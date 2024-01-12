param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Provide path to the solution file")][string]$solutionPath,
    [Parameter(Position = 1, Mandatory = $false)][string]$generateReport,
    [Parameter(ParameterSetName = 'sonar', Mandatory = $false, Position = 3)][string]$runSonarAnalysis,
    [Parameter(ParameterSetName = 'sonar', Mandatory = $false)][string]$sonarUrl,
    [Parameter(ParameterSetName = 'sonar', Mandatory = $false)][string]$sonarProjectKey = "project_key",
    [Parameter(ParameterSetName = 'sonar', Mandatory = $false)][string]$sonarToken = "N"
)
#exit
#Validate rootPath
[string]$solutionRootPath = ""
[string]$solutionFile = ""
[string]$defaultSonarHost = "http://localhost:9000"

$correctPath = $false
While ($correctPath -eq $false) {
    if (Test-Path $solutionPath\*.sln -PathType Leaf) {
        if (Test-Path $solutionPath -PathType Container) {
            #given path is folder
            $solutionRootPath = $solutionPath
        }
        else {
            #given path is absolute file path
            $solutionRootPath = Split-Path -Path $solutionPath
        }
        $solutionFile = (Get-ChildItem -Path $solutionPath -Filter *.sln).Name
        $correctPath = $true
        Write-host "Solution File found: " $solutionFile
    }
    if ($correctPath -ne $true) {
        $solutionPath = Read-Host "No Solution file found. Please enter correct path"
    }
}

$coverageDestination = Join-Path $solutionRootPath "Coverage"
$baseLocation = Get-Location

Write-Host "Coverage destination " $coverageDestination

$relativePath = ""
Set-Location $solutionRootPath

function Run_Test {
    param (
        [Parameter(Mandatory = $true)]$testPath, [string]$sequence
    )
    Set-Location $testPath.DirectoryName
    
    $relativePath = (Resolve-Path -relative $coverageDestination)
    
    if ($sequence -eq "first") {
        dotnet test $testPath.Name /p:collectCoverage=true /p:CoverletOutput=$relativePath/
    }
    elseif ($sequence -ne "first" -and $sequence -ne "last" ) {
        dotnet test $testPath.Name /p:collectCoverage=true /p:CoverletOutput=$relativePath/ /p:MergeWith="$relativePath/coverage.json"
    }
    elseif ($sequence -eq "last") {
        dotnet test $testPath.Name /p:collectCoverage=true /p:CoverletOutput=$relativePath/ /p:MergeWith="$relativePath/coverage.json" /p:CoverletOutputFormat="opencover"
    }
}

function Ask_Choice {
    param (
        [string]$heading,
        [string]$description,
        [string]$hint_yes,
        [string]$hint_no
    )
    $title = $heading
    $question = $description

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No', $hint_no ))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', $hint_yes))

    $decision = $Host.UI.PromptForChoice($title, $question, $choices, 0)
    return $decision
}

Write-Host "Cleaning old coverage files and report"
if (Test-Path $coverageDestination) {
    Remove-Item $coverageDestination -Force -Recurse
    #Get-ChildItem -Path $coverageDestination -Include *.* -File -Recurse | ForEach-Object { $_.Delete() }
}

New-Item $coverageDestination -ItemType Directory | Out-Null

Write-Host "Starting coverage..."

$testProjects = Get-ChildItem -Path $solutionRootPath -Filter *Test.csproj -Recurse -File | Sort-Object Length -Descending

Run_Test -testPath ($testProjects | Select-Object Name, DirectoryName -First 1) -sequence "first"

($testProjects | Select-object Name, DirectoryName -skip 1) | Select-Object Name, DirectoryName -skipLast 1 | ForEach-Object {
    Run_Test -testPath $_
}

Run_Test -testPath ($testProjects | Select-Object Name, DirectoryName -Last 1) -sequence "last"

Set-Location $solutionRootPath

if ($generateReport -eq "") {
    $generateReport = Ask_Choice "Generate Report" "Report generation option is not set. Dou you want to generate report" "Coverage report will be generated" "Coverage report will not be generated"
}
if ($generateReport -or $generateReport -ne "N") {
    Write-Host "Generating Coverage report..."
    
    if (-not (Test-Path $solutionRootPath\.config\dotnet-tools.json)) {
        Invoke-Command -ScriptBlock { dotnet new tool-manifest }
    }
    if (dotnet tool list | Select-String "reportgenerator") {
        Write-Host -ForegroundColor DarkGreen 'Skipping installation of reportgenerator. It''s already installed'
    }
    else {
        Write-Warning "No Reporting tool exists!!"
        Invoke-Command -ScriptBlock { dotnet tool install dotnet-reportgenerator-globaltool --version 4.6.1 }
    }
    dotnet reportgenerator "-reports:$coverageDestination\coverage.opencover.xml" "-targetdir:$coverageDestination" -reporttypes:Html

    invoke-item $coverageDestination\index.html
}

if ($runSonarAnalysis -eq "") {
    $runSonarAnalysis = Ask_Choice "Sonar Report" "Do you want to push coverage to Sonarqube"
}
if ($runSonarAnalysis -or $runSonarAnalysis -ne "N") {
    if ($sonarUrl -eq "") {
        if (-not (Ask_Choice "Sonarqube host Url" "SonarQube host url set to default http://localhost:9000. Do you want to continue with this")) {
            $sonarUrl = Read-Host "Enter SonarQube host url"
        }
        else {
            $sonarUrl = $defaultSonarHost
        }
    }
    if ($sonarProjectKey -eq "") {
        $sonarProjectKey = Read-Host "Enter project key"
    }
    if ($sonarToken -eq "" -or $sonarToken -ne "N") {
        if (Ask_Choice "Sonarqube auth token" "No token is set. Is token required to connect to sonar") {
            $sonarToken = Read-Host "Enter SonarQube auth token"
        }
    }
    
    try {
        if ($sonarToken -eq "" -or $sonarToken -eq "N") {
            dotnet sonarscanner begin /k:$sonarProjectKey /d:sonar.host.url=$sonarUrl /d:sonar.cs.opencover.reportsPaths=$coverageDestination/coverage.opencover.xml
            dotnet build .\App.sln
            dotnet sonarscanner end
        }
        else {
            dotnet sonarscanner begin /k:$sonarProjectKey /d:sonar.host.url=$sonarUrl /d:sonar.login=$sonarToken  /d:sonar.cs.opencover.reportsPaths=$coverageDestination/coverage.opencover.xml
            dotnet build .\App.sln
            dotnet sonarscanner end /d:sonar.login=$sonarToken
        } 
    }
    catch {
        Write-Host -ForegroundColor Red "Something went wrong while Sonar Analysis"
    }
}    

Set-Location $baseLocation
