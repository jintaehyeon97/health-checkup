/* =====================================================================
   04_tuning.sql - 인덱스 튜닝 전/후 비교 (2일차 오후)  *** 프로젝트의 핵심 ***
   사용법
   1) SSMS에서 [쿼리] > [실제 실행 계획 포함] 을 켠다 (Ctrl+M)
   2) 각 STEP을 순서대로 실행하고, [메시지] 탭의 '논리 읽기(logical reads)'와
      'CPU 시간 / 경과 시간'을 표에 기록한다.
   3) 개발용 PC에서만 DBCC 명령을 쓴다. (운영 서버에서는 사용 금지)
   ===================================================================== */
USE healthdb;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* ---------- STEP 0. 현재 인덱스 확인 (PK 외에는 없어야 함) ---------- */
SELECT name, type_desc FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.fact_checkup');
GO

/* ---------- STEP 1. [BEFORE] 인덱스 없이 측정 (여러 번 실행해 평균을 기록) ---------- */
DBCC DROPCLEANBUFFERS;     -- 캐시 비우기 (개발용 PC 전용)
GO
/* 측정 쿼리 A: 특정 시도의 혈압 높음 건수 */
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);
GO

/* 측정 쿼리 B: 연령대+성별별 평균 혈당 */
SELECT age_code, sex_code, AVG(CAST(fasting_glucose AS FLOAT)) AS avg_glucose
FROM dbo.fact_checkup
WHERE base_year = (SELECT MAX(base_year) FROM dbo.fact_checkup)
GROUP BY age_code, sex_code;
GO

/* 측정 쿼리 C (일부러 느리게 쓴 형태): 컬럼에 함수를 씌운 조건 -> 인덱스를 못 탐(non-sargable) */
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE CAST(base_year AS VARCHAR(4)) = '2023';
GO

/* ---------- STEP 2. 인덱스 추가 ---------- */
/* A용: 시도로 찾고, 혈압 컬럼은 인덱스 안에서 바로 읽도록 INCLUDE (커버링 인덱스) */
CREATE NONCLUSTERED INDEX ix_checkup_sido_bp
    ON dbo.fact_checkup (sido_code)
    INCLUDE (sbp, dbp);
GO
/* B/C용: 기준년도 + 연령/성별
   ※ 주의: 현재 적재 데이터는 base_year 가 전부 2023 (값 1종류).
      선두 컬럼의 선택도가 없으므로 B(MAX 연도)·C(base_year = 2023) 모두 사실상 전체 행을 읽게 되어
      Seek 으로 범위를 좁히는 효과는 기대하기 어렵다. 효과가 있다면 테이블보다 폭이 좁은
      인덱스를 읽는(커버링) 데서 나오는 것이고, 실제 효과는 5단계 측정값으로만 판단한다. */
CREATE NONCLUSTERED INDEX ix_checkup_year_age_sex
    ON dbo.fact_checkup (base_year, age_code, sex_code)
    INCLUDE (fasting_glucose);
GO

/* ---------- STEP 3. [AFTER] 같은 쿼리를 다시 측정 ---------- */
DBCC DROPCLEANBUFFERS;
GO
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);
GO
SELECT age_code, sex_code, AVG(CAST(fasting_glucose AS FLOAT)) AS avg_glucose
FROM dbo.fact_checkup
WHERE base_year = (SELECT MAX(base_year) FROM dbo.fact_checkup)
GROUP BY age_code, sex_code;
GO

/* C는 쓰는 방법을 바꿔야 인덱스를 탐: 컬럼 가공 없이 값을 비교 (sargable) */
SELECT COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE base_year = 2023;
GO

/* ---------- STEP 4. 인덱스 효과를 다시 확인하고 싶을 때 ---------- */
-- DROP INDEX ix_checkup_sido_bp ON dbo.fact_checkup;
-- DROP INDEX ix_checkup_year_age_sex ON dbo.fact_checkup;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =====================================================================
   기록용 표 (README에 옮기기)
   | 쿼리 | BEFORE 논리 읽기 | BEFORE 경과(ms) | AFTER 논리 읽기 | AFTER 경과(ms) | 비고 |
   | A    |                  |                 |                 |                | 커버링 인덱스 |
   | B    |                  |                 |                 |                | 복합 인덱스   |
   | C    |                  |                 |                 |                | 함수 제거(sargable) |
   ===================================================================== */
