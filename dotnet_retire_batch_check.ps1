$CurrentPath = $PWD

Get-ChildItem -Filter *.csproj -Recurse | Select Directory | ForEach-Object {
    cd $_.Directory
    Write-Host "Scanning" $_.Directory
    dotnet-retire.exe
    Write-Host "`n`n"
    cd $CurrentPath
}
