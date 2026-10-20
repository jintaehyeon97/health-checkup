"""Step 3: 한국어 질문 -> SQL 생성 -> 안전 검사 -> 실행 -> 쉬운 설명"""
import os
import re
import sys
from dotenv import load_dotenv
from langchain_community.utilities import SQLDatabase
from langchain.chat_models import init_chat_model

load_dotenv()

TABLES = [t.strip() for t in os.getenv("DB_TABLES", "fact_checkup").split(",")]
db = SQLDatabase.from_uri(
    os.environ["DB_URI"],
    include_tables=TABLES,
    sample_rows_in_table_info=0,
)
llm = init_chat_model(os.environ["LLM_MODEL"])

def to_text(msg) -> str:
    """LLM 응답을 문자열로 바꿉니다. (모델에 따라 content가 문자열 또는 블록 목록으로 옴)"""
    c = msg.content
    if isinstance(c, str):
        return c
    return "".join(b.get("text", "") if isinstance(b, dict) else str(b) for b in c)


# 코드값 설명은 실제 코드표를 확인해서 채우세요. (추측하지 않도록 LLM에 알려주는 용도)
CODE_NOTES = """
- sido_code: 시도 코드 (예: 11 = 서울)
- sex_code, age_code: 코드표 기준 (실제 값 확인 후 여기에 적기)
- sbp: 수축기 혈압, dbp: 이완기 혈압
"""

BANNED = r"\b(insert|update|delete|drop|alter|truncate|create|grant|revoke|merge|exec|execute|into|openrowset|opendatasource|xp_\w+|sp_\w+)\b"


def make_sql(question: str) -> str:
    prompt = f"""너는 SQL Server(T-SQL) 전문가다. 아래 테이블 구조만 사용해 SELECT 쿼리 한 개만 출력해라.
설명과 코드블록 표시 없이 SQL만 출력한다. 행을 나열하는 쿼리는 SELECT TOP 50 이하로 제한한다. (LIMIT 문법은 쓰지 않는다)
구조에 없는 컬럼이나 코드값은 추측하지 마라.

[코드값 메모]{CODE_NOTES}
[테이블 구조]
{db.get_table_info()}

질문: {question}"""
    sql = to_text(llm.invoke(prompt)).strip()
    return re.sub(r"^```(?:sql)?|```$", "", sql, flags=re.I | re.M).strip()


def is_safe(sql: str) -> bool:
    s = sql.strip().rstrip(";").lower()
    return s.startswith("select") and ";" not in s and not re.search(BANNED, s)


def ask(question: str):
    sql = make_sql(question)
    if not is_safe(sql):
        return sql, None, "안전하지 않은 쿼리라 실행하지 않았습니다."
    try:
        result = db.run(sql)
    except Exception as e:  # SQL 오류도 기록해 두면 평가 때 오류 유형 분석에 쓸 수 있음
        return sql, None, f"SQL 실행 오류: {e}"
    answer = to_text(llm.invoke(
        f"질문: {question}\nSQL: {sql}\n결과: {result}\n"
        "결과만 근거로 한국어로 2문장 이내로 설명해라. 마크다운(**)이나 목록은 쓰지 말고, 결과에 없는 내용은 추측하지 마라. "
        "마지막에 '진단이 아닌 참고용입니다.'를 덧붙여라."
    ))
    return sql, result, answer


if __name__ == "__main__":
    q = " ".join(sys.argv[1:]) or "서울에서 수축기 혈압 140 이상 또는 이완기 혈압 90 이상인 사람은 몇 명이야?"
    sql, result, answer = ask(q)
    print("질문:", q)
    print("SQL :", sql)
    print("결과:", result)
    print("설명:", answer)
