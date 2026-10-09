# Day 3 - 백업 / 검증 결과

- 대상: `healthdb` (복구 모델 SIMPLE, 데이터 파일 136 MB / 로그 파일 136 MB 할당)
- 실행 스크립트: `sql/06_backup.sql` 1~3번 배치. 4번 복구 연습은 파일에서는 주석 상태이며, 같은 SQL 을 승인 후 따로 실행했습니다 (아래 4번).
- 실행일: 2026-10-09, SQL Server 2025 Express, 단일 PC
- 모든 수치는 실제 실행 결과입니다.

## 1. 전체 백업 (BACKUP DATABASE ... WITH INIT, CHECKSUM)

| 항목 | 값 | 출처 |
|---|---|---|
| 백업 파일 | `C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\healthdb_full.bak` | `SERVERPROPERTY('InstanceDefaultBackupPath')` + PRINT 출력 |
| 처리 페이지 | 데이터 파일 14,832 + 로그 파일 2 = 14,834 페이지 | BACKUP 완료 메시지 |
| 소요 시간 (서버) | **0.227초** (510.514 MB/초) | BACKUP 완료 메시지 |
| 소요 시간 (클라이언트) | 302 ms | Python 에서 실행~완료까지 측정 |
| backup_start_date | 2026-10-09 12:42:50 | `msdb.dbo.backupset` |
| backup_finish_date | 2026-10-09 12:42:50 | `msdb.dbo.backupset` |
| backup_size | **121,595,904 bytes** (약 116.0 MiB) | `msdb.dbo.backupset` |
| compressed_backup_size | 121,595,904 bytes (압축 미사용, backup_size 와 동일) | `msdb.dbo.backupset` |
| has_backup_checksums | True | `msdb.dbo.backupset` |
| backup_set_id / type | 1 / D (전체 백업) | `msdb.dbo.backupset` |

- `msdb.dbo.backupset` 의 start / finish 시각은 초 단위라 두 값이 같습니다 (DATEDIFF = 0 ms). 실제 소요 시간은 BACKUP 메시지의 0.227초를 기준으로 합니다.
- 백업 파일 크기는 `C:\Program Files` 아래 폴더를 이 작업 환경에서 직접 조회할 권한이 없어 `backup_size` 로 기록했습니다.

## 2. RESTORE VERIFYONLY ... WITH CHECKSUM

| 항목 | 결과 |
|---|---|
| 메시지 | `파일 1에서 백업 세트를 사용할 수 있습니다.` |
| 판정 | **정상** (백업 세트를 읽을 수 있고 체크섬 검증 통과) |
| 소요 시간 (클라이언트) | 76 ms |

VERIFYONLY 는 백업 파일을 읽을 수 있는지만 확인하며, 실제 복원 후 데이터가 맞는지는 확인하지 않습니다 (그건 4번 복구 연습에서 확인).

## 3. RESTORE FILELISTONLY

| LogicalName | PhysicalName (원본) | Type | FileGroup | Size (bytes) | BackupSizeInBytes |
|---|---|---|---|---:|---:|
| healthdb | `...\MSSQL\DATA\healthdb.mdf` | D | PRIMARY | 142,606,336 | 121,372,672 |
| healthdb_log | `...\MSSQL\DATA\healthdb_log.ldf` | L | - | 142,606,336 | 0 |

논리 파일명은 `healthdb`, `healthdb_log` 로 `06_backup.sql` 4번(복구 연습)의 `WITH MOVE` 이름과 같습니다.

## 4. 복구 연습 (healthdb_restore)

원본 `healthdb` 는 건드리지 않고, 같은 백업 파일을 **별도 이름 `healthdb_restore`** 로 복원했습니다 (2026-10-09 12:45, `msdb.dbo.restorehistory` restore_type = D).

```sql
RESTORE DATABASE healthdb_restore
FROM DISK = @bak                                   -- ...\MSSQL\Backup\healthdb_full.bak
WITH MOVE N'healthdb'     TO @mdf,                 -- ...\MSSQL\DATA\healthdb_restore.mdf
     MOVE N'healthdb_log' TO @ldf,                 -- ...\MSSQL\DATA\healthdb_restore_log.ldf
     RECOVERY;
```

