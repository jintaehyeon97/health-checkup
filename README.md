# 건강검진 공개 데이터로 만든 SQL Server 운영·튜닝 포트폴리오

국민건강보험공단 건강검진정보(2023년, 1,000,000행) CSV 를 SQL Server 에 적재하고,
**스키마 설계 → ETL 적재 → 분석 쿼리 → 인덱스 튜닝(전/후 측정) → 데이터 품질 점검 → 백업·복구 검증**까지
DB 운영 업무 흐름을 3일 동안 직접 수행한 프로젝트입니다.

> README 의 모든 수치는 `docs/` 의 측정 기록(`day2_analysis.md`, `day2_results.md`, `day3_quality.md`, `day3_backup.md`)에서 가져온 실제 실행 결과입니다. 추정치는 쓰지 않았습니다.
> 마지막 확장인 'AI 자연어 질의 프로토타입' 절의 수치만 `eval/results.csv`에서 가져왔습니다.

## 사용 기술

| 구분 | 내용 |
|---|---|
| DBMS | SQL Server 2025 Express (RTM 17.0.1000.7, 64-bit), SSMS |
| 언어 | T-SQL, Python 3.13 |
| 라이브러리 | pandas 2.3.0, pyodbc 5.3.0 |
| AI (확장) | LangChain, SQLAlchemy, Claude API(`anthropic:claude-opus-5-5`) — [AI 자연어 질의 프로토타입](#ai-자연어-질의-프로토타입-app-eval) 참고 |
| 연결 | ODBC Driver 18 for SQL Server, Windows 인증(`Trusted_Connection=yes`) — 비밀번호를 쓰지 않음 |
| 환경 | Windows 11, 단일 PC |

## 데이터 출처

- 국민건강보험공단 건강검진정보 2023년 (공공데이터포털), 1,000,000행 × 33컬럼, 인코딩 cp949
- 개인을 식별할 수 있는 정보는 없고(공공데이터포털 설명 기준), 가입자 일련번호는 식별 불가 번호입니다.
- **원본 CSV 는 이 저장소에 포함하지 않았습니다** (`data/` 는 `.gitignore` 처리). 직접 내려받아 `data/` 에 두고 실행하세요.
- **데이터 이용 조건(라이선스·출처 표시 등)은 공공데이터포털의 해당 데이터 페이지에서 직접 확인해야 합니다.**

## 폴더 구조와 실행 순서

```
medi_Project/
├─ data/                      원본 CSV (저장소 미포함)
├─ sql/
│  ├─ 01_schema.sql           DB·테이블 생성 + 코드표 입력
│  ├─ 03_analysis.sql         분석 쿼리 Q1~Q6b
│  ├─ 04_tuning.sql           인덱스 튜닝 전/후 측정 쿼리와 인덱스 정의
│  ├─ 05_quality_checks.sql   데이터 품질 점검 (+ 보충 점검)
│  └─ 06_backup.sql           전체 백업, 검증, 복구 연습
├─ etl/02_load.py             CSV → fact_checkup 적재
├─ tools/measure_tuning.py    04의 측정을 자동화 (STATISTICS IO/TIME + 실행 계획 → JSON)
├─ docker-compose.yml, docker/ SQL Server 컨테이너 환경과 복구 스크립트
├─ app/                       AI 자연어 질의 프로토타입 (Text-to-SQL)
├─ eval/                      평가 질문·채점 코드·결과
└─ docs/
   ├─ day2_analysis.md        분석 쿼리 실행 결과
   ├─ day2_results.md         튜닝 전/후 측정 기록
   ├─ day3_quality.md         품질 점검 결과
   └─ day3_backup.md          백업·복구 결과
```

| 순서 | 실행 | 비고 |
|---|---|---|
| 1 | `sql/01_schema.sql` (SSMS) | ⚠️ 재실행하면 기존 테이블을 DROP 후 다시 만듭니다. 적재 후에는 다시 실행하지 마세요. |
| 2 | `python etl/02_load.py "data/<CSV 파일명>"` | 서버/DB 는 환경변수 `MSSQL_SERVER`, `MSSQL_DB` 로 바꿀 수 있음 (기본 `localhost\SQLEXPRESS`, `healthdb`) |
| 3 | `sql/03_analysis.sql` | 분석 쿼리 |
| 4 | `sql/04_tuning.sql` 또는 `python tools/measure_tuning.py <phase> <out.json>` | ⚠️ `DBCC DROPCLEANBUFFERS` 포함 — 개발 PC 전용, 운영 서버 금지 |
| 5 | `sql/05_quality_checks.sql` | |
| 6 | `sql/06_backup.sql` | 백업 경로는 `SERVERPROPERTY('InstanceDefaultBackupPath')` 로 구함 |

## ERD

```
dim_sido                 dim_sex                  dim_age_group
─────────────────        ─────────────────        ─────────────────────
PK sido_code SMALLINT    PK sex_code TINYINT      PK age_code TINYINT
   sido_name NVARCHAR(20)   sex_name NVARCHAR(10)    age_label NVARCHAR(20)
   (17행)                   (2행)                    (18행, 5세 단위)
        │ 1                      │ 1                       │ 1
        │                        │                         │
        │ N                      │ N                       │ N
        └──────────────┬─────────┴──────────┬──────────────┘
                       ▼                    ▼
fact_checkup (1,000,000행)
──────────────────────────────────────────────────────────────
PK checkup_id      BIGINT IDENTITY  (CLUSTERED)
   base_year       SMALLINT  NOT NULL
   member_id       BIGINT    NOT NULL   가입자 일련번호(식별 불가)
FK sido_code       SMALLINT  NOT NULL → dim_sido
FK sex_code        TINYINT   NOT NULL → dim_sex
FK age_code        TINYINT   NOT NULL → dim_age_group
   height_cm, weight_kg, sbp, dbp, fasting_glucose, total_chol,
   triglyceride, hdl, ldl, ast, alt, gamma_gtp        SMALLINT NULL
   waist_cm DECIMAL(5,1), hemoglobin DECIMAL(4,1), creatinine DECIMAL(4,1)  NULL
   smoking_status, drinking_yn                         TINYINT NULL
IX ix_checkup_sido_bp       (sido_code) INCLUDE (sbp, dbp)
IX ix_checkup_year_age_sex  (base_year, age_code, sex_code) INCLUDE (fasting_glucose)

etl_log (적재 이력, FK 없음)
──────────────────────────────────────────────────────────────
PK log_id INT IDENTITY
   loaded_at DATETIME2(0), source_file NVARCHAR(260),
   rows_read, rows_loaded, rows_dropped INT, note NVARCHAR(500)
```

## 적재 방식 (etl/02_load.py)

- **청크 적재**: 50,000행 단위로 읽어 `fast_executemany` 로 INSERT, 청크마다 커밋
- **인코딩 자동 판별**: `utf-8-sig` 시도 → 실패 시 `cp949` (이 파일은 cp949)
- **컬럼 매핑**: CSV 헤더를 직접 읽어 확인한 뒤 `COLMAP` 으로 22개 DB 컬럼에 매핑. 시력·청력·요단백·구강 관련 11개 컬럼은 적재 대상에서 제외
- **정제 규칙**: 필수 키(연도·가입자번호·시도·성별·연령대) 결측 행과 코드표에 없는 코드 행은 제외하고 사유별 건수를 `etl_log` 에 기록. 정수 컬럼의 소수값은 반올림해 적재하고 건수를 로그에 출력
- **드라이버 선택**: 구형 `SQL Server` 드라이버가 아니라 `ODBC Driver 18` → `17` 순으로 선택. 연결 문자열 전체는 로그에 출력하지 않음

적재 결과 (`etl_log` 와 테이블 행 수 대조):

| rows_read | rows_loaded | rows_dropped | fact_checkup 행 수 | 정수 컬럼 소수값 반올림 |
|---:|---:|---:|---:|---:|
| 1,000,000 | 1,000,000 | 0 | 1,000,000 | 6건 (triglyceride 2, hdl 4) |

### 실행 화면 (SSMS)

**객체 탐색기** — 코드표 3개 + `fact_checkup` + `etl_log`, 그리고 인덱스 3개 (PK 클러스터드 1 + 비클러스터드 2)

<img src="images/01_tables.png" alt="객체 탐색기: 테이블 5개와 인덱스 3개" width="380">

**적재 검증** — `fact_checkup` 1,000,000행, `etl_log` 의 rows_read / rows_loaded / rows_dropped = 1,000,000 / 1,000,000 / 0

<img src="images/02_load_check.jpg" alt="적재 검증: 행 수와 etl_log" width="600">

**데이터 샘플** — 코드표(시도·성별·연령대)를 JOIN 한 10행

<img src="images/03_sample_join.jpg" alt="데이터 샘플: 코드표 JOIN 결과" width="480">

## 분석 쿼리 (sql/03_analysis.sql)

| 쿼리 | 내용 | 사용 기법 |
|---|---|---|
| Q1 | 연령대 × 성별 평균 수축기혈압·공복혈당·BMI | JOIN + GROUP BY |
| Q2 | 시도별 '혈압 높음(수축기 ≥140 또는 이완기 ≥90)' 비율 | 조건부 집계 (`SUM(CASE ...)`) |
| Q3 | 연령대별로 평균 공복혈당이 높은 시도 순위 | CTE + `RANK() OVER (PARTITION BY ...)` |
| Q4 | 전체 평균보다 LDL 이 높은 사람의 성별 건수와 비율 (분모 = LDL 값이 있는 행) | 서브쿼리 + `CROSS JOIN` |
| Q5 | 흡연 상태별 HDL / 중성지방 평균 | GROUP BY |
| Q6a | 연령대별 평균 수축기혈압과 이전 연령대 대비 증감 | `LAG() OVER (ORDER BY ...)` |
| Q6b | 시도별 평균 수축기혈압과 전국 평균(가중) 대비 차이 | 윈도우 집계 `SUM() OVER ()` |

- 원래 Q6 는 연도별 추이(LAG)였으나, 적재 데이터가 2023년 한 해뿐이라 Q6a/Q6b 로 바꿨습니다.
- 혈압·혈당 기준은 분석 예시를 위한 단순 기준이며 의학적 진단 기준이 아닙니다.

### 결과 요약 (docs/day2_analysis.md, 2026-10-09 실행)

> ⚠️ 시도 비교(Q2, Q3, Q6b)는 **연령 보정을 하지 않은 값**입니다. 흡연 코드(1/2/3)의 의미는 스키마 주석 기준이며 **공식 코드표로 확인하지 않았습니다.**

| 쿼리 | 한 줄 요약 | exec elapsed ms |
|---|---|---:|
| Q1 | 확인한 20~44세 구간(상위 10행)에서 모든 연령대의 남성 평균 수축기혈압·공복혈당·BMI 가 여성보다 높음 (예: 40-44세 수축기혈압 남 124.64 / 여 116.12) | 770 |
| Q2 | '혈압 높음' 비율은 강원 17.78% 가 가장 높고 광주 10.34% 가 가장 낮음 (연령 보정 없음) | 188 |
| Q3 | 20-24세에서 평균 공복혈당 1위는 전북 92.21, 10위 충남 90.81 로 1~10위 차이는 1.40 (연령 보정 없음) | 252 |
| Q4 | LDL 측정자 중 전체 평균보다 높은 비율은 남 48.17% (86,889 / 180,378), 여 49.09% (74,799 / 152,375) | 193 |
| Q5 | 흡연 코드 1 → 2 → 3 순으로 평균 HDL 59.16 → 54.17 → 52.73 감소, 평균 중성지방 115.29 → 138.25 → 166.94 증가 (코드 의미 미확인) | 220 |
| Q6a | 평균 수축기혈압이 20-24세 115.52 에서 80-84세 133.46 까지 매 구간 증가, 85+ 는 132.33 으로 직전 구간보다 1.13 낮음 | 195 |
| Q6b | 전국 가중평균 122.97 대비 충남 +2.22 가 가장 높고 부산 -2.05 가 가장 낮음 (연령 보정 없음) | 146 |

실행 시간은 쿼리당 1회 측정값이며, 인덱스 2개 생성 이후 상태에서 실행했습니다.

<img src="images/08_q2_sido_bp.jpg" alt="Q2 시도별 혈압 높음 비율 (분모 = 전체 행)" width="440">

> 위 캡처는 단순화한 쿼리로 **분모를 `COUNT(*)`(sbp/dbp 가 NULL 인 행 포함)** 로 잡아 강원 17.64% 로 나옵니다. 위 표의 17.78% 는 `sql/03_analysis.sql` 의 Q2 로, 혈압 값이 있는 행만 분모로 한 값입니다. 순위 경향(강원 최고, 광주 최저)은 같습니다.

## 인덱스 튜닝 전/후 (docs/day2_results.md)

측정 방법: `SET STATISTICS IO, TIME`, 캐시를 비우지 않은 **warm 3회 평균**과 `CHECKPOINT; DBCC DROPCLEANBUFFERS;` 후 **cold 1회**. 사용 인덱스는 실제 실행 계획으로 확인.

```sql
-- A
SELECT COUNT(*) FROM dbo.fact_checkup WHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);
-- B
SELECT age_code, sex_code, AVG(CAST(fasting_glucose AS FLOAT)) FROM dbo.fact_checkup
WHERE base_year = (SELECT MAX(base_year) FROM dbo.fact_checkup) GROUP BY age_code, sex_code;
-- C1 (non-sargable)
SELECT COUNT(*) FROM dbo.fact_checkup WHERE CAST(base_year AS VARCHAR(4)) = '2023';
-- C2 (sargable)
SELECT COUNT(*) FROM dbo.fact_checkup WHERE base_year = 2023;
```

| 쿼리 | logical reads 전 → 후 | 감소율 | warm elapsed ms 전 → 후 | 증감률 | cold elapsed ms 전 → 후 | 실행 계획 전 → 후 |
|---|---|---:|---|---:|---|---|
| A | 9,219 → 438 | -95.2% | 60.3 → 11.3 | -81.2% | 84 → 13 | Clustered Index Scan → **Index Seek** (ix_checkup_sido_bp) |
| B | 18,438 → 2,488 | -86.5% | 318.0 → 155.0 | -51.3% | 363 → 162 | Clustered Index Scan ×2 → Index Scan ×2 (ix_checkup_year_age_sex) |
| C1 | 9,219 → 2,485 | -73.0% | 172.7 → 174.3 | **+1.0%** | 191 → 182 | Clustered Index Scan → Index Scan (ix_checkup_year_age_sex) |
| C2 | 9,219 → 2,485 | -73.0% | 87.0 → 49.7 | -42.9% | 123 → 57 | Clustered Index Scan → Index Seek (ix_checkup_year_age_sex), 1,000,000행 전부 |

인덱스 생성: ix_checkup_sido_bp 1,226 ms / 2,489 페이지(reserved), ix_checkup_year_age_sex 1,813 ms / 2,489 페이지 (테이블 클러스터드 인덱스는 9,225 페이지).

**측정 요약 (실측값, `docs/day2_results.md`)**

<img src="images/04_tuning_summary.png" alt="인덱스 튜닝 전/후: 논리적 읽기와 실행 시간" width="720">

**실행 계획 (쿼리 A)** — 같은 쿼리에서 인덱스 힌트만 다릅니다. BEFORE 는 `WITH (INDEX(1))` 로 클러스터드 인덱스 스캔을 강제했습니다.

<img src="images/04_tuning_before_plan.jpg" alt="BEFORE: Clustered Index Scan, 읽은 행 1,000,000 / 실제 행 23,884" width="480">

<img src="images/05_tuning_after_plan.jpg" alt="AFTER: Index Seek (ix_checkup_sido_bp), 읽은 행 175,300 / 실제 행 23,884" width="480">

**인덱스 크기** — PK 9,219 / ix_checkup_sido_bp 2,484 / ix_checkup_year_age_sex 2,485 페이지 (used)

<img src="images/07_index_list.jpg" alt="인덱스 목록과 사용 페이지 수" width="520">

**정리**

- **A**: 커버링 인덱스로 Scan 이 Seek 으로 바뀌어 효과가 가장 컸습니다.
- **B**: Seek 이 아니라 더 좁은 인덱스를 Scan 한 효과입니다. MAX 서브쿼리는 인덱스에서 1행만 읽었습니다.
- **C1**: 인덱스를 쓰면서 logical reads 는 줄었지만 **실행 시간은 줄지 않았습니다 (효과 없음).**
- **C2**: 인덱스가 없을 때도 C1 → C2 재작성만으로 warm 172.7 → 87.0 ms. 인덱스 후 Seek 이 됐지만 `base_year` 값이 하나뿐이라 인덱스 전체를 읽었습니다.

## 데이터 품질 점검 (docs/day3_quality.md)

| 점검 | 결과 |
|---|---|
| 중복 (base_year + member_id) | 0건 |
| 범위 이탈 (05 예시 기준) | sbp 0 / dbp 3 / fasting_glucose 7 / height_cm 0 |
| 범위 이탈 (보충: 허리둘레 40~200cm) | 12건 (999.0 이 5건, 그 외 7.5 ~ 480.0) |
| 논리 모순 (수축기 < 이완기) | 0건 |
| 결측 | 키 5개 컬럼 0% / 총콜레스테롤·중성지방·HDL 66.14% / LDL 66.72% / 혈압·혈액검사 0.57~0.58% |
| 적재 건수 대조 | rows_read 1,000,000 = rows_loaded 1,000,000 + rows_dropped 0 → OK |

범위 밖 값은 원본 설명서로 원인을 확인하지 못해 **삭제·수정하지 않고 원본 그대로 두었습니다.**

## 백업·복구 (docs/day3_backup.md)

| 단계 | 결과 |
|---|---|
| 전체 백업 (`WITH INIT, CHECKSUM`) | 14,834 페이지, **0.227초**, backup_size 121,595,904 bytes (약 116.0 MiB), 체크섬 포함 |
| `RESTORE VERIFYONLY ... WITH CHECKSUM` | `백업 세트를 사용할 수 있습니다` (정상) |
| `RESTORE FILELISTONLY` | 논리 파일명 healthdb / healthdb_log 확인 |
| 복구 연습 | 별도 이름 **healthdb_restore** 로 `WITH MOVE` 복원 (원본 파일과 다른 경로), **0.215초** |
| 원본 대조 | fact_checkup 1,000,000 = 1,000,000, 쿼리 A 23,884 = 23,884, etl_log 동일, 코드표·인덱스 동일 |
| 정리 | 백업 재검증 후 healthdb_restore 삭제, 원본 healthdb 1,000,000행 유지 확인 |

운영 원칙: 원본 DB 위에 복원(덮어쓰기)하지 않고, 복구 테스트는 항상 별도 이름으로 수행했습니다.

<img src="images/06_backup_history.jpg" alt="백업 이력: 종류 D(전체), 체크섬 포함" width="560">

## Docker로 환경 재현

> **한 줄 요약**
> 백업해 둔 건강검진 데이터베이스를 다른 환경(Docker)에서 다시 열어 보고, **원본과 똑같은지** 확인했습니다.
>
> **쉽게 말하면**
> - **백업과 복원:** 데이터를 통째로 복사해 두는 것이 백업이고, 그 복사본으로 되돌려 놓는 것이 복원입니다.
> - **Docker:** 프로그램을 컴퓨터 환경과 상관없이 똑같이 실행하게 해 주는 상자입니다. 어느 컴퓨터에서든 같은 환경을 만들 수 있습니다.
> - **확인 방법:** 데이터 건수(100만 건), 특정 조건으로 조회한 결과(23,884건), 전체 내용을 하나의 숫자로 요약한 값(체크섬)이 원본과 같은지 비교했습니다. 모두 같았습니다.
> - **의미:** 컴퓨터가 고장 나도 백업으로 같은 데이터를 다시 만들 수 있고, 다른 사람도 같은 환경에서 결과를 다시 확인할 수 있습니다.

백업 파일을 SQL Server 컨테이너의 별도 DB(`healthdb_restore`)로 복원하고, 원본과 같은 결과가 나오는지 확인합니다.
(검증 결과: [docs/docker_restore_verification.md](docs/docker_restore_verification.md))

| 항목 | 내용 |
|---|---|
| 이미지 | `mcr.microsoft.com/mssql/server:2025-latest` (원본이 SQL Server 2025이므로 같은 버전 이상 필요) |
| 에디션 | Express |
| 접속 | `localhost,14330` (SQL Server 인증, `sa`). 기존 PC의 SQL Server(1433)와 포트가 겹치지 않도록 14330 사용 |
| 백업 파일 | `backup/healthdb_full.bak` (약 116.0 MiB, CHECKSUM 포함 전체 백업. 저장소에는 포함하지 않음) |

### 실행 순서
1. `env.example`을 `.env`로 복사하고 `MSSQL_SA_PASSWORD`를 입력합니다. (8자 이상, 대·소문자·숫자·기호 중 3종류 이상. `.env`는 커밋하지 않음)
2. 프로젝트 폴더에 `backup/`을 만들고 `healthdb_full.bak`을 넣습니다.
3. `docker compose up -d`
4. SSMS에서 `localhost,14330`(SQL Server 인증, `sa`)으로 접속해 `docker/restore.sql`을 순서대로 실행합니다.
   (`FILELISTONLY` → `VERIFYONLY` → `RESTORE ... WITH MOVE` → 검증 쿼리)
5. 원본과 복원본의 행 수, 쿼리 A 결과, 체크섬이 같은지 비교합니다.

### 주의
- `.env`, `backup/`, `*.bak`은 `.gitignore`에 포함되어 있어야 합니다.
- 복원은 `healthdb_restore`라는 별도 이름으로 하며 원본 DB는 건드리지 않습니다.
- 컨테이너에서는 Windows 인증을 쓸 수 없어 SQL 계정(`sa`)을 사용했습니다. 개발·검증용 설정입니다.
- 조회 시간 60.3 → 11.3ms 등 성능 수치는 Windows PC의 SQL Server Express에서 측정한 값이며, 컨테이너에서 다시 측정하지 않았습니다.

### 용어 설명
| 용어 | 쉬운 뜻 |
|---|---|
| 데이터베이스(DB) | 많은 데이터를 표 형태로 모아 두고 빠르게 찾는 저장 공간 |
| 백업 / 복원 | 데이터를 통째로 복사해 두는 것 / 복사본으로 되돌려 놓는 것 |
| Docker, 컨테이너 | 프로그램을 어느 컴퓨터에서나 똑같이 실행하게 해 주는 독립된 실행 공간 |
| 인덱스 | 책의 색인처럼 원하는 데이터를 빨리 찾게 해 주는 목록 |
| 체크섬 | 데이터 전체를 하나의 숫자로 요약한 값. 한 글자라도 다르면 값이 달라져서 "같은 데이터인지" 확인하는 데 씀 |
| `healthdb_restore` | 원본을 건드리지 않으려고 새 이름으로 복원한 복사본 |
| `sa` 계정 | SQL Server 관리자 계정. 이번에는 개발·검증용으로만 사용 |

## AI 자연어 질의 프로토타입 (app/, eval/)

> 이 절의 수치는 `eval/results.csv`(2026-10-20 실행 1회)에서 가져온 실제 결과입니다.

**쉬운 요약** — "서울에서 혈압 높은 사람은 몇 명이야?"처럼 한국어로 물으면, AI(LLM)가 SQL을 만들고,
그 SQL을 위에서 구축한 DB에 실행한 뒤, 결과를 쉬운 말로 알려 주는 프로토타입입니다.
SQL을 모르는 사람도 숫자를 확인할 수 있게 하는 것이 목적이고, **진단이나 의료 판단용이 아닌 참고용**입니다.

### 동작 흐름

```
한국어 질문
  → (1) 테이블 구조를 LLM에 전달 → (2) LLM이 SQL 생성
  → (3) SELECT만 통과시키는 검사 → (4) SQL Server 실행 (읽기 전용 계정)
  → (5) LLM이 결과를 2문장 이내로 설명 (+ "진단이 아닌 참고용입니다.")
```

| 파일 | 역할 |
|---|---|
| `app/check_db.py` | DB 연결만 확인 (조회 가능한 테이블, 행 수) |
| `app/check_llm.py` | LLM 연결만 확인 |
| `app/text2sql.py` | 질문 → SQL 생성 → 안전 검사 → 실행 → 설명 |
| `eval/questions.csv` | 평가 질문 10개 + 직접 작성한 정답 SQL |
| `eval/run_eval.py` | 정답 SQL과 LLM 생성 SQL의 **실행 결과**를 비교해 자동 채점 |
| `eval/results.csv` | 채점 결과 (질문별 정답 결과, LLM 생성 SQL, 일치 여부) |

### 안전장치

- **읽기 전용 DB 계정(`ai_reader`)**: `fact_checkup` 테이블 한 개에 `SELECT` 권한만 부여했습니다. 실제 방어선은 이 DB 권한입니다.
- **SELECT 전용 검사**: 생성된 SQL이 `SELECT`로 시작하지 않거나, `INSERT/UPDATE/DELETE/DROP/EXEC/INTO` 등의 키워드 또는 세미콜론이 있으면 실행하지 않습니다. (보조 수단이며, 완벽한 검증은 아닙니다.)
- **예시 데이터 미전송**: 테이블 구조(컬럼 이름·타입)만 LLM에 보내고 실제 행은 보내지 않습니다. 다만 질문과 쿼리 결과(집계 값)는 LLM API로 전송됩니다.
- **비밀값 분리**: DB 비밀번호와 API 키는 `.env`에만 두고 저장소에는 올리지 않습니다(`.gitignore`).

### 실행 순서

사전 조건: [Docker로 환경 재현](#docker로-환경-재현)의 컨테이너가 실행 중이어야 합니다.

1. SSMS에서 `sa`로 접속해 읽기 전용 계정을 만듭니다. (비밀번호는 직접 정하고, 대문자·소문자·숫자 조합 사용)

   ```sql
   USE master;
   CREATE LOGIN ai_reader WITH PASSWORD = '직접_정한_비밀번호';
   USE healthdb_restore;
   CREATE USER ai_reader FOR LOGIN ai_reader;
   GRANT SELECT ON OBJECT::dbo.fact_checkup TO ai_reader;
   ```

2. `env.example`을 참고해 `.env`에 `DB_URI`, `LLM_MODEL`, LLM 서비스의 API 키를 추가합니다.
3. 패키지 설치: `pip install -r requirements.txt` 와 사용하는 LLM 서비스용 패키지(예: `langchain-anthropic`)
4. 단계별 확인 후 실행:

   ```
   python app\check_db.py        # DB 연결
   python app\check_llm.py       # LLM 연결
   python app\text2sql.py 전체 수검자는 몇 명이야?
   python eval\run_eval.py       # 질문 10개 자동 채점
   ```

### 평가 결과

- **방법**: 질문 10개에 대해 정답 SQL을 직접 작성하고, LLM이 만든 SQL과 **실행 결과**가 같으면 일치로 채점했습니다. (SQL 문장 모양은 비교하지 않음 — 예: 정답은 `COUNT(*)`, LLM은 `COUNT(DISTINCT member_id)`를 써도 결과가 같으면 일치)
- **모델**: `anthropic:claude-opus-5-5`
- **결과**: **10/10 일치** (1회 실행)

| # | 질문 | 정답 값 | 일치 |
|---|---|---|---|
| 1 | 서울에서 수축기 140 이상 또는 이완기 90 이상인 사람 수 | 23,884 | O |
| 2 | 전체 수검자 수 | 1,000,000 | O |
| 3 | 서울 수검자의 평균 수축기 혈압 | 122.008226 | O |
| 4 | 공복혈당 126 이상인 사람 수 | 77,805 | O |
| 5 | 수축기 혈압 140 이상인 사람 수 | 112,657 | O |
| 6 | 서울에서 공복혈당 126 이상인 사람 수 | 12,011 | O |
| 7 | 총콜레스테롤 240 이상인 사람 수 | 51,448 | O |
| 8 | 수축기 140 이상이면서 공복혈당 126 이상인 사람 수 | 16,658 | O |
| 9 | BMI 25 이상인 사람 수 | 362,055 | O |
| 10 | 수검자 수가 가장 많은 시도 코드와 인원 | 41, 267,122 | O |

(1번의 정답 값 23,884는 앞의 Docker 복구 검증에서 확인한 값과 같습니다.)

### 한계 (이 결과를 과대 해석하지 마세요)

- **질문 10개, 기본 집계 위주**(건수·평균·단순 조건)입니다. 일반적인 정확도라고 말할 수 없습니다.
- **1회 실행**이라 같은 질문에서 결과가 매번 같은지(일관성)는 측정하지 않았습니다.
- 정답 SQL을 **같은 사람이 작성**했고, **모델 1종만** 사용해 모델 간 비교는 하지 못했습니다.
- 성별·연령 코드값이 필요한 질문, 모호한 표현("건강한 사람"), 이상치 처리, **데이터에 없는 정보를 묻는 질문**, 악의적 요청(삭제 등)에 대한 평가는 아직 하지 않았습니다.
- 질문의 "서울"은 `sido_code = 11`로 해석하도록 프롬프트에 적었으나, 공식 코드표와의 대조는 별도로 확인해야 합니다.
- **설명 문장**은 쿼리 결과를 근거로 하지만 표현이 부정확할 수 있습니다. 초기 실행에서 근거 없는 추측 문장이 한 번 나와 프롬프트(2문장 이내, 추측 금지)를 수정했고, 이후 실행에서는 확인되지 않았지만 보장하지는 않습니다.
- `langchain-community`가 유지보수 종료 예정이라는 경고가 출력됩니다. 향후 SQLAlchemy 직접 사용 등으로 교체할 계획입니다.

### 다음 계획 (미수행)

모델 간 비교(소형 모델), 코드값·모호한 표현·이상치 질문 추가, 안전성 테스트(삭제 요청 차단 여부), 반복 실행을 통한 일관성 측정.
RAG(의료 문서 검색)는 이번 범위에 포함하지 않았습니다.

### 용어 설명

- **LLM**: 사람의 말을 이해하고 문장을 만들어 내는 AI 모델.
- **Text-to-SQL**: 자연어 질문을 데이터베이스 질의문(SQL)으로 바꾸는 것.
- **읽기 전용 계정**: 데이터를 조회만 할 수 있고 수정·삭제는 못 하는 DB 계정. AI가 실수해도 데이터가 바뀌지 않게 하는 안전장치.

## 한계점

- **데이터는 2023년 한 해뿐**입니다. `base_year` 값이 하나라 연도 선두 인덱스(ix_checkup_year_age_sex)의 Seek 효과를 검증할 수 없었고, 연도별 추이 분석도 하지 않았습니다.
- **지역별 비교(Q2, Q3, Q6b)는 연령 보정을 하지 않은 단순 비율·평균**입니다. 시도마다 연령 구성이 다르므로, 지역 간 차이가 연령 구성 차이에서 온 것일 수 있습니다.
- 혈압·혈당 기준은 분석 예시용이며 의학적 진단이 아닙니다. 흡연 상태 코드(1/2/3)의 의미는 스키마 주석 기준이고 공식 코드표로 확인하지 않았습니다.
- 지질 검사 4개 컬럼은 약 66% 가 결측이라 지질 관련 분석은 값이 있는 행만 대상입니다.
- 성능 측정은 **단일 PC, SQL Server Express** 한 대에서 warm 3회 / cold 1회만 수행했습니다. ms 단위의 작은 차이는 측정 오차일 수 있고, 다른 하드웨어나 동시 사용자 환경으로 일반화할 수 없습니다.
- 인덱스 추가에 따른 INSERT / UPDATE 비용은 측정하지 않았습니다.
- 복구 모델이 SIMPLE 이라 로그 백업·특정 시점 복구는 다루지 않았고, 백업 파일을 같은 PC·같은 디스크에 두었습니다. 백업·복원 시간은 각 1회 측정값입니다.

## 향후 개선

- 여러 연도 데이터를 적재해 연도 선두 인덱스의 Seek 효과와 연도별 추이(LAG) 분석을 다시 측정
- 시도별 비교에 연령 표준화(직접 표준화) 적용
- 허리둘레 999.0 등 이상값의 의미를 데이터 설명서로 확인한 뒤 정제 규칙 결정
- 인덱스 추가 전/후 적재(INSERT) 시간 측정으로 쓰기 비용 확인
- FULL 복구 모델 + 로그 백업으로 특정 시점 복구 연습, 백업 파일의 별도 저장소 복사
- Express 에는 SQL Server Agent 가 없으므로 백업·품질 점검을 `sqlcmd` + 작업 스케줄러로 자동화
