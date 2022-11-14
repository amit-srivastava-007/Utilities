DECLARE @MySchemaName VARCHAR(50)='<schemaname>', @sql VARCHAR(MAX)='';
DECLARE @SchemaName VARCHAR(255), @ObjectName VARCHAR(255), @ObjectType VARCHAR(255), @ObjectDesc VARCHAR(255), @Category INT;

DECLARE cur CURSOR FOR
    SELECT  (s.name)SchemaName, (o.name)ObjectName, (o.type)ObjectType,(o.type_desc)ObjectDesc,(so.category)Category
    FROM    sys.objects o
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    INNER JOIN sysobjects so ON so.name=o.name
    WHERE s.name = @MySchemaName
    AND so.category=0
    AND o.type IN ('P','PC','U','V','FN','IF','TF','FS','FT','PK','TT')

OPEN cur
FETCH NEXT FROM cur INTO @SchemaName,@ObjectName,@ObjectType,@ObjectDesc,@Category

SET @sql='';
WHILE @@FETCH_STATUS = 0 BEGIN    
    IF @ObjectType IN('FN', 'IF', 'TF', 'FS', 'FT') SET @sql=@sql+'Drop Function '+@MySchemaName+'.'+@ObjectName+CHAR(13)
    IF @ObjectType IN('V') SET @sql=@sql+'Drop View '+@MySchemaName+'.'+@ObjectName+CHAR(13)
    IF @ObjectType IN('P') SET @sql=@sql+'Drop Procedure '+@MySchemaName+'.'+@ObjectName+CHAR(13)
    IF @ObjectType IN('U') SET @sql=@sql+'Drop Table '+@MySchemaName+'.'+@ObjectName+CHAR(13)

    --PRINT @ObjectName + ' | ' + @ObjectType
    FETCH NEXT FROM cur INTO @SchemaName,@ObjectName,@ObjectType,@ObjectDesc,@Category
END
CLOSE cur;    
DEALLOCATE cur;
SET @sql=@sql+CASE WHEN LEN(@sql)>0 THEN 'Drop Schema '+@MySchemaName+CHAR(13) ELSE '' END
PRINT @sql
--EXECUTE (@sql)
