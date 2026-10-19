/* healthdb_restore 로 복원 테스트 (원본 healthdb 는 건드리지 않음)
   접속: 서버 localhost,14330 / SQL Server 인증 sa / 비밀번호는 접속 창에서 직접 입력
   각 단계를 하나씩 실행하세요. */

/* 1) 백업 파일 안의 파일 목록 확인 (LogicalName: healthdb, healthdb_log) */
RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/healthdb_full.bak';
GO

/* 2) 백업 파일 손상 검사 */
RESTORE VERIFYONLY FROM DISK = N'/var/opt/mssql/backup/healthdb_full.bak' WITH CHECKSUM;
GO

/* 3) 별도 이름으로 복원 */
RESTORE DATABASE healthdb_restore
FROM DISK = N'/var/opt/mssql/backup/healthdb_full.bak'
WITH CHECKSUM,
     MOVE N'healthdb'     TO N'/var/opt/mssql/data/healthdb_restore.mdf',
     MOVE N'healthdb_log' TO N'/var/opt/mssql/data/healthdb_restore_log.ldf',
     STATS = 10;
GO

/* 4) 검증: 같은 쿼리를 원본(healthdb)에서도 실행해 값을 비교 */
USE healthdb_restore;
SELECT COUNT(*) AS fact_checkup_rows FROM dbo.fact_checkup;           -- 기대값 1,000,000
SELECT COUNT(*) AS cnt FROM dbo.fact_checkup
WHERE sido_code = 11 AND (sbp >= 140 OR dbp >= 90);                   -- 쿼리 A, 기대값 23,884
SELECT COUNT(*) AS cnt, CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS chk
FROM dbo.fact_checkup;                                                -- 원본과 같아야 함
SELECT name, type_desc FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.fact_checkup') AND name IS NOT NULL; -- PK + 인덱스 2개
GO
