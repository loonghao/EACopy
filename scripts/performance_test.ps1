# Performance Test Script for EACopy vs Robocopy
# This script compares the performance of EACopy and Robocopy for various file operations

# Parameters
param (
    [string]$EACopyPath = "",  # Empty by default, will auto-detect
    [string]$TestDir = ".\perf_test",
    [int]$SmallFileCount = 1000,
    [int]$SmallFileSize = 10KB,
    [int]$MediumFileCount = 100,
    [int]$MediumFileSize = 1MB,
    [int]$LargeFileCount = 10,
    [int]$LargeFileSize = 10MB,
    [switch]$CleanupAfterTest = $true,
    [string]$HistoryDir = ".\performance_history",
    [string]$CommitId = ""
)

# Create test directories
$SourceDir = Join-Path $TestDir "source"
$DestDir1 = Join-Path $TestDir "dest_eacopy"
$DestDir2 = Join-Path $TestDir "dest_robocopy"

# Ensure test directories exist
New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null
New-Item -ItemType Directory -Force -Path $DestDir1 | Out-Null
New-Item -ItemType Directory -Force -Path $DestDir2 | Out-Null

# Function to create test files
function Create-TestFiles {
    param (
        [string]$Directory,
        [int]$Count,
        [int]$Size,
        [string]$Prefix
    )

    Write-Host "Creating $Count $Prefix files of size $Size in $Directory..."

    # Create subdirectories to simulate a more realistic file structure
    $SubDirCount = [Math]::Min(10, $Count / 10)
    for ($i = 1; $i -le $SubDirCount; $i++) {
        $SubDir = Join-Path $Directory "subdir_$i"
        New-Item -ItemType Directory -Force -Path $SubDir | Out-Null
    }

    for ($i = 1; $i -le $Count; $i++) {
        # Determine if this file should go in a subdirectory
        $TargetDir = $Directory
        if ($i % 10 -eq 0 -and $SubDirCount -gt 0) {
            $SubDirIndex = ($i / 10) % $SubDirCount + 1
            $TargetDir = Join-Path $Directory "subdir_$SubDirIndex"
        }

        $FilePath = Join-Path $TargetDir "$Prefix`_file_$i.dat"
        $Buffer = New-Object byte[] $Size
        (New-Object Random).NextBytes($Buffer)
        [System.IO.File]::WriteAllBytes($FilePath, $Buffer)

        # Show progress for large files
        if ($Size -gt 1MB -and $i % 5 -eq 0) {
            Write-Host "  Created $i of $Count files..."
        }
    }

    Write-Host "Created $Count $Prefix files."
}

