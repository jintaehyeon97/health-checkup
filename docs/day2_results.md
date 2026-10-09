# Day 2 - 인덱스 튜닝 측정 결과

- 대상: `healthdb.dbo.fact_checkup` 1,000,000행 (2023년 한 해, `base_year` 값은 2023 하나뿐)
- 환경: SQL Server 2025 Express (RTM 17.0.1000.7, 64-bit), 단일 PC (Windows 11), ODBC Driver 18 / pyodbc 5.3.0
- 측정일: 2026-10-09
- 측정 방법: `SET STATISTICS IO ON; SET STATISTICS TIME ON;` 메시지를 pyodbc 로 수집
  - **warm**: 캐시를 비우지 않고 쿼리당 3회 연속 실행
  - **cold**: 쿼리 직전에 `CHECKPOINT; DBCC DROPCLEANBUFFERS;` (개발 PC 전용) 후 1회 실행
  - CPU / elapsed = `SQL Server 실행 시간` (컴파일 시간 제외), 단위 ms
  - 사용 인덱스 = 측정과 별도로 1회 실행한 실제 실행 계획(`SET STATISTICS XML ON`)에서 확인
  - logical / physical / read-ahead reads 는 `fact_checkup` 테이블 기준
- 측정 스크립트: `tools/measure_tuning.py`
- 모든 수치는 실제 측정값입니다. 평균은 측정한 3회 값의 산술평균, 증감률은 `(AFTER - BEFORE) / BEFORE`.

## 측정 쿼리

```sql
-- A: 특정 시도의 혈압 높음 건수
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);

-- B: 연령대+성별별 평균 혈당
SELECT age_code, sex_code, AVG(CAST(fasting_glucose AS FLOAT)) AS avg_glucose
FROM dbo.fact_checkup
WHERE base_year = (SELECT MAX(base_year) FROM dbo.fact_checkup)
GROUP BY age_code, sex_code;

-- C1 (CAST 형태, non-sargable)
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE CAST(base_year AS VARCHAR(4)) = '2023';

-- C2 (sargable 형태)
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE base_year = 2023;
```

C1 과 C2 는 인덱스 효과와 쿼리 재작성 효과를 분리하기 위해 BEFORE / AFTER 모두에서 측정했습니다.

## 인덱스 정의와 생성 기록

```sql
/* A용: 시도로 찾고, 혈압 컬럼은 인덱스 안에서 바로 읽도록 INCLUDE (커버링 인덱스) */
CREATE NONCLUSTERED INDEX ix_checkup_sido_bp
    ON dbo.fact_checkup (sido_code)
    INCLUDE (sbp, dbp);

/* B/C용: 기준년도 + 연령/성별 */
CREATE NONCLUSTERED INDEX ix_checkup_year_age_sex
    ON dbo.fact_checkup (base_year, age_code, sex_code)
    INCLUDE (fasting_glucose);
```

한 개씩 실행했고, 페이지 수는 `sys.indexes` 와 `sys.dm_db_partition_stats` 를 조인해 생성 직후 조회했습니다.

| 인덱스 | 종류 | 생성 CPU ms | 생성 elapsed ms | row_count | in_row_data_page_count | used_page_count | reserved_page_count |
|---|---|---:|---:|---:|---:|---:|---:|
| pk_fact_checkup (기존) | CLUSTERED | - | - | 1,000,000 | 9,175 | 9,219 | 9,225 |
| ix_checkup_sido_bp | NONCLUSTERED | 1,187 | 1,226 | 1,000,000 | 2,476 | 2,484 | 2,489 |
| ix_checkup_year_age_sex | NONCLUSTERED | 1,812 | 1,813 | 1,000,000 | 2,476 | 2,485 | 2,489 |

## 전/후 비교 요약 (warm 평균 기준)

