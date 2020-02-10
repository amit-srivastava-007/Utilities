---define variables and its values
 
:setvar DB <DB>
:setvar SRC <SourceServer>
:setvar TGT <TargetServer>
:setvar BACKUP_PATH <local or nfs>
:setvar RESTORE_PATH <local or nfs>
:setvar DATAFILENAME <DataFileName>
:setvar LOGFILENAME <LogFileName>
:setvar RESTORE_DATA_PATH "<Data file path>"
:setvar RESTORE_LOG_PATH "<LogFilePath>"

:setvar DESIRED_COMPATIBILITY_LEVEL <DesiredCompatibilityLevel>



--:setvar COPYPATH f$\PowerSQL
:setvar Timeout 100
 
---Precheck for an existence of DB
 
:CONNECT $(SRC)
SELECT @@Servername
select * from sys.databases  where name='$(DB)'
Go
:CONNECT $(TGT)
SELECT @@Servername
select * from sys.databases where name='$(DB)'
GO
 
:CONNECT $(SRC)
-- Compression Option is set
BACKUP DATABASE $(DB) TO DISK = '$(BACKUP_PATH)\$(DB).bak'
WITH  COPY_ONLY, NOFORMAT, INIT,  NAME = '$(DB) Full DB Backup', SKIP, NOREWIND, NOUNLOAD, STATS = 5,COMPRESSION
GO

--2. Copy the files from SRC to TGT , Refer below link for more --information
 
print '*** Copy DB $(DB) from SRC server $(SRC) to TGT server $(TGT) ***'
!!ROBOCOPY $(BACKUP_PATH)\ \\$(TGT)\$(COPYPATH) $(DB).*
GO

---–3. Restore DB to TGT
print '*** Restore full backup of DB $(DB) ***'
:CONNECT $(TGT)
GO
USE [master]
GO
IF EXISTS (select * from sys.databases where name='$(DB)')
BEGIN
ALTER DATABASE $(DB) SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
DROP DATABASE $(DB)
END
RESTORE DATABASE $(DB)
   FROM disk = '$(RESTORE_PATH)\$(DB).bak'
  WITH RECOVERY, NOUNLOAD,  STATS = 10,REPLACE,
  MOVE '$(DATAFILENAME)' TO 
'$(RESTORE_DATA_PATH)\$(DATAFILENAME).mdf',
      MOVE '$(LOGFILENAME)'
TO '$(RESTORE_DATA_PATH)\$(LOGFILENAME).ldf'
GO
 


--Set Competibility Level if Source and Target have different Compatibility Level

IF ((SELECT COMPATIBILITY_LEVEL FROM SYS.DATABASES WHERE NAME='$(DB)') < $(DESIRED_COMPATIBILITY_LEVEL))
BEGIN
ALTER DATABASE $(DB)
SET COMPATIBILITY_LEVEL = $(DESIRED_COMPATIBILITY_LEVEL)
END
GO

---Post Check for an existence of DB on both SRC and TGT
 
:CONNECT $(SRC)
SELECT @@Servername
select * from sys.databases where name='$(DB)'
GO
SELECT @@Servername
:CONNECT $(TGT)
select * from sys.databases where name='$(DB)'