# Function to measure performance
function Measure-CopyPerformance {
    param (
        [string]$Tool,
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Arguments
    )

    # Clear destination directory
    if (Test-Path $DestPath) {
        Remove-Item -Path $DestPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $DestPath | Out-Null

    # Prepare command
    $Command = ""
    if ($Tool -eq "EACopy") {
        $Command = "$EACopyPath $SourcePath $DestPath $Arguments"
    } elseif ($Tool -eq "Robocopy") {
        $Command = "robocopy $SourcePath $DestPath /E $Arguments"
    }

    Write-Host "Running: $Command"

    # Measure performance
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Tool -eq "EACopy") {
        & $EACopyPath $SourcePath $DestPath $Arguments | Out-Null
        $ExitCode = $LASTEXITCODE
    } elseif ($Tool -eq "Robocopy") {
        & robocopy $SourcePath $DestPath /E $Arguments | Out-Null
        # Robocopy exit codes are different - 0-7 are success with various levels of copying activity
        $ExitCode = if ($LASTEXITCODE -le 7) { 0 } else { $LASTEXITCODE }
    }

    $StopWatch.Stop()
    $ElapsedTime = $StopWatch.Elapsed

    # Get total size copied
    $Size = (Get-ChildItem -Path $SourcePath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $SizeMB = [Math]::Round($Size / 1MB, 2)

    # Calculate throughput
    $ThroughputMBps = if ($ElapsedTime.TotalSeconds -gt 0) { [Math]::Round($SizeMB / $ElapsedTime.TotalSeconds, 2) } else { 0 }

    # Return result
    return @{
        Tool = $Tool
        ElapsedTime = $ElapsedTime
        ElapsedSeconds = [Math]::Round($ElapsedTime.TotalSeconds, 2)
        SizeMB = $SizeMB
        ThroughputMBps = $ThroughputMBps
        ExitCode = $ExitCode
    }
}

# Function to run a test scenario
function Run-TestScenario {
    param (
        [string]$ScenarioName,
        [string]$SourcePath,
        [string]$EACopyArgs = "",
        [string]$RobocopyArgs = ""
    )

    Write-Host "`n========== Running Test Scenario: $ScenarioName ==========" -ForegroundColor Cyan

    # Run EACopy
    $EACopyResult = Measure-CopyPerformance -Tool "EACopy" -SourcePath $SourcePath -DestPath $DestDir1 -Arguments $EACopyArgs

    # Run Robocopy
    $RobocopyResult = Measure-CopyPerformance -Tool "Robocopy" -SourcePath $SourcePath -DestPath $DestDir2 -Arguments $RobocopyArgs

    # Calculate performance difference
    $TimeDiff = $RobocopyResult.ElapsedSeconds - $EACopyResult.ElapsedSeconds
    $TimeDiffPercent = if ($RobocopyResult.ElapsedSeconds -gt 0) {
        [Math]::Round(($TimeDiff / $RobocopyResult.ElapsedSeconds) * 100, 2)
    } else {
        0
    }

    $ThroughputDiff = $EACopyResult.ThroughputMBps - $RobocopyResult.ThroughputMBps
    $ThroughputDiffPercent = if ($RobocopyResult.ThroughputMBps -gt 0) {
        [Math]::Round(($ThroughputDiff / $RobocopyResult.ThroughputMBps) * 100, 2)
    } else {
        0
    }

    # Determine which tool is faster
    $FasterTool = if ($EACopyResult.ElapsedSeconds -lt $RobocopyResult.ElapsedSeconds) { "EACopy" } else { "Robocopy" }

    # Print results
    Write-Host "`nResults for ${ScenarioName}:" -ForegroundColor Green
    Write-Host "EACopy: $($EACopyResult.ElapsedSeconds) seconds, $($EACopyResult.ThroughputMBps) MB/s"
    Write-Host "Robocopy: $($RobocopyResult.ElapsedSeconds) seconds, $($RobocopyResult.ThroughputMBps) MB/s"
    Write-Host "Difference: $TimeDiff seconds ($TimeDiffPercent%), $ThroughputDiff MB/s ($ThroughputDiffPercent%)"
    Write-Host "Faster tool: $FasterTool"

    # Return results
    return @{
        ScenarioName = $ScenarioName
        EACopy = $EACopyResult
        Robocopy = $RobocopyResult
        TimeDiff = $TimeDiff
        TimeDiffPercent = $TimeDiffPercent
        ThroughputDiff = $ThroughputDiff
        ThroughputDiffPercent = $ThroughputDiffPercent
        FasterTool = $FasterTool
    }
}

# Main test execution
try {
    Write-Host "Starting performance tests for EACopy vs Robocopy" -ForegroundColor Yellow

    # Auto-detect EACopy.exe if path not provided
    if (-not $EACopyPath) {
        $PossiblePaths = @(
            ".\Release\EACopy.exe",
            ".\Debug\EACopy.exe",
            "..\Release\EACopy.exe",
            "..\Debug\EACopy.exe",
            ".\build_Release\Release\EACopy.exe",
            ".\build_Debug\Debug\EACopy.exe",
            "..\build_Release\Release\EACopy.exe",
            "..\build_Debug\Debug\EACopy.exe"
        )

        foreach ($Path in $PossiblePaths) {
            if (Test-Path $Path) {
                $EACopyPath = $Path
                Write-Host "Auto-detected EACopy at: $EACopyPath" -ForegroundColor Green
                break
            }
        }
    }

    # Check if EACopy executable exists
    if (-not $EACopyPath -or -not (Test-Path $EACopyPath)) {
        Write-Error "EACopy executable not found. Please provide the correct path using the -EACopyPath parameter."
        Write-Host "Tried the following paths:" -ForegroundColor Red
        foreach ($Path in $PossiblePaths) {
            Write-Host "  - $Path" -ForegroundColor Red
        }
        exit 1
    }

    Write-Host "EACopy path: $EACopyPath"
    Write-Host "Test directory: $TestDir"

    # Create test files
    Create-TestFiles -Directory $SourceDir -Count $SmallFileCount -Size $SmallFileSize -Prefix "small"
    Create-TestFiles -Directory $SourceDir -Count $MediumFileCount -Size $MediumFileSize -Prefix "medium"
    Create-TestFiles -Directory $SourceDir -Count $LargeFileCount -Size $LargeFileSize -Prefix "large"

    # Run test scenarios
    $Results = @()
    $Results += Run-TestScenario -ScenarioName "All Files" -SourcePath $SourceDir
    $Results += Run-TestScenario -ScenarioName "Small Files Only" -SourcePath "$SourceDir\small*"
    $Results += Run-TestScenario -ScenarioName "Medium Files Only" -SourcePath "$SourceDir\medium*"
    $Results += Run-TestScenario -ScenarioName "Large Files Only" -SourcePath "$SourceDir\large*"

    # Generate summary
    Write-Host "`n========== Performance Test Summary ==========" -ForegroundColor Yellow
    Write-Host "| Scenario | EACopy | Robocopy | Difference | Faster Tool |"
    Write-Host "|----------|--------|----------|------------|-------------|"

    foreach ($Result in $Results) {
        $ScenarioName = $Result.ScenarioName
        $EACopyTime = "$($Result.EACopy.ElapsedSeconds)s ($($Result.EACopy.ThroughputMBps) MB/s)"
        $RobocopyTime = "$($Result.Robocopy.ElapsedSeconds)s ($($Result.Robocopy.ThroughputMBps) MB/s)"
        $Difference = "$($Result.TimeDiffPercent)%"
        $FasterTool = $Result.FasterTool

        Write-Host "| $ScenarioName | $EACopyTime | $RobocopyTime | $Difference | $FasterTool |"
    }

    # Generate JSON output for CI
    $JsonOutput = @{
        TestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TestResults = $Results
    } | ConvertTo-Json -Depth 5

    $JsonOutputPath = Join-Path $TestDir "performance_results.json"
    $JsonOutput | Out-File -FilePath $JsonOutputPath -Encoding utf8

    Write-Host "`nPerformance test results saved to: $JsonOutputPath" -ForegroundColor Green

    # Save to history directory if specified
    if ($HistoryDir -and (Test-Path $HistoryDir -PathType Container)) {
        # Create history directory if it doesn't exist
        if (-not (Test-Path $HistoryDir)) {
            New-Item -ItemType Directory -Force -Path $HistoryDir | Out-Null
        }

        # Generate filename with timestamp and commit ID if available
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $CommitSuffix = if ($CommitId) { "_$CommitId" } else { "" }
        $HistoryFileName = "performance_${Timestamp}${CommitSuffix}.json"
        $HistoryFilePath = Join-Path $HistoryDir $HistoryFileName

        # Save to history file
        $JsonOutput | Out-File -FilePath $HistoryFilePath -Encoding utf8
        Write-Host "Performance test results saved to history: $HistoryFilePath" -ForegroundColor Green
    }

    # Generate markdown report for PR comment
    $MarkdownReport = @"
## EACopy vs Robocopy Performance Test Results

Test conducted on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

| Scenario | EACopy | Robocopy | Difference | Faster Tool |
|----------|--------|----------|------------|-------------|
"@

    foreach ($Result in $Results) {
        $ScenarioName = $Result.ScenarioName
        $EACopyTime = "$($Result.EACopy.ElapsedSeconds)s ($($Result.EACopy.ThroughputMBps) MB/s)"
        $RobocopyTime = "$($Result.Robocopy.ElapsedSeconds)s ($($Result.Robocopy.ThroughputMBps) MB/s)"
        $Difference = "$($Result.TimeDiffPercent)%"
        $FasterTool = $Result.FasterTool

        $MarkdownReport += "`n| $ScenarioName | $EACopyTime | $RobocopyTime | $Difference | $FasterTool |"
    }

    $MarkdownReport += @"

### Test Configuration
- Small Files: $SmallFileCount files of $SmallFileSize each
- Medium Files: $MediumFileCount files of $MediumFileSize each
- Large Files: $LargeFileCount files of $LargeFileSize each
"@

    $MarkdownReportPath = Join-Path $TestDir "performance_results.md"
    $MarkdownReport | Out-File -FilePath $MarkdownReportPath -Encoding utf8

    Write-Host "`nMarkdown report saved to: $MarkdownReportPath" -ForegroundColor Green

} finally {
    # Cleanup if requested
    if ($CleanupAfterTest) {
        Write-Host "`nCleaning up test directories..." -ForegroundColor Yellow
        if (Test-Path $TestDir) {
            Remove-Item -Path $TestDir -Recurse -Force
        }
    }
}