| 쿼리 | logical reads BEFORE → AFTER | 감소율 | elapsed ms BEFORE → AFTER | 증감률 | 실행 계획 BEFORE → AFTER |
|---|---|---:|---|---:|---|
| A | 9,219 → 438 | -95.2% | 60.3 → 11.3 | -81.2% | Clustered Index Scan (pk_fact_checkup) → **Index Seek (ix_checkup_sido_bp)** |
| B | 18,438 → 2,488 | -86.5% | 318.0 → 155.0 | -51.3% | Clustered Index Scan × 2 → **Index Scan × 2 (ix_checkup_year_age_sex)**, Seek 아님 |
| C1 (CAST) | 9,219 → 2,485 | -73.0% | 172.7 → 174.3 | **+1.0%** (감소 없음) | Clustered Index Scan → Index Scan (ix_checkup_year_age_sex), Seek 아님 |
| C2 (sargable) | 9,219 → 2,485 | -73.0% | 87.0 → 49.7 | -42.9% | Clustered Index Scan → **Index Seek (ix_checkup_year_age_sex)**, 단 1,000,000행 전부 반환 |

### C 2x2 (형태 × 인덱스)

| C 형태 | BEFORE (PK만) | AFTER (인덱스 2개) |
|---|---|---|
| C1 `CAST(base_year AS VARCHAR(4)) = '2023'` | logical 9,219 / warm elapsed 172.7 ms / cold 191 ms / Clustered Index Scan | logical 2,485 / warm elapsed 174.3 ms / cold 182 ms / Index Scan (ix_checkup_year_age_sex) |
| C2 `base_year = 2023` | logical 9,219 / warm elapsed 87.0 ms / cold 123 ms / Clustered Index Scan | logical 2,485 / warm elapsed 49.7 ms / cold 57 ms / Index Seek (ix_checkup_year_age_sex) |

- 인덱스가 없을 때도 C1 → C2 재작성만으로 warm elapsed 가 172.7 → 87.0 ms 로 줄었습니다 (logical reads 는 둘 다 9,219 로 동일).
- 인덱스를 만든 뒤 C1 은 더 좁은 인덱스를 읽어 logical reads 가 73.0% 줄었지만 elapsed 는 줄지 않았습니다 (warm +1.0%, cold -4.7%, CPU 172.0 → 171.7 ms).
- C2 는 실행 계획상 Seek 이지만 모든 행의 `base_year` 가 2023 이라 Seek 범위가 인덱스 전체(1,000,000행)였고, logical reads 는 C1 AFTER 와 같은 2,485 입니다.

## 상세 측정값

### warm (캐시 유지, 3회)

| 쿼리 | 단계 | Scan count | logical | physical | CPU ms (1/2/3, 평균) | elapsed ms (1/2/3, 평균) | 실행 계획 (fact_checkup 접근, 실제 행 수) |
|---|---|---:|---:|---:|---|---|---|
| A | BEFORE | 1 | 9,219 | 0 | 47 / 63 / 62, 57.3 | 61 / 60 / 60, 60.3 | Clustered Index Scan (pk_fact_checkup), 23,884 |
| A | AFTER | 1 | 438 | 0 | 16 / 15 / 16, 15.7 | 12 / 11 / 11, 11.3 | Index Seek (ix_checkup_sido_bp), 23,884 |
| B | BEFORE | 2 | 18,438 | 0 | 312 / 313 / 312, 312.3 | 316 / 320 / 318, 318.0 | Clustered Index Scan (pk_fact_checkup) 1,000,000 + 1,000,000 |
| B | AFTER | 2 | 2,488 | 0 | 156 / 157 / 156, 156.3 | 155 / 156 / 154, 155.0 | Index Scan (ix_checkup_year_age_sex) 1 (MAX) + 1,000,000 |
| C1 | BEFORE | 1 | 9,219 | 0 | 172 / 172 / 172, 172.0 | 173 / 167 / 178, 172.7 | Clustered Index Scan (pk_fact_checkup), 1,000,000 |
| C1 | AFTER | 1 | 2,485 | 0 | 156 / 188 / 171, 171.7 | 173 / 175 / 175, 174.3 | Index Scan (ix_checkup_year_age_sex), 1,000,000 |
| C2 | BEFORE | 1 | 9,219 | 0 | 78 / 78 / 109, 88.3 | 79 / 82 / 100, 87.0 | Clustered Index Scan (pk_fact_checkup), 1,000,000 |
| C2 | AFTER | 1 | 2,485 | 0 | 47 / 47 / 47, 47.0 | 49 / 50 / 50, 49.7 | Index Seek (ix_checkup_year_age_sex), 1,000,000 |

