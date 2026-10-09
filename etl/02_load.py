"""
02_load.py - 건강검진 CSV를 정제해서 SQL Server(healthdb.dbo.fact_checkup)에 적재

사용법 (Windows 명령 프롬프트 / PowerShell)
    pip install pandas pyodbc
    python 02_load.py "C:\\data\\건강검진정보_2022.csv"  "C:\\data\\건강검진정보_2021.csv"

환경에 맞게 아래 SERVER 값만 확인하세요. (SQL Server Express 기본: localhost\\SQLEXPRESS)
컬럼명이 달라서 'COLUMN MAP' 경고가 나오면 COLMAP을 고치세요.
"""
import os
import re
import sys

import numpy as np
import pandas as pd

SERVER = os.environ.get("MSSQL_SERVER", r"localhost\SQLEXPRESS")
DATABASE = os.environ.get("MSSQL_DB", "healthdb")
CHUNK = 50_000

# 원본 컬럼명(공백 제거/소문자로 비교) -> DB 컬럼명. 받은 파일에 맞게 고치세요.
COLMAP = {
    "기준년도": "base_year", "기준연도": "base_year",
    "가입자일련번호": "member_id", "가입자일련번호(식별번호)": "member_id",
    "시도코드": "sido_code",
    "성별코드": "sex_code", "성별": "sex_code",
    "연령대코드(5세단위)": "age_code", "연령대코드": "age_code",
    "신장(5cm단위)": "height_cm", "신장(5㎝단위)": "height_cm", "신장": "height_cm",
    "체중(5kg단위)": "weight_kg", "체중": "weight_kg",
    "허리둘레": "waist_cm",
    "수축기혈압": "sbp",
    "이완기혈압": "dbp",
    "식전혈당(공복혈당)": "fasting_glucose", "공복혈당": "fasting_glucose",
    "총콜레스테롤": "total_chol",
    "트리글리세라이드": "triglyceride",
    "hdl콜레스테롤": "hdl",
    "ldl콜레스테롤": "ldl",
    "혈색소": "hemoglobin",
    "혈청크레아티닌": "creatinine",
    "혈청지오티(ast)": "ast",
    "혈청지피티(alt)": "alt",
    "감마지티피": "gamma_gtp", "감마지티피(γ-gtp)": "gamma_gtp",
    "흡연상태": "smoking_status",
    "음주여부": "drinking_yn",
}

KEY_COLS = ["base_year", "member_id", "sido_code", "sex_code", "age_code"]
VALUE_COLS = ["height_cm", "weight_kg", "waist_cm", "sbp", "dbp", "fasting_glucose",
              "total_chol", "triglyceride", "hdl", "ldl", "hemoglobin", "creatinine",
              "ast", "alt", "gamma_gtp", "smoking_status", "drinking_yn"]
DB_COLS = KEY_COLS + VALUE_COLS


def norm(name: str) -> str:
    return re.sub(r"\s+", "", str(name)).lower()


def read_csv_chunks(path, chunksize=CHUNK):
    """CSV 인코딩을 자동으로 시도 (공공데이터는 cp949인 경우가 많음)."""
    last_err = None
    for enc in ("utf-8-sig", "cp949"):
        try:
            # 첫 청크를 읽어 보며 인코딩이 맞는지 확인
            reader = pd.read_csv(path, encoding=enc, chunksize=chunksize, low_memory=False)
            first = next(reader)
            def gen(first=first, reader=reader):
                yield first
                yield from reader
            print(f"  인코딩: {enc}")
            return gen()
        except UnicodeDecodeError as e:
            last_err = e
    raise last_err


def map_columns(df: pd.DataFrame) -> pd.DataFrame:
    rename = {}
    for c in df.columns:
        key = norm(c)
        if key in COLMAP:
            rename[c] = COLMAP[key]
    df = df.rename(columns=rename)
    return df


def clean_chunk(df: pd.DataFrame, valid_sido, valid_sex, valid_age):
    """정제하고 (깨끗한 DataFrame, 제외 사유별 건수)를 돌려준다."""
    df = map_columns(df)
    reasons = {}
    n0 = len(df)

    for c in DB_COLS:
        if c not in df.columns:
            df[c] = np.nan
    df = df[DB_COLS].copy()
    for c in DB_COLS:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    # 1) 필수 키가 비어 있는 행 제외
    m = df[KEY_COLS].isna().any(axis=1)
    reasons["필수값 없음"] = int(m.sum()); df = df[~m]

    # 2) 코드 테이블에 없는 값 제외 (FK 위반 방지) - 어떤 값이 빠졌는지 확인용으로 보관
    unk = {}
    for col, valid in (("sido_code", valid_sido), ("sex_code", valid_sex), ("age_code", valid_age)):
        bad = ~df[col].astype("int64").isin(valid)
        if bad.any():
            unk[col] = sorted(df.loc[bad, col].astype("int64").unique().tolist())
        reasons[f"{col} 코드표에 없음"] = int(bad.sum()); df = df[~bad]
    reasons["_unknown_codes"] = unk

    # 3) 정수형 컬럼 변환 (NaN은 None으로 넣기 위해 object 사용)
    return df, reasons


