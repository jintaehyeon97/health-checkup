"""Step 1: SQL Server 연결만 확인합니다. (LLM은 아직 쓰지 않음)"""
import os
from dotenv import load_dotenv
from langchain_community.utilities import SQLDatabase

load_dotenv()

tables = [t.strip() for t in os.getenv("DB_TABLES", "fact_checkup").split(",")]
db = SQLDatabase.from_uri(
    os.environ["DB_URI"],
    include_tables=tables,
    sample_rows_in_table_info=0,  # 예시 행을 LLM에 보내지 않음(개인정보 보호)
)

print("DB 종류:", db.dialect)
print("조회 가능한 테이블:", db.get_usable_table_names())
print("행 수:", db.run(f"SELECT COUNT(*) FROM {tables[0]}"))
