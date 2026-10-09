/* =====================================================================
   06_backup.sql - 백업과 복구 연습 (3일차 오전)
   ※ 백업 경로는 인스턴스 기본 백업 폴더를 SERVERPROPERTY('InstanceDefaultBackupPath') 로 구해서 씁니다.
      (SQL Server 서비스 계정이 이미 쓰기 권한을 가진 폴더라 폴더 생성/권한 설정이 필요 없음)
      다른 폴더를 쓰려면 각 배치의 @dir 값을 그 경로로 바꾸고, 서비스 계정에 쓰기 권한을 주세요.
   ※ 변수는 GO 로 나뉜 배치마다 새로 선언해야 하므로 각 배치에서 경로를 다시 구합니다.
   ===================================================================== */
USE master;
GO

/* 1. 전체 백업 */
DECLARE @dir NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
DECLARE @bak NVARCHAR(400) = @dir + CASE WHEN RIGHT(@dir, 1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_full.bak';
PRINT N'백업 파일: ' + @bak;
BACKUP DATABASE healthdb
TO DISK = @bak
WITH INIT, CHECKSUM, NAME = N'healthdb full backup';
GO

/* 2. 백업 파일이 읽을 수 있는 상태인지 검증 */
DECLARE @dir NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
DECLARE @bak NVARCHAR(400) = @dir + CASE WHEN RIGHT(@dir, 1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_full.bak';
RESTORE VERIFYONLY
FROM DISK = @bak
WITH CHECKSUM;
GO

/* 3. 백업 안의 파일 목록 (논리 파일명 확인용, 읽기 전용) */
DECLARE @dir NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
DECLARE @bak NVARCHAR(400) = @dir + CASE WHEN RIGHT(@dir, 1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_full.bak';
RESTORE FILELISTONLY FROM DISK = @bak;
GO

/* 4. 복구 연습: 다른 이름(healthdb_restore)의 DB로 복원해 원본과 건수 비교 (원본 healthdb 는 건드리지 않음)
      - 논리 파일명(healthdb, healthdb_log)은 3번 FILELISTONLY 결과로 확인 후 맞게 고치세요.
      - WITH MOVE 로 물리 파일을 원본(healthdb.mdf / healthdb_log.ldf)과 다른 이름으로 지정합니다.
      - 필요할 때만 주석을 풀어 실행하세요. */
-- DECLARE @dir  NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
-- DECLARE @bak  NVARCHAR(400) = @dir + CASE WHEN RIGHT(@dir, 1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_full.bak';
-- DECLARE @data NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
-- DECLARE @log  NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS NVARCHAR(260));
-- DECLARE @mdf  NVARCHAR(400) = @data + CASE WHEN RIGHT(@data, 1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_restore.mdf';
-- DECLARE @ldf  NVARCHAR(400) = @log  + CASE WHEN RIGHT(@log,  1) = N'\' THEN N'' ELSE N'\' END + N'healthdb_restore_log.ldf';
-- IF DB_ID(N'healthdb_restore') IS NOT NULL THROW 50000, N'healthdb_restore 가 이미 있습니다. 먼저 확인하세요.', 1;
-- RESTORE DATABASE healthdb_restore
-- FROM DISK = @bak
-- WITH MOVE N'healthdb'     TO @mdf,
--      MOVE N'healthdb_log' TO @ldf,
--      RECOVERY;
-- GO
-- SELECT COUNT_BIG(*) FROM healthdb_restore.dbo.fact_checkup;   -- 원본과 같은지 확인 (1,000,000)
-- DROP DATABASE healthdb_restore;                                -- 연습 후 정리 (실행 전 확인)
