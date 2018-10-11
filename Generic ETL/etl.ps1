Import-Module sqlps
#Connect to SQL Database

$TargetServer = "."
$DestDB = "destDB"
$DestSchema = "dbo"

$SourceDB = "SourceDB"
$SourceSchema = "dbo"
$SourceServer = "."

$connectionString = "Server = $TargetServer; Database = $DestDB; user id=<userid>; password=<userid>"

$masterTableList = <List of tables to be excluded from etl>

function Execute-Sql {
    param (
        $sql, $connectionString
    )
    $Connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $Connection.Open()
    $Command = New-Object system.Data.SqlClient.SqlCommand($sql, $Connection) 
    $Command.CommandTimeout = 0  
    $Command.ExecuteNonQuery()
    $Connection.Close()
}

function Execute-DataTable {
    param (
        $sql, $connectionString
    )
    $Datatable = New-Object System.Data.DataTable  
    $Connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $Connection.Open()
    $Command = New-Object system.Data.SqlClient.SqlCommand($sql, $Connection) 
    $Reader = $Command.ExecuteReader()
    $Datatable.Load($Reader)
    $connection.Close()

    return $Datatable
}

function Get-Dependency {
    
    $sql = "EXEC sp_msdependencies @intrans = 1"
    return Execute-DataTable $sql $ConnectionString
}

function Clear-Table {
    param (
        $table
    )
    $sql = "DELETE FROM " + $table
    Write-Debug $sql
    return Execute-Sql $sql $ConnectionString
}

function Get-Columns {
    param (
        $table
    )
    $sql = "select TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = '" + $table + "' order by ORDINAL_POSITION"
    return Execute-DataTable $sql $ConnectionString
}


function Copy-SqlTable {
    <#
    .DESCRIPTION
      Copy single table from source database to target database on same SQL Server Database Engine instance. 
    #>
    [CmdletBinding()]
    [OutputType([void])]
    Param($table)
    
    Begin {
        $mywatch = [System.Diagnostics.Stopwatch]::StartNew() 
        "{0:s}Z :: Copying to $table `n" -f [System.DateTime]::UtcNow | Write-Output
    
        [string]$ApplicationName = 'ETL Insert'
    
        #Candidates for function parameters:
        [string]$SourceInstanceName = $SourceServer
        [string]$SourceDatabaseName = $SourceDB
        [string]$SourceTableName = $table
    
        [string]$TargetInstanceName = $TargetServer
        [string]$TargetDatabaseName = $DestDB
        [string]$TargetTableName = $table
    }
    
    Process {
        
        $Columns = Get-Columns $table
        $SourceColumnList = ""

        $Columns | ForEach-Object {
            $SourceColumnList = $SourceColumnList + $(if($_.COLUMN_NAME -eq "Id") { $table + "Id" } else { $_.COLUMN_NAME}) + ","
        }    
        $sql = "Select " + $SourceColumnList.Substring(0, $SourceColumnList.Length - 1) + " from " + $SourceTableName #"Insert Into " + $DestSchema + "." + $table + 
        #"(" + $DestColumnList.Substring(0, $DestColumnList.Length - 1) + ")" + 
        

        #Write-Host $sql

        'Connect to source...' | Write-Output
        [string]$CnnStrSource = "Data Source=$SourceInstanceName;Initial Catalog=$SourceDatabaseName;Application Name=$ApplicationName; User Id=<userid>; password=<password>"
        "Source connection string: '$CnnStrSource'" | Write-Verbose
        $SqlCnnSource = New-Object -TypeName System.Data.SqlClient.SqlConnection $CnnStrSource
        $SqlCommand = New-Object -TypeName System.Data.SqlClient.SqlCommand($sql, $SqlCnnSource)
        $SqlCnnSource.Open()
        [System.Data.SqlClient.SqlDataReader]$SqlReader = $SqlCommand.ExecuteReader()
    
        'Copy to target...' | Write-Output
        [string]$CnnStrTarget = "Data Source=$TargetInstanceName;Initial Catalog=$TargetDatabaseName;Application Name=$ApplicationName; User Id=<userid>; password=<password>"
        "Target connection string: '$CnnStrTarget'" | Write-Verbose
        try {
            $SqlBulkCopy = New-Object -TypeName System.Data.SqlClient.SqlBulkCopy($CnnStrTarget, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
            $Columns | ForEach-Object {
                #custom mapping logic
                If ($_.COLUMN_NAME -eq "Id"){
                    $SqlBulkCopy.ColumnMappings.Add($table + "Id", "Id")
                }
                else {
                    $SqlBulkCopy.ColumnMappings.Add($_.COLUMN_NAME, $_.COLUMN_NAME) 
                }
            }
			
            $SqlBulkCopy.EnableStreaming = $true
            $SqlBulkCopy.DestinationTableName = $TargetTableName
            $SqlBulkCopy.BatchSize = 1000000  # Another candidate for function parameter
            $SqlBulkCopy.BulkCopyTimeout = 0 # seconds, 0 (zero) = no timeout limit
            $SqlBulkCopy.NotifyAfter = 1000
            $SqlBulkCopy.WriteToServer($SqlReader)
        }
        catch [System.Exception] {
            $_.Exception | Write-Output
        }
        finally {
            "Copy complete. Closing...`n" | Write-Output
            $SqlReader.Close()
            $SqlCnnSource.Close()
            $SqlCnnSource.Dispose()
            $SqlBulkCopy.Close()
        }
    }
    
    End {
        $mywatch.Stop()
        [string]$Message = "Copy finished with success. Duration = $($mywatch.Elapsed.ToString()). [hh:mm:ss.ddd] {0:s}Z $Message" -f [System.DateTime]::UtcNow | Write-Output
    }
} # Copy-SqlTable


$InsertionOrder = New-Object System.Data.DataTable
$InsertionOrder = Get-Dependency

$DeletionOrder = $InsertionOrder | Sort-Object -Descending -Property oSequence

$DeletionOrder | FOREACH-OBJECT {

    if (-not $masterTableList.Contains($_.oObjName)) {
        write-host "Cleaning Table:" $_.oObjName

        Clear-Table $_.oObjName
    }  
}

$InsertionOrder | ForEach-Object {
    $table = $_.oObjName
    
    $DestColumnList = ""
    

    if (-not $masterTableList.Contains($table)) {
        $Columns | ForEach-Object {
            $DestColumnList = $DestColumnList + $_.COLUMN_NAME + ","
        }

        Copy-SqlTable $table
    }
}