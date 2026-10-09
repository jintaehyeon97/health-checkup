/* =====================================================================
   01_schema.sql  -  의료(건강검진) DB 스키마  (SQL Server / T-SQL)
   실행 순서: SSMS에서 이 파일 전체를 실행 (여러 번 실행해도 되도록 작성)
   ※ 컬럼 구성은 '국민건강보험공단 건강검진정보' 형태를 가정했습니다.
      받은 파일의 컬럼과 다르면 fact_checkup 컬럼을 맞게 수정하세요.
   ===================================================================== */

IF DB_ID(N'healthdb') IS NULL
    CREATE DATABASE healthdb;
GO

USE healthdb;
GO

/* 재실행을 위해 기존 객체 제거 (자식 테이블 먼저) */
IF OBJECT_ID(N'dbo.fact_checkup', N'U') IS NOT NULL DROP TABLE dbo.fact_checkup;
IF OBJECT_ID(N'dbo.etl_log',      N'U') IS NOT NULL DROP TABLE dbo.etl_log;
IF OBJECT_ID(N'dbo.dim_sido',     N'U') IS NOT NULL DROP TABLE dbo.dim_sido;
IF OBJECT_ID(N'dbo.dim_sex',      N'U') IS NOT NULL DROP TABLE dbo.dim_sex;
IF OBJECT_ID(N'dbo.dim_age_group',N'U') IS NOT NULL DROP TABLE dbo.dim_age_group;
GO

/* ---------- 코드 테이블 (dimension) ---------- */
CREATE TABLE dbo.dim_sido (
    sido_code  SMALLINT      NOT NULL PRIMARY KEY,
    sido_name  NVARCHAR(20)  NOT NULL
);

CREATE TABLE dbo.dim_sex (
    sex_code   TINYINT       NOT NULL PRIMARY KEY,
    sex_name   NVARCHAR(10)  NOT NULL
);

CREATE TABLE dbo.dim_age_group (
    age_code   TINYINT       NOT NULL PRIMARY KEY,
    age_label  NVARCHAR(20)  NOT NULL
);
GO

/* 시도 코드: 행정구역 코드 기준 예시입니다.
   데이터 설명서(코드표)와 다르면 이 INSERT를 맞게 고치세요.
   (적재 시 매칭 안 되는 코드는 제외되고 개수가 출력됩니다) */
INSERT INTO dbo.dim_sido (sido_code, sido_name) VALUES
 (11, N'서울'), (26, N'부산'), (27, N'대구'), (28, N'인천'), (29, N'광주'),
 (30, N'대전'), (31, N'울산'), (36, N'세종'), (41, N'경기'), (42, N'강원'),
 (43, N'충북'), (44, N'충남'), (45, N'전북'), (46, N'전남'), (47, N'경북'),
 (48, N'경남'), (49, N'제주');

INSERT INTO dbo.dim_sex (sex_code, sex_name) VALUES (1, N'남'), (2, N'여');

/* 연령대 코드(5세 단위) 예시: 1=0~4세, 2=5~9세, ... 18=85세 이상 */
;WITH n AS (
    SELECT 1 AS c
    UNION ALL SELECT c + 1 FROM n WHERE c < 18
)
INSERT INTO dbo.dim_age_group (age_code, age_label)
SELECT c,
       CASE WHEN c = 18 THEN N'85+'
            ELSE CONCAT((c - 1) * 5, N'-', (c - 1) * 5 + 4) END
FROM n;
GO

/* ---------- 사실 테이블 (검진 결과) ---------- */
CREATE TABLE dbo.fact_checkup (
    checkup_id      BIGINT IDENTITY(1,1) NOT NULL,
    base_year       SMALLINT      NOT NULL,           -- 기준년도
    member_id       BIGINT        NOT NULL,           -- 가입자 일련번호(식별 불가 ID)
    sido_code       SMALLINT      NOT NULL,
    sex_code        TINYINT       NOT NULL,
    age_code        TINYINT       NOT NULL,
    height_cm       SMALLINT      NULL,
    weight_kg       SMALLINT      NULL,
    waist_cm        DECIMAL(5,1)  NULL,
    sbp             SMALLINT      NULL,               -- 수축기 혈압
    dbp             SMALLINT      NULL,               -- 이완기 혈압
    fasting_glucose SMALLINT      NULL,               -- 식전(공복) 혈당
    total_chol      SMALLINT      NULL,
    triglyceride    SMALLINT      NULL,
    hdl             SMALLINT      NULL,
    ldl             SMALLINT      NULL,
    hemoglobin      DECIMAL(4,1)  NULL,
    creatinine      DECIMAL(4,1)  NULL,
    ast             SMALLINT      NULL,
    alt             SMALLINT      NULL,
    gamma_gtp       SMALLINT      NULL,
    smoking_status  TINYINT       NULL,               -- 1 비흡연, 2 과거, 3 현재 (코드표 확인)
    drinking_yn     TINYINT       NULL,               -- 0 아니오, 1 예 (코드표 확인)
    CONSTRAINT pk_fact_checkup PRIMARY KEY CLUSTERED (checkup_id),
    CONSTRAINT fk_checkup_sido FOREIGN KEY (sido_code) REFERENCES dbo.dim_sido (sido_code),
    CONSTRAINT fk_checkup_sex  FOREIGN KEY (sex_code)  REFERENCES dbo.dim_sex (sex_code),
    CONSTRAINT fk_checkup_age  FOREIGN KEY (age_code)  REFERENCES dbo.dim_age_group (age_code)
);
GO

/* ---------- 적재 이력 (운영 관점) ---------- */
CREATE TABLE dbo.etl_log (
    log_id        INT IDENTITY(1,1) PRIMARY KEY,
    loaded_at     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    source_file   NVARCHAR(260) NOT NULL,
    rows_read     INT           NOT NULL,
    rows_loaded   INT           NOT NULL,
    rows_dropped  INT           NOT NULL,
    note          NVARCHAR(500) NULL
);
GO

/* 튜닝 실습 전에는 일부러 비클러스터 인덱스를 만들지 않습니다. (04_tuning.sql에서 추가) */