- 3회 실행 사이에 logical reads / Scan count 는 변하지 않았습니다.
- B 는 Worktable / Workfile 항목도 출력됐으나 BEFORE / AFTER 모두 읽기 0 이었습니다.
- 쿼리 결과 확인: A = 23,884, C1·C2 = 1,000,000 으로 전/후 동일. B 는 전/후 모두 28행이고 첫 행(age 5, sex 1, 91.9168)이 같았습니다 (28행 전체 대조는 하지 않음).

### cold (CHECKPOINT + DBCC DROPCLEANBUFFERS 후 1회)

| 쿼리 | 단계 | Scan count | logical | physical | read-ahead | CPU ms | elapsed ms |
|---|---|---:|---:|---:|---:|---:|---:|
| A | BEFORE | 1 | 9,219 | 3 | 9,215 | 94 | 84 |
| A | AFTER | 1 | 438 | 3 | 435 | 15 | 13 |
| B | BEFORE | 2 | 18,438 | 3 | 9,215 | 328 | 363 |
| B | AFTER | 2 | 2,488 | 5 | 2,479 | 157 | 162 |
| C1 | BEFORE | 1 | 9,219 | 3 | 9,215 | 172 | 191 |
| C1 | AFTER | 1 | 2,485 | 3 | 2,481 | 171 | 182 |
| C2 | BEFORE | 1 | 9,219 | 3 | 9,215 | 110 | 123 |
| C2 | AFTER | 1 | 2,485 | 3 | 2,481 | 63 | 57 |

cold elapsed 증감률: A -84.5%, B -55.4%, C1 -4.7%, C2 -53.7%.

- cold 에서 디스크 읽기는 대부분 `physical reads` 가 아니라 `read-ahead reads` 로 집계됐습니다.
- B BEFORE 는 테이블을 2번 스캔하지만(logical 18,438) read-ahead 합계는 9,215 로 A/C 와 같았습니다. 두 번째 스캔은 첫 스캔이 메모리에 올린 페이지를 읽은 것으로 보입니다 (스캔별 IO 는 따로 측정하지 않음).

## 해석 (측정값 기준)

- **ix_checkup_sido_bp**: 쿼리 A 에서 Clustered Index Scan 이 Index Seek 으로 바뀌었고 logical reads -95.2%, warm elapsed -81.2%. 실제로 사용됐고 효과가 가장 컸습니다.
- **ix_checkup_year_age_sex**: B, C1, C2 모두에서 사용됐습니다.
  - B: Seek 이 아니라 Index Scan 입니다. 테이블보다 좁은 인덱스(2,485 vs 9,219 페이지)를 읽고, MAX 서브쿼리는 인덱스에서 1행만 읽게 되어 logical reads -86.5%, elapsed -51.3%.
  - C1: 인덱스는 쓰였지만 **실행 시간 측면에서는 효과 없음** (근거는 위 C 2x2 표).
  - C2: Seek 이지만 인덱스 전체를 읽어, 선두 컬럼으로 범위를 좁히는 Seek 본래의 효과는 이 데이터에서 확인되지 않았습니다 (근거는 위 C 2x2 표).
- 두 인덱스는 각각 reserved 2,489 페이지를 추가로 사용합니다. INSERT / UPDATE 시 인덱스 유지 비용은 측정하지 않았습니다.

## 한계점

- **데이터가 2023년 한 해뿐**입니다. `base_year` 가 모든 행에서 같아 `ix_checkup_year_age_sex` 의 선두 컬럼은 선택도가 없습니다. 여러 연도를 적재하면 B / C2 결과는 달라질 수 있습니다 (측정하지 않음).
- **단일 PC, SQL Server Express** 한 대에서 측정했습니다. 다른 하드웨어·에디션·동시 사용자 환경으로 일반화할 수 없습니다.
- warm 은 쿼리당 3회, cold 는 1회만 측정했습니다. ms 단위의 작은 차이(예: C1 의 +1.0%)는 측정 오차 범위일 수 있습니다.
- 실행 계획은 시간 측정과 별도 실행에서 수집했습니다 (계획 수집 오버헤드가 시간에 섞이지 않도록).
- `DBCC DROPCLEANBUFFERS` 는 개발 PC 에서만 사용했습니다. 운영 서버에서는 사용하지 않습니다.
- 인덱스 추가에 따른 쓰기(INSERT/UPDATE) 성능 변화와 저장 공간 외 비용은 측정하지 않았습니다.
