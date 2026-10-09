/* =====================================================================
   05_quality_checks.sql - 데이터 품질 점검 쿼리 (3일차 오전)
   결과 건수가 0이 아니면 원인을 조사하고 README에 기록한다.
   ※ 허용 범위는 예시입니다. 데이터 설명서를 보고 직접 정하세요.
   ===================================================================== */
USE healthdb;
GO

/* 1. 중복: 같은 연도 + 같은 가입자 번호가 2건 이상 */
SELECT base_year, member_id, COUNT(*) AS dup_cnt
FROM dbo.fact_checkup
GROUP BY base_year, member_id
HAVING COUNT(*) > 1;
GO

/* 2. 범위 이탈 (예시 기준) */
SELECT 'sbp'  AS col, COUNT(*) AS bad_cnt FROM dbo.fact_checkup WHERE sbp  IS NOT NULL AND sbp  NOT BETWEEN 50 AND 300
UNION ALL
SELECT 'dbp',  COUNT(*) FROM dbo.fact_checkup WHERE dbp  IS NOT NULL AND dbp  NOT BETWEEN 30 AND 200
UNION ALL
SELECT 'fasting_glucose', COUNT(*) FROM dbo.fact_checkup WHERE fasting_glucose IS NOT NULL AND fasting_glucose NOT BETWEEN 20 AND 800
UNION ALL
SELECT 'height_cm', COUNT(*) FROM dbo.fact_checkup WHERE height_cm IS NOT NULL AND height_cm NOT BETWEEN 100 AND 220;
GO

/* 3. 컬럼별 결측 비율 */
SELECT COUNT(*) AS total,
       CAST(100.0 * SUM(CASE WHEN sbp             IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS sbp_null_pct,
       CAST(100.0 * SUM(CASE WHEN fasting_glucose IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS glucose_null_pct,
       CAST(100.0 * SUM(CASE WHEN ldl             IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS ldl_null_pct,
       CAST(100.0 * SUM(CASE WHEN smoking_status  IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS smoking_null_pct
FROM dbo.fact_checkup;
GO

/* 보충 2-1. 허리둘레 범위 이탈 (기준 40~200cm 은 보충 점검용 임의 기준, 999.0 은 별도 집계) */
SELECT N'waist_cm = 999.0' AS cond, COUNT(*) AS cnt FROM dbo.fact_checkup WHERE waist_cm = 999.0
UNION ALL
SELECT 'waist_cm < 40', COUNT(*) FROM dbo.fact_checkup WHERE waist_cm < 40
UNION ALL
SELECT 'waist_cm >= 200 AND <> 999', COUNT(*) FROM dbo.fact_checkup WHERE waist_cm >= 200 AND waist_cm <> 999.0
UNION ALL
SELECT N'waist_cm NOT BETWEEN 40 AND 200 (합계)', COUNT(*) FROM dbo.fact_checkup WHERE waist_cm IS NOT NULL AND waist_cm NOT BETWEEN 40 AND 200;
GO

/* 보충 2-2. 허리둘레 범위 밖 값 목록 */
SELECT waist_cm, COUNT(*) AS cnt
FROM dbo.fact_checkup
WHERE waist_cm IS NOT NULL AND waist_cm NOT BETWEEN 40 AND 200
GROUP BY waist_cm
ORDER BY waist_cm;
GO

/* 보충 3. 적재한 22개 컬럼 전체 결측 건수 / 결측률 */
SELECT v.col,
       v.null_cnt,
       CAST(100.0 * v.null_cnt / t.total AS DECIMAL(5,2)) AS null_pct
FROM (SELECT COUNT(*) AS total,
             SUM(CASE WHEN base_year       IS NULL THEN 1 ELSE 0 END) AS base_year,
             SUM(CASE WHEN member_id       IS NULL THEN 1 ELSE 0 END) AS member_id,
             SUM(CASE WHEN sido_code       IS NULL THEN 1 ELSE 0 END) AS sido_code,
             SUM(CASE WHEN sex_code        IS NULL THEN 1 ELSE 0 END) AS sex_code,
             SUM(CASE WHEN age_code        IS NULL THEN 1 ELSE 0 END) AS age_code,
             SUM(CASE WHEN height_cm       IS NULL THEN 1 ELSE 0 END) AS height_cm,
             SUM(CASE WHEN weight_kg       IS NULL THEN 1 ELSE 0 END) AS weight_kg,
             SUM(CASE WHEN waist_cm        IS NULL THEN 1 ELSE 0 END) AS waist_cm,
             SUM(CASE WHEN sbp             IS NULL THEN 1 ELSE 0 END) AS sbp,
             SUM(CASE WHEN dbp             IS NULL THEN 1 ELSE 0 END) AS dbp,
             SUM(CASE WHEN fasting_glucose IS NULL THEN 1 ELSE 0 END) AS fasting_glucose,
             SUM(CASE WHEN total_chol      IS NULL THEN 1 ELSE 0 END) AS total_chol,
             SUM(CASE WHEN triglyceride    IS NULL THEN 1 ELSE 0 END) AS triglyceride,
             SUM(CASE WHEN hdl             IS NULL THEN 1 ELSE 0 END) AS hdl,
             SUM(CASE WHEN ldl             IS NULL THEN 1 ELSE 0 END) AS ldl,
             SUM(CASE WHEN hemoglobin      IS NULL THEN 1 ELSE 0 END) AS hemoglobin,
             SUM(CASE WHEN creatinine      IS NULL THEN 1 ELSE 0 END) AS creatinine,
             SUM(CASE WHEN ast             IS NULL THEN 1 ELSE 0 END) AS ast,
             SUM(CASE WHEN alt             IS NULL THEN 1 ELSE 0 END) AS alt,
             SUM(CASE WHEN gamma_gtp       IS NULL THEN 1 ELSE 0 END) AS gamma_gtp,
             SUM(CASE WHEN smoking_status  IS NULL THEN 1 ELSE 0 END) AS smoking_status,
             SUM(CASE WHEN drinking_yn     IS NULL THEN 1 ELSE 0 END) AS drinking_yn
      FROM dbo.fact_checkup) AS t
CROSS APPLY (VALUES
    ('base_year', t.base_year), ('member_id', t.member_id), ('sido_code', t.sido_code),
    ('sex_code', t.sex_code), ('age_code', t.age_code), ('height_cm', t.height_cm),
    ('weight_kg', t.weight_kg), ('waist_cm', t.waist_cm), ('sbp', t.sbp), ('dbp', t.dbp),
    ('fasting_glucose', t.fasting_glucose), ('total_chol', t.total_chol),
    ('triglyceride', t.triglyceride), ('hdl', t.hdl), ('ldl', t.ldl),
    ('hemoglobin', t.hemoglobin), ('creatinine', t.creatinine), ('ast', t.ast), ('alt', t.alt),
    ('gamma_gtp', t.gamma_gtp), ('smoking_status', t.smoking_status), ('drinking_yn', t.drinking_yn)
) AS v(col, null_cnt);
GO

/* 4. 적재 이력 점검: 읽은 건수 = 적재 건수 + 제외 건수 */
SELECT log_id, loaded_at, source_file, rows_read, rows_loaded, rows_dropped,
       CASE WHEN rows_read = rows_loaded + rows_dropped THEN 'OK' ELSE 'MISMATCH' END AS check_result,
       note
FROM dbo.etl_log
ORDER BY log_id;
GO
