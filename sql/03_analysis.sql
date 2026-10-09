/* =====================================================================
   03_analysis.sql - 분석 쿼리 (2일차 오전)
   ※ 혈압/혈당 기준은 '의학적 진단'이 아니라 분석 예시를 위한 단순 기준입니다.
   ===================================================================== */
USE healthdb;
GO

/* Q1. 연령대 x 성별 평균 지표 (JOIN + GROUP BY) */
SELECT a.age_label,
       s.sex_name,
       COUNT(*)                         AS n,
       AVG(CAST(f.sbp AS FLOAT))        AS avg_sbp,
       AVG(CAST(f.fasting_glucose AS FLOAT)) AS avg_glucose,
       AVG(CAST(f.weight_kg AS FLOAT) / NULLIF(POWER(f.height_cm / 100.0, 2), 0)) AS avg_bmi
FROM dbo.fact_checkup f
JOIN dbo.dim_age_group a ON a.age_code = f.age_code
JOIN dbo.dim_sex       s ON s.sex_code = f.sex_code
GROUP BY a.age_code, a.age_label, s.sex_name
ORDER BY a.age_code, s.sex_name;
GO

/* Q2. 시도별 '혈압 높음(수축기>=140 또는 이완기>=90)' 비율 (조건부 집계) */
SELECT d.sido_name,
       COUNT(*) AS n,
       SUM(CASE WHEN f.sbp >= 140 OR f.dbp >= 90 THEN 1 ELSE 0 END) AS high_bp_cnt,
       CAST(100.0 * SUM(CASE WHEN f.sbp >= 140 OR f.dbp >= 90 THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,2)) AS high_bp_pct
FROM dbo.fact_checkup f
JOIN dbo.dim_sido d ON d.sido_code = f.sido_code
WHERE f.sbp IS NOT NULL AND f.dbp IS NOT NULL
GROUP BY d.sido_name
ORDER BY high_bp_pct DESC;
GO

/* Q3. 연령대별로 평균 공복혈당이 높은 시도 순위 (윈도우 함수 RANK) */
WITH g AS (
    SELECT f.age_code, f.sido_code, AVG(CAST(f.fasting_glucose AS FLOAT)) AS avg_glucose, COUNT(*) AS n
    FROM dbo.fact_checkup f
    WHERE f.fasting_glucose IS NOT NULL
    GROUP BY f.age_code, f.sido_code
)
SELECT a.age_label, d.sido_name, g.n, g.avg_glucose,
       RANK() OVER (PARTITION BY g.age_code ORDER BY g.avg_glucose DESC) AS rnk
FROM g
JOIN dbo.dim_age_group a ON a.age_code = g.age_code
JOIN dbo.dim_sido d ON d.sido_code = g.sido_code
ORDER BY a.age_code, rnk;
GO

/* Q4. 전체 평균보다 LDL이 높은 사람의 성별 건수와 비율 (서브쿼리)
   ※ 비율의 분모는 LDL 값이 있는 행만 (LDL은 약 67%가 NULL) */
SELECT s.sex_name,
       COUNT(*) AS ldl_measured_cnt,
       SUM(CASE WHEN f.ldl > a.avg_ldl THEN 1 ELSE 0 END) AS above_avg_ldl_cnt,
       CAST(100.0 * SUM(CASE WHEN f.ldl > a.avg_ldl THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS above_avg_ldl_pct
FROM dbo.fact_checkup f
JOIN dbo.dim_sex s ON s.sex_code = f.sex_code
CROSS JOIN (SELECT AVG(CAST(ldl AS FLOAT)) AS avg_ldl FROM dbo.fact_checkup WHERE ldl IS NOT NULL) a
WHERE f.ldl IS NOT NULL
GROUP BY s.sex_name;
GO

/* Q5. 흡연 상태별 HDL / 중성지방 평균 비교 */
SELECT f.smoking_status,
       COUNT(*) AS n,
       AVG(CAST(f.hdl AS FLOAT))          AS avg_hdl,
       AVG(CAST(f.triglyceride AS FLOAT)) AS avg_tg
FROM dbo.fact_checkup f
WHERE f.smoking_status IS NOT NULL
GROUP BY f.smoking_status
ORDER BY f.smoking_status;
GO

/* Q6a. 연령대별 평균 수축기혈압 + 이전 연령대 대비 증감 (LAG)
   ※ 원래는 연도별 추이였으나 적재 데이터가 2023년 한 해뿐이라 연령대 축으로 변경 */
WITH g AS (
    SELECT f.age_code, AVG(CAST(f.sbp AS FLOAT)) AS avg_sbp, COUNT(*) AS n
    FROM dbo.fact_checkup f
    WHERE f.sbp IS NOT NULL
    GROUP BY f.age_code
)
SELECT a.age_label, g.n, g.avg_sbp,
       g.avg_sbp - LAG(g.avg_sbp) OVER (ORDER BY g.age_code) AS diff_from_prev_age
FROM g
JOIN dbo.dim_age_group a ON a.age_code = g.age_code
ORDER BY g.age_code;
GO

/* Q6b. 시도별 평균 수축기혈압 vs 전국 평균 (윈도우 집계 AVG() OVER ())
   ※ 전국 평균 = 시도 평균들의 평균이 아니라 전체 행 기준 가중평균 */
WITH g AS (
    SELECT f.sido_code, SUM(CAST(f.sbp AS FLOAT)) AS sum_sbp, COUNT(*) AS n
    FROM dbo.fact_checkup f
    WHERE f.sbp IS NOT NULL
    GROUP BY f.sido_code
)
SELECT d.sido_name, g.n,
       g.sum_sbp / g.n                                         AS avg_sbp,
       SUM(g.sum_sbp) OVER () / SUM(g.n) OVER ()               AS national_avg_sbp,
       g.sum_sbp / g.n - SUM(g.sum_sbp) OVER () / SUM(g.n) OVER () AS diff_from_national
FROM g
JOIN dbo.dim_sido d ON d.sido_code = g.sido_code
ORDER BY diff_from_national DESC;
GO
