"""질문 목록(eval/questions.csv)을 자동 채점합니다.
- LLM이 만든 SQL과 정답 SQL을 각각 실행해 '결과'가 같은지 비교합니다(SQL 문장 모양은 비교하지 않음).
- 결과는 eval/results.csv 에 저장됩니다.
실행:  python eval\\run_eval.py
"""
import csv
import os
import sys
from decimal import Decimal
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "app"))
load_dotenv(ROOT / ".env")

from text2sql import make_sql, is_safe  # noqa: E402

engine = create_engine(os.environ["DB_URI"])


def run(sql: str):
    with engine.connect() as conn:
        return [tuple(r) for r in conn.execute(text(sql)).fetchall()]


def norm(v):
    if isinstance(v, (Decimal, float)):
        return float(v)
    return v


def same(a, b, tol=0.01) -> bool:
    if len(a) != len(b):
        return False
    a = sorted([tuple(norm(x) for x in r) for r in a], key=str)
    b = sorted([tuple(norm(x) for x in r) for r in b], key=str)
    for ra, rb in zip(a, b):
        if len(ra) != len(rb):
            return False
        for x, y in zip(ra, rb):
            if isinstance(x, float) or isinstance(y, float):
                try:
                    if abs(float(x) - float(y)) > tol:
                        return False
                except (TypeError, ValueError):
                    return False
            elif x != y:
                return False
    return True


def main():
    qpath = ROOT / "eval" / "questions.csv"
    with open(qpath, encoding="utf-8-sig", newline="") as f:
        questions = [r for r in csv.DictReader(f) if r["질문"].strip() and r["정답SQL"].strip()]

    out_rows, ok = [], 0
    for r in questions:
        qid, q, gold_sql = r["id"], r["질문"], r["정답SQL"]
        gold = run(gold_sql)
        gen_sql, gen, status, err = "", None, "X", ""
        try:
            gen_sql = make_sql(q)
            if not is_safe(gen_sql):
                err = "안전하지 않은 SQL(차단)"
            else:
                gen = run(gen_sql)
                if same(gen, gold):
                    status = "O"
        except Exception as e:
            err = f"실행 오류: {str(e)[:150]}"
        ok += status == "O"
        print(f"[{qid}] {status}  {q}")
        out_rows.append({"id": qid, "질문": q, "정답결과": gold, "LLM생성SQL": gen_sql.replace("\n", " "),
                         "LLM결과": gen, "결과일치": status, "오류": err})

    with open(ROOT / "eval" / "results.csv", "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        w.writerows(out_rows)
    print(f"\n정답 일치: {ok}/{len(out_rows)}  ({ok / len(out_rows):.0%})")
    print("모델:", os.getenv("LLM_MODEL"))
    print("상세 결과: eval\\results.csv  (틀린 질문은 LLM생성SQL과 정답결과를 비교해 오류 유형을 기록하세요)")


if __name__ == "__main__":
    main()