### 복원 시간

| 항목 | 값 | 출처 |
|---|---|---|
| 처리 페이지 | 14,834 (데이터 14,832 + 로그 2) | RESTORE 완료 메시지 |
| 소요 시간 (서버) | **0.215초** (539.007 MB/초) | RESTORE 완료 메시지 |
| 소요 시간 (클라이언트) | 535 ms | Python 에서 실행~완료까지 측정 |
| 복원 후 상태 | ONLINE, 복구 모델 SIMPLE | `sys.databases` |

### 파일 경로 비교

| DB | 논리 이름 | 종류 | 물리 파일 |
|---|---|---|---|
| healthdb | healthdb | ROWS | `...\MSSQL\DATA\healthdb.mdf` |
| healthdb | healthdb_log | LOG | `...\MSSQL\DATA\healthdb_log.ldf` |
| healthdb_restore | healthdb | ROWS | `...\MSSQL\DATA\healthdb_restore.mdf` |
| healthdb_restore | healthdb_log | LOG | `...\MSSQL\DATA\healthdb_restore_log.ldf` |

4개 물리 경로가 모두 서로 다릅니다 (`...` = `C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS`).

### 원본과 대조

| 항목 | healthdb | healthdb_restore | 일치 |
|---|---:|---:|---|
| fact_checkup 행 수 | 1,000,000 | 1,000,000 | ✅ |
| 쿼리 A 결과 (`sido_code = 11 AND (sbp >= 140 OR dbp >= 90)`) | 23,884 | 23,884 | ✅ |
| dim_sido / dim_sex / dim_age_group 행 수 | 17 / 2 / 18 | 17 / 2 / 18 | ✅ |
| fact_checkup 인덱스 | pk_fact_checkup, ix_checkup_sido_bp, ix_checkup_year_age_sex | 동일 | ✅ |
| etl_log | 1행 (아래) | 1행 (아래) | ✅ 7개 컬럼 모두 동일 |

etl_log (두 DB 동일): `log_id 1 | 2026-10-09 11:57:57 | 국민건강보험공단_건강검진정보_2023.CSV | rows_read 1,000,000 | rows_loaded 1,000,000 | rows_dropped 0 | 제외 없음`

### 정리

위 대조 결과를 확인한 뒤 별도 승인을 받아 `DROP DATABASE healthdb_restore;` 로 정리했습니다 (2026-10-09).

실행 전 확인:

| 항목 | 결과 |
|---|---|
| 대상 이름 | `healthdb_restore` (원본 `healthdb` 아님, 이름 일치 확인 후 실행) |
| healthdb_restore 접속 세션 | 0 |
| 백업 파일 재검증 (`RESTORE VERIFYONLY ... WITH CHECKSUM`) | `파일 1에서 백업 세트를 사용할 수 있습니다.` → 필요하면 같은 백업으로 다시 복원 가능 |

실행 후 최종 상태:

| 항목 | 결과 |
|---|---|
| `sys.databases` 의 healthdb% | `healthdb` 만 존재 |
| `DB_ID('healthdb_restore')` | NULL (없음) |
| `sys.master_files` 의 healthdb_restore 파일 | 0개 |
| healthdb 상태 | ONLINE |
| healthdb.dbo.fact_checkup 행 수 | **1,000,000** (변화 없음) |
| healthdb 쿼리 A 결과 | 23,884 (변화 없음) |
| healthdb.dbo.etl_log 행 수 | 1 |
| 백업 파일 `healthdb_full.bak` | 유지 (삭제하지 않음) |

## 한계점

- 백업 / 복원 시간은 136 MB 규모 DB 를 단일 PC 에서 1회씩 측정한 값입니다.
- 복구 모델이 SIMPLE 이라 로그 백업과 특정 시점 복구(Point-in-time)는 다루지 않았습니다.
- 백업 파일을 같은 PC·같은 디스크에 두었습니다. 실제 운영이라면 다른 장비나 원격 저장소에 복사본을 두어야 합니다.