DEC_COLS = {"waist_cm", "hemoglobin", "creatinine"}      # DECIMAL 컬럼, 나머지는 정수


def to_rows(df: pd.DataFrame):
    """(행 목록, 정수 컬럼에서 반올림한 값 개수)를 돌려준다."""
    out = df.astype(object).where(pd.notna(df), None)
    rows, rounded = [], 0
    for rec in out.itertuples(index=False, name=None):
        row = []
        for c, v in zip(DB_COLS, rec):
            if v is None:
                row.append(None)
            elif c in DEC_COLS:
                row.append(float(v))
            else:
                if v != int(v):                # 정수 컬럼의 소수값(예: 84.7)은 버리지 않고 반올림
                    rounded += 1
                row.append(int(round(v)))
        rows.append(tuple(row))
    return rows, rounded


INSERT_SQL = ("INSERT INTO dbo.fact_checkup (" + ",".join(DB_COLS) + ") VALUES (" +
              ",".join("?" * len(DB_COLS)) + ")")


def insert_chunk(conn, df):
    rows, rounded = to_rows(df)
    if not rows:
        return 0, 0
    cur = conn.cursor()
    if hasattr(cur, "fast_executemany"):
        cur.fast_executemany = True           # pyodbc: 대량 INSERT 속도 향상
    cur.executemany(INSERT_SQL, rows)
    conn.commit()
    return len(rows), rounded


PREFERRED_DRIVERS = ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")


def connect():
    import pyodbc
    installed = pyodbc.drivers()
    driver = next((d for d in PREFERRED_DRIVERS if d in installed), None)
    if driver is None:
        sys.exit("ODBC 드라이버가 없습니다. 'ODBC Driver 17/18 for SQL Server'를 설치하세요.")
    conn_str = (f"DRIVER={{{driver}}};SERVER={SERVER};DATABASE={DATABASE};"
                "Trusted_Connection=yes;TrustServerCertificate=yes;")
    print(f"연결: driver={driver}, server={SERVER}, db={DATABASE}")   # 연결 문자열 전체는 출력하지 않음
    return pyodbc.connect(conn_str)


def load_codes(conn):
    cur = conn.cursor()
    s = {r[0] for r in cur.execute("SELECT sido_code FROM dbo.dim_sido")}
    x = {r[0] for r in cur.execute("SELECT sex_code FROM dbo.dim_sex")}
    a = {r[0] for r in cur.execute("SELECT age_code FROM dbo.dim_age_group")}
    return s, x, a


def log_etl(conn, path, read, loaded, dropped, note):
    cur = conn.cursor()
    cur.execute("INSERT INTO dbo.etl_log (source_file, rows_read, rows_loaded, rows_dropped, note) "
                "VALUES (?,?,?,?,?)", (os.path.basename(path), read, loaded, dropped, note[:500]))
    conn.commit()


def load_file(conn, path, codes):
    valid_sido, valid_sex, valid_age = codes
    print(f"\n== {path}")
    read = loaded = rounded = 0
    drop_total, unknown = {}, {}
    warned = False
    for i, chunk in enumerate(read_csv_chunks(path), 1):
        if not warned:
            mapped = set(map_columns(chunk.head(1)).columns)
            missing = [c for c in DB_COLS if c not in mapped]
            extra = [c for c in chunk.columns if norm(c) not in COLMAP]
            if missing:
                print(f"  [COLUMN MAP] 매핑되지 않은 DB 컬럼(NULL로 들어감): {missing}")
            if extra:
                print(f"  [COLUMN MAP] 무시되는 원본 컬럼: {extra}")
            warned = True
        read += len(chunk)
        clean, reasons = clean_chunk(chunk, valid_sido, valid_sex, valid_age)
        for k, v in reasons.pop("_unknown_codes").items():
            unknown.setdefault(k, set()).update(v)
        for k, v in reasons.items():
            drop_total[k] = drop_total.get(k, 0) + v
        n, r = insert_chunk(conn, clean)
        loaded += n
        rounded += r
        print(f"  청크 {i}: 읽음 {read:,} / 적재 {loaded:,}")
    dropped = read - loaded
    note = "; ".join(f"{k} {v}" for k, v in drop_total.items() if v) or "제외 없음"
    if unknown:
        note += f" | 코드표에 없던 값: { {k: sorted(v) for k, v in unknown.items()} }"
    print(f"  완료: 읽음 {read:,}, 적재 {loaded:,}, 제외 {dropped:,}\n  사유: {note}")
    log_etl(conn, path, read, loaded, dropped, note)
    print(f"  정수 컬럼 소수값 반올림: {rounded:,}건")


def main(paths):
    if not paths:
        sys.exit(__doc__)
    conn = connect()
    codes = load_codes(conn)
    for p in paths:
        load_file(conn, p, codes)
    print("\n확인: SELECT COUNT(*) FROM dbo.fact_checkup;  /  SELECT * FROM dbo.etl_log;")


if __name__ == "__main__":
    main(sys.argv[1:])
