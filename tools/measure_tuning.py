"""
measure_tuning.py - 04_tuning.sql 의 측정 쿼리(A, B, C1, C2)를 실행해 IO/TIME 통계와 실행 계획을 JSON 으로 저장

사용법
    python tools/measure_tuning.py <phase> <out.json> [A,B,C1,C2]
    예) python tools/measure_tuning.py after docs/tmp/after.json A,B,C1,C2

- warm: 캐시를 비우지 않고 쿼리당 3회 (SET STATISTICS IO, TIME)
- cold: CHECKPOINT + DBCC DROPCLEANBUFFERS 후 1회  ※ 개발 PC 전용, 운영 서버에서 실행 금지
- plan: 별도 1회 실행의 실제 실행 계획(SET STATISTICS XML)에서 인덱스 접근 연산만 추출
- 메시지 파싱은 한국어 SQL Server 메시지(검색 횟수, 논리적 읽기 ...) 기준
"""
import sys, re, json, time, pyodbc
import xml.etree.ElementTree as ET
QUERIES = {
 "A": "SELECT COUNT(*) AS cnt\nFROM dbo.fact_checkup\nWHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);",
 "B": "SELECT age_code, sex_code, AVG(CAST(fasting_glucose AS FLOAT)) AS avg_glucose\nFROM dbo.fact_checkup\nWHERE base_year = (SELECT MAX(base_year) FROM dbo.fact_checkup)\nGROUP BY age_code, sex_code;",
 "C1": "SELECT COUNT(*) AS cnt\nFROM dbo.fact_checkup\nWHERE CAST(base_year AS VARCHAR(4)) = '2023';",
 "C2": "SELECT COUNT(*) AS cnt\nFROM dbo.fact_checkup\nWHERE base_year = 2023;",
}
phase, outp = sys.argv[1], sys.argv[2]
if len(sys.argv) > 3: QUERIES = {k: QUERIES[k] for k in sys.argv[3].split(",")}   # 측정할 쿼리만
c = pyodbc.connect(r"DRIVER={ODBC Driver 18 for SQL Server};SERVER=localhost\SQLEXPRESS;DATABASE=healthdb;Trusted_Connection=yes;TrustServerCertificate=yes;", autocommit=True)
cur = c.cursor()
num = lambda pat, s: int(re.search(pat, s).group(1))

def run(sql):
    cur.execute("SET STATISTICS IO ON; SET STATISTICS TIME ON;")
    t0 = time.perf_counter()
    cur.execute(sql)
    msgs = list(cur.messages); rows = cur.fetchall()
    while cur.nextset(): msgs += cur.messages
    msgs += cur.messages
    wall = (time.perf_counter() - t0) * 1000
    cur.execute("SET STATISTICS IO OFF; SET STATISTICS TIME OFF;")
    io = {}
    for code, m in msgs:
        if "(3615)" in code:
            t = re.search(r"'([^']+)'", m).group(1)
            d = io.setdefault(t, dict(scan=0, logical=0, physical=0, readahead=0))
            d["scan"] += num(r"검색 횟수 (\d+)", m); d["logical"] += num(r"논리적 읽기 (\d+)", m)
            d["physical"] += num(r"(?<!lob )물리적 읽기 (\d+)", m); d["readahead"] += num(r"(?<!lob )(?<!서버 )미리 읽기 (\d+)", m)
    ex = [m for code, m in msgs if "(3612)" in code][-1]
    return dict(io=io, cpu_ms=num(r"CPU 시간 = (\d+)ms", ex), elapsed_ms=num(r"경과 시간 = (\d+)ms", ex),
                client_ms=round(wall), result=[list(r) for r in rows][:3], nrows=len(rows))

def plan(sql):
    cur.execute("SET STATISTICS XML ON;")
    cur.execute(sql); cur.fetchall(); cur.nextset()
    xml = cur.fetchone()[0]
    while cur.nextset(): pass
    cur.execute("SET STATISTICS XML OFF;")
    ns = {"p": "http://schemas.microsoft.com/sqlserver/2004/07/showplan"}
    ops = []
    for r in ET.fromstring(xml).iter("{%s}RelOp" % ns["p"]):
        o = r.find("./*/p:Object", ns)
        if r.get("PhysicalOp") in ("Clustered Index Scan", "Clustered Index Seek", "Index Scan", "Index Seek", "Table Scan") and o is not None:
            ops.append(f'{r.get("PhysicalOp")} ({o.get("Index","").strip("[]")}) actual_rows={r.find("p:RunTimeInformation/p:RunTimeCountersPerThread", ns).get("ActualRows")}')
    return dict(ops=ops, dop=re.search(r'DegreeOfParallelism="(\d+)"', xml).group(1) if 'DegreeOfParallelism="' in xml else "1")

res = dict(phase=phase, queries=QUERIES, indexes=[list(r) for r in cur.execute(
    "SELECT name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.fact_checkup') AND name IS NOT NULL")], warm={}, cold={}, plan={})
for k, q in QUERIES.items():
    res["warm"][k] = [run(q) for _ in range(3)]
for k, q in QUERIES.items():
    cur.execute("CHECKPOINT;"); cur.execute("DBCC DROPCLEANBUFFERS;")
    res["cold"][k] = run(q)
for k, q in QUERIES.items():
    res["plan"][k] = plan(q)
json.dump(res, open(outp, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
print("saved", outp)
