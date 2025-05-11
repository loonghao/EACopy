# Performance Test Script for EACopy vs Robocopy
# This script compares the performance of EACopy and Robocopy for various file operations
# It also collects system information and performance metrics to provide context for the results

# Parameters
param (
    [string]$EACopyPath = "",  # Empty by default, will auto-detect
    [string]$TestDir = ".\perf_test",
    [int]$SmallFileCount = 1000,
    [long]$SmallFileSize = 10KB,
    [int]$MediumFileCount = 100,
    [long]$MediumFileSize = 2MB,
    [int]$LargeFileCount = 5,
    [long]$LargeFileSize = 1GB,  # Reduced from 5120MB to 1GB for more realistic testing
    [switch]$CleanupAfterTest = $true,
    [string]$HistoryDir = ".\performance_history",
    [string]$CommitId = "",
    [switch]$CollectDetailedMetrics = $true,  # Whether to collect detailed system metrics during tests
    [int]$MetricSamplingInterval = 1,  # Seconds between metric samples during tests
    [switch]$DisableCache = $true,  # Whether to attempt to disable file system cache
    [switch]$VerifyCopy = $true    # Whether to verify file copy results
)

# Function to collect system information
function Get-SystemInfo {
    Write-Host "Collecting system information..." -ForegroundColor Yellow

    # CPU Information
    $Processor = Get-WmiObject -Class Win32_Processor
    $CPUModel = $Processor.Name
    $CPUCores = $Processor.NumberOfCores
    $CPULogicalProcessors = $Processor.NumberOfLogicalProcessors
    $CPUMaxClockSpeed = $Processor.MaxClockSpeed

    # Memory Information
    $ComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
    $TotalMemoryGB = [Math]::Round($ComputerSystem.TotalPhysicalMemory / 1GB, 2)

    # OS Information
    $OS = Get-WmiObject -Class Win32_OperatingSystem
    $OSVersion = $OS.Caption
    $OSBuild = $OS.BuildNumber

    # Disk Information
    $SystemDrive = $env:SystemDrive
    $DiskInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$SystemDrive'"
    $DiskSizeGB = [Math]::Round($DiskInfo.Size / 1GB, 2)
    $DiskFreeGB = [Math]::Round($DiskInfo.FreeSpace / 1GB, 2)

    # Try to get disk type (SSD vs HDD)
    $DiskType = "Unknown"
    try {
        # This requires admin privileges, so it might fail
        $PhysicalDisk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $DiskInfo.DeviceID }
        if ($PhysicalDisk) {
            $DiskType = $PhysicalDisk.MediaType
        } else {
            # Fallback method - check for typical SSD performance characteristics
            $DiskPerf = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_PhysicalDisk |
                        Where-Object { $_.Name -eq "_Total" }
            if ($DiskPerf.AvgDiskSecPerRead -lt 0.02) {
                $DiskType = "SSD (estimated)"
            } else {
                $DiskType = "HDD (estimated)"
            }
        }
    } catch {
        Write-Host "Could not determine disk type: $_" -ForegroundColor Yellow
    }

    # Get disk performance baseline
    $DiskReadSpeed = "Unknown"
    $DiskWriteSpeed = "Unknown"
    try {
        Write-Host "  Measuring disk performance baseline..." -ForegroundColor Yellow

        # Create a temporary file for disk speed test
        $TempFile = Join-Path $env:TEMP "disk_speed_test.dat"
        $TestSize = 100MB

        # Measure write speed
        $WriteTest = Measure-Command {
            # Create file stream
            $FileStream = [System.IO.File]::Create($TempFile)
            try {
                # Create buffer and write to file
                $Buffer = New-Object byte[] $TestSize
                (New-Object Random).NextBytes($Buffer)
                $FileStream.Write($Buffer, 0, $TestSize)
                $FileStream.Flush()
            }
            finally {
                # Close file stream
                $FileStream.Close()
                $FileStream.Dispose()
            }
        }
        $DiskWriteSpeed = [Math]::Round($TestSize / $WriteTest.TotalSeconds / 1MB, 2)

        # Measure read speed
        $ReadTest = Measure-Command {
            # Create file stream
            $FileStream = [System.IO.File]::OpenRead($TempFile)
            try {
                # Create buffer and read from file
                $Buffer = New-Object byte[] $TestSize
                $BytesRead = 0
                $TotalBytesRead = 0

                # Read in chunks
                while ($TotalBytesRead -lt $TestSize) {
                    $BytesRead = $FileStream.Read($Buffer, $TotalBytesRead, $TestSize - $TotalBytesRead)
                    if ($BytesRead -eq 0) { break }
                    $TotalBytesRead += $BytesRead
                }
            }
            finally {
                # Close file stream
                $FileStream.Close()
                $FileStream.Dispose()
            }
        }
        $DiskReadSpeed = [Math]::Round($TestSize / $ReadTest.TotalSeconds / 1MB, 2)

        # Clean up
        Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Could not measure disk performance: $_" -ForegroundColor Yellow
    }

    # Return system information
    return @{
        CPU = @{
            Model = $CPUModel
            Cores = $CPUCores
            LogicalProcessors = $CPULogicalProcessors
            MaxClockSpeedMHz = $CPUMaxClockSpeed
        }
        Memory = @{
            TotalGB = $TotalMemoryGB
        }
        OS = @{
            Version = $OSVersion
            Build = $OSBuild
        }
        Disk = @{
            Type = $DiskType
            SizeGB = $DiskSizeGB
            FreeGB = $DiskFreeGB
            ReadSpeedMBps = $DiskReadSpeed
            WriteSpeedMBps = $DiskWriteSpeed
        }
    }
}

# Function to collect system performance metrics during a test
function Start-PerformanceMonitoring {
    param (
        [int]$SamplingInterval = 1  # Seconds between samples
    )

    Write-Host "Starting performance monitoring..." -ForegroundColor Yellow

    # Create a background job to collect metrics
    $MonitoringJob = Start-Job -ScriptBlock {
        param($Interval)

        $Metrics = @()
        $StartTime = Get-Date

        # Collect metrics until stopped
        while ($true) {
            # CPU usage
            $CPUUsage = (Get-WmiObject -Class Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime

            # Memory usage
            $OS = Get-WmiObject -Class Win32_OperatingSystem
            $MemoryUsage = [Math]::Round(($OS.TotalVisibleMemorySize - $OS.FreePhysicalMemory) / $OS.TotalVisibleMemorySize * 100, 2)

            # Disk I/O
            $DiskIO = Get-WmiObject -Class Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
            $DiskReadBytes = $DiskIO.DiskReadBytesPersec
            $DiskWriteBytes = $DiskIO.DiskWriteBytesPersec

            # Network I/O
            $NetworkIO = Get-WmiObject -Class Win32_PerfFormattedData_Tcpip_NetworkInterface | Select-Object -First 1
            $NetworkReceivedBytes = $NetworkIO.BytesReceivedPersec
            $NetworkSentBytes = $NetworkIO.BytesSentPersec

            # Add metrics to collection
            $Metrics += @{
                Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
                ElapsedSeconds = [Math]::Round(((Get-Date) - $StartTime).TotalSeconds, 3)
                CPU = @{
                    UsagePercent = $CPUUsage
                }
                Memory = @{
                    UsagePercent = $MemoryUsage
                }
                Disk = @{
                    ReadBytesPersec = $DiskReadBytes
                    WriteBytesPersec = $DiskWriteBytes
                }
                Network = @{
                    ReceivedBytesPersec = $NetworkReceivedBytes
                    SentBytesPersec = $NetworkSentBytes
                }
            }

            # Wait for next sample
            Start-Sleep -Seconds $Interval
        }

        return $Metrics
    } -ArgumentList $SamplingInterval

    return $MonitoringJob
}

function Stop-PerformanceMonitoring {
    param (
        [System.Management.Automation.Job]$MonitoringJob
    )

    Write-Host "Stopping performance monitoring..." -ForegroundColor Yellow

    # Stop the monitoring job
    Stop-Job -Job $MonitoringJob

    # Get the collected metrics
    $Metrics = Receive-Job -Job $MonitoringJob

    # Clean up
    Remove-Job -Job $MonitoringJob

    # Calculate summary statistics
    $CPUAvg = ($Metrics | Measure-Object -Property { $_.CPU.UsagePercent } -Average).Average
    $CPUMax = ($Metrics | Measure-Object -Property { $_.CPU.UsagePercent } -Maximum).Maximum
    $MemoryAvg = ($Metrics | Measure-Object -Property { $_.Memory.UsagePercent } -Average).Average
    $MemoryMax = ($Metrics | Measure-Object -Property { $_.Memory.UsagePercent } -Maximum).Maximum
    $DiskReadAvg = ($Metrics | Measure-Object -Property { $_.Disk.ReadBytesPersec } -Average).Average
    $DiskReadMax = ($Metrics | Measure-Object -Property { $_.Disk.ReadBytesPersec } -Maximum).Maximum
    $DiskWriteAvg = ($Metrics | Measure-Object -Property { $_.Disk.WriteBytesPersec } -Average).Average
    $DiskWriteMax = ($Metrics | Measure-Object -Property { $_.Disk.WriteBytesPersec } -Maximum).Maximum

    # Return summary and detailed metrics
    return @{
        Summary = @{
            CPU = @{
                AverageUsagePercent = [Math]::Round($CPUAvg, 2)
                MaxUsagePercent = [Math]::Round($CPUMax, 2)
            }
            Memory = @{
                AverageUsagePercent = [Math]::Round($MemoryAvg, 2)
                MaxUsagePercent = [Math]::Round($MemoryMax, 2)
            }
            Disk = @{
                AverageReadMBps = [Math]::Round($DiskReadAvg / 1MB, 2)
                MaxReadMBps = [Math]::Round($DiskReadMax / 1MB, 2)
                AverageWriteMBps = [Math]::Round($DiskWriteAvg / 1MB, 2)
                MaxWriteMBps = [Math]::Round($DiskWriteMax / 1MB, 2)
            }
        }
        DetailedMetrics = $Metrics
    }
}

# Function to normalize performance results based on hardware capabilities
function Normalize-PerformanceResults {
    param (
        [object[]]$Results,
        [hashtable]$SystemInfo
    )

    Write-Host "Normalizing performance results based on hardware capabilities..." -ForegroundColor Yellow

    # Create a copy of the results to avoid modifying the original
    $NormalizedResults = @()

    # Calculate normalization factors based on hardware
    $CPUFactor = 1.0
    $DiskFactor = 1.0

    # CPU normalization - based on a reference of 4 cores at 3.0 GHz
    $ReferenceCores = 4
    $ReferenceClockSpeed = 3000  # MHz
    if ($SystemInfo.CPU.Cores -gt 0 -and $SystemInfo.CPU.MaxClockSpeedMHz -gt 0) {
        $CPUPower = $SystemInfo.CPU.Cores * $SystemInfo.CPU.MaxClockSpeedMHz
        $ReferencePower = $ReferenceCores * $ReferenceClockSpeed
        $CPUFactor = $ReferencePower / $CPUPower
    }

    # Disk normalization - based on a reference SSD with 500 MB/s read speed
    $ReferenceReadSpeed = 500  # MB/s
    if ($SystemInfo.Disk.ReadSpeedMBps -gt 0) {
        $DiskFactor = $ReferenceReadSpeed / $SystemInfo.Disk.ReadSpeedMBps
    }

    # Create normalization factors object
    $NormalizationFactors = @{
        CPU = $CPUFactor
        Disk = $DiskFactor
        Combined = $CPUFactor * $DiskFactor
    }

    # Apply normalization to each test result
    foreach ($Result in $Results) {
        # Create a deep copy of the result
        $NormalizedResult = $Result.Clone()

        # Normalize EACopy results
        $NormalizedResult.EACopy.NormalizedElapsedSeconds = [Math]::Round($Result.EACopy.ElapsedSeconds * $CPUFactor * $DiskFactor, 2)
        $NormalizedResult.EACopy.NormalizedThroughputMBps = [Math]::Round($Result.EACopy.ThroughputMBps / ($CPUFactor * $DiskFactor), 2)

        # Normalize Robocopy results
        $NormalizedResult.Robocopy.NormalizedElapsedSeconds = [Math]::Round($Result.Robocopy.ElapsedSeconds * $CPUFactor * $DiskFactor, 2)
        $NormalizedResult.Robocopy.NormalizedThroughputMBps = [Math]::Round($Result.Robocopy.ThroughputMBps / ($CPUFactor * $DiskFactor), 2)

        # Calculate normalized differences
        $NormalizedTimeDiff = $NormalizedResult.Robocopy.NormalizedElapsedSeconds - $NormalizedResult.EACopy.NormalizedElapsedSeconds
        $NormalizedTimeDiffPercent = if ($NormalizedResult.Robocopy.NormalizedElapsedSeconds -gt 0) {
            [Math]::Round(($NormalizedTimeDiff / $NormalizedResult.Robocopy.NormalizedElapsedSeconds) * 100, 2)
        } else {
            0
        }

        $NormalizedThroughputDiff = $NormalizedResult.EACopy.NormalizedThroughputMBps - $NormalizedResult.Robocopy.NormalizedThroughputMBps
        $NormalizedThroughputDiffPercent = if ($NormalizedResult.Robocopy.NormalizedThroughputMBps -gt 0) {
            [Math]::Round(($NormalizedThroughputDiff / $NormalizedResult.Robocopy.NormalizedThroughputMBps) * 100, 2)
        } else {
            0
        }

        # Add normalized differences to result
        $NormalizedResult.NormalizedTimeDiff = $NormalizedTimeDiff
        $NormalizedResult.NormalizedTimeDiffPercent = $NormalizedTimeDiffPercent
        $NormalizedResult.NormalizedThroughputDiff = $NormalizedThroughputDiff
        $NormalizedResult.NormalizedThroughputDiffPercent = $NormalizedThroughputDiffPercent

        # Determine which tool is faster based on normalized results
        $NormalizedResult.NormalizedFasterTool = if ($NormalizedResult.EACopy.NormalizedElapsedSeconds -lt $NormalizedResult.Robocopy.NormalizedElapsedSeconds) {
            "EACopy"
        } else {
            "Robocopy"
        }

        # Add to normalized results array
        $NormalizedResults += $NormalizedResult
    }

    # Create a result object with normalization factors
    $ResultObject = [PSCustomObject]@{
        Results = $NormalizedResults
        NormalizationFactors = $NormalizationFactors
    }

    # Add normalization factors to each result for backward compatibility
    foreach ($Result in $NormalizedResults) {
        $Result | Add-Member -NotePropertyName "NormalizationFactors" -NotePropertyValue $NormalizationFactors -Force
    }

    return $ResultObject

    return $ResultObject
}

# Create test directories
$SourceDir = Join-Path $TestDir "source"
$DestDir1 = Join-Path $TestDir "dest_eacopy"
$DestDir2 = Join-Path $TestDir "dest_robocopy"

# Ensure test directories exist
New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null
New-Item -ItemType Directory -Force -Path $DestDir1 | Out-Null
New-Item -ItemType Directory -Force -Path $DestDir2 | Out-Null

# Function to create test files with realistic data patterns
function Create-TestFiles {
    param (
        [string]$Directory,
        [int]$Count,
        [long]$Size,
        [string]$Prefix,
        [switch]$UseRealisticData = $true  # Whether to create files with realistic data patterns
    )

    Write-Host "Creating $Count $Prefix files of size $Size in $Directory..." -ForegroundColor Yellow

    # Create subdirectories to simulate a more realistic file structure
    $SubDirCount = [Math]::Min(10, $Count / 10)
    for ($i = 1; $i -le $SubDirCount; $i++) {
        $SubDir = Join-Path $Directory "subdir_$i"
        New-Item -ItemType Directory -Force -Path $SubDir | Out-Null
    }

    # Create a data pattern generator for realistic files
    function Get-RealisticDataPattern {
        param (
            [int]$PatternIndex,
            [byte[]]$Buffer,
            [int]$BufferSize
        )

        $Random = New-Object Random

        switch ($PatternIndex % 5) {
            0 {
                # Completely random data
                $Random.NextBytes($Buffer)
            }
            1 {
                # Text-like data with spaces and line breaks
                for ($i = 0; $i -lt $BufferSize; $i++) {
                    # ASCII printable characters (32-126) with occasional line breaks
                    if ($i % 80 -eq 0 -and $i -gt 0) {
                        $Buffer[$i] = 10  # Line feed
                    } elseif ($Random.Next(10) -eq 0) {
                        $Buffer[$i] = 32  # Space
                    } else {
                        $Buffer[$i] = [byte]($Random.Next(94) + 33)  # Random printable ASCII
                    }
                }
            }
            2 {
                # Binary data with patterns (simulating executable or compressed data)
                $Pattern = @(0, 0, 0, 0, 255, 255, 255, 255)
                $PatternLength = $Pattern.Length

                for ($i = 0; $i -lt $BufferSize; $i++) {
                    if ($Random.Next(20) -eq 0) {
                        # Occasional random byte
                        $Buffer[$i] = [byte]$Random.Next(256)
                    } else {
                        # Pattern-based byte
                        $Buffer[$i] = [byte]$Pattern[$i % $PatternLength]
                    }
                }
            }
            3 {
                # Repeating data with occasional changes (simulating structured data)
                $BaseValue = [byte]$Random.Next(256)

                for ($i = 0; $i -lt $BufferSize; $i++) {
                    if ($i % 16 -eq 0) {
                        # Change base value every 16 bytes
                        $BaseValue = [byte]$Random.Next(256)
                    }

                    if ($Random.Next(32) -eq 0) {
                        # Occasional random byte
                        $Buffer[$i] = [byte]$Random.Next(256)
                    } else {
                        # Base value with small variation
                        $Variation = $Random.Next(21) - 10  # -10 to +10
                        $Value = $BaseValue + $Variation
                        if ($Value -lt 0) { $Value = 0 }
                        if ($Value -gt 255) { $Value = 255 }
                        $Buffer[$i] = [byte]$Value
                    }
                }
            }
            4 {
                # Gradient pattern (simulating image data)
                $StartValue = [byte]$Random.Next(256)
                $EndValue = [byte]$Random.Next(256)
                $Range = $EndValue - $StartValue

                for ($i = 0; $i -lt $BufferSize; $i++) {
                    $Position = $i / $BufferSize
                    $Value = $StartValue + [int]($Position * $Range)
                    if ($Value -lt 0) { $Value = 0 }
                    if ($Value -gt 255) { $Value = 255 }
                    $Buffer[$i] = [byte]$Value
                }
            }
        }
    }

    for ($i = 1; $i -le $Count; $i++) {
        # Determine if this file should go in a subdirectory
        $TargetDir = $Directory
        if ($i % 10 -eq 0 -and $SubDirCount -gt 0) {
            $SubDirIndex = ($i / 10) % $SubDirCount + 1
            $TargetDir = Join-Path $Directory "subdir_$SubDirIndex"
        }

        $FilePath = Join-Path $TargetDir "$Prefix`_file_$i.dat"

        # Use different data patterns for different files
        $PatternIndex = $i % 5

        # Handle large files by writing in chunks to avoid Int32 overflow
        if ($Size -gt [int]::MaxValue) {
            # Create the file
            $FileStream = [System.IO.File]::Create($FilePath)

            try {
                # Determine chunk size (500MB)
                $ChunkSize = 500MB
                $RemainingSize = $Size

                # Write file in chunks
                while ($RemainingSize -gt 0) {
                    # Calculate current chunk size (using our own Min function to avoid Int32 overflow)
                    $CurrentChunkSize = if ($ChunkSize -lt $RemainingSize) { $ChunkSize } else { $RemainingSize }

                    # Create buffer for this chunk
                    $Buffer = New-Object byte[] $CurrentChunkSize

                    # Fill buffer with appropriate data pattern
                    if ($UseRealisticData) {
                        Get-RealisticDataPattern -PatternIndex $PatternIndex -Buffer $Buffer -BufferSize $CurrentChunkSize
                    } else {
                        (New-Object Random).NextBytes($Buffer)
                    }

                    # Write chunk to file (ensuring parameters are within Int32 range)
                    $FileStream.Write($Buffer, 0, [int]$CurrentChunkSize)

                    # Update remaining size
                    $RemainingSize -= $CurrentChunkSize

                    # Show progress for very large files
                    if ($Size -gt 1GB) {
                        $PercentComplete = [Math]::Round(100 - ($RemainingSize / $Size * 100), 0)
                        Write-Host "  File $i - $PercentComplete% complete..." -NoNewline -ForegroundColor Yellow
                        Write-Host "`r" -NoNewline
                    }
                }

                # Ensure data is written to disk
                $FileStream.Flush($true)
            }
            finally {
                # Close the file stream
                $FileStream.Close()
                $FileStream.Dispose()
            }
        }
        else {
            # For smaller files, create the entire buffer at once
            $Buffer = New-Object byte[] $Size

            # Fill buffer with appropriate data pattern
            if ($UseRealisticData) {
                Get-RealisticDataPattern -PatternIndex $PatternIndex -Buffer $Buffer -BufferSize $Size
            } else {
                (New-Object Random).NextBytes($Buffer)
            }

            # Write to file
            [System.IO.File]::WriteAllBytes($FilePath, $Buffer)
        }

        # Show progress for large files or periodically for many files
        if (($Size -gt 1MB -and $i % 5 -eq 0) -or ($Count -gt 100 -and $i % 50 -eq 0) -or ($i -eq $Count)) {
            Write-Host "  Created $i of $Count files..." -ForegroundColor Yellow
        }
    }

    # Get total size of created files
    $TotalSize = (Get-ChildItem -Path $Directory -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $TotalSizeMB = [Math]::Round($TotalSize / 1MB, 2)

    Write-Host "Created $Count $Prefix files. Total size: $TotalSizeMB MB" -ForegroundColor Green
}

# Function to clear file system cache (requires admin privileges)
function Clear-FileSystemCache {
    Write-Host "Attempting to clear file system cache..." -ForegroundColor Yellow

    # Check if running as administrator
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $IsAdmin) {
        Write-Host "Warning: Not running as administrator. Cannot clear file system cache." -ForegroundColor Yellow
        Write-Host "For more accurate results, run the script as administrator." -ForegroundColor Yellow
        return $false
    }

    try {
        # Method 1: Using SetSystemFileCacheSize API
        $signature = @'
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetSystemFileCacheSize(IntPtr MinimumFileCacheSize, IntPtr MaximumFileCacheSize, uint Flags);
'@

        $type = Add-Type -MemberDefinition $signature -Name "CacheUtil" -Namespace Win32Functions -PassThru
        $result = $type::SetSystemFileCacheSize([IntPtr]::Zero, [IntPtr]::Zero, 0)

        if ($result) {
            Write-Host "Successfully cleared file system cache using SetSystemFileCacheSize." -ForegroundColor Green
            return $true
        }

        # Method 2: Using PowerShell command (Windows 8.1/Server 2012 R2 and later)
        Write-Host "Trying alternative method to clear cache..." -ForegroundColor Yellow

        # Check if Clear-FileSystemCache cmdlet exists (Windows 8.1/Server 2012 R2 and later)
        if (Get-Command -Name Clear-FileSystemCache -ErrorAction SilentlyContinue) {
            Clear-FileSystemCache
            Write-Host "Successfully cleared file system cache using Clear-FileSystemCache cmdlet." -ForegroundColor Green
            return $true
        }

        # Method 3: Using RAMMap (SysInternals) if available
        $RAMMapPath = "C:\Program Files\RAMMap\RAMMap.exe"
        if (Test-Path $RAMMapPath) {
            Write-Host "Using RAMMap to clear cache..." -ForegroundColor Yellow
            Start-Process -FilePath $RAMMapPath -ArgumentList "-Ew" -Wait
            Write-Host "Successfully cleared file system cache using RAMMap." -ForegroundColor Green
            return $true
        }

        # Method 4: Using working set trimming as a fallback
        Write-Host "Using memory working set trimming as fallback..." -ForegroundColor Yellow

        # Get all processes
        $processes = Get-Process

        # Trim working sets
        foreach ($process in $processes) {
            try {
                $process.MinWorkingSet = [IntPtr]::Zero
                $process.MaxWorkingSet = [IntPtr]::Zero
            } catch {
                # Ignore errors for system processes
            }
        }

        Write-Host "Trimmed process working sets as a fallback cache clearing method." -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Host "Error clearing file system cache: $_" -ForegroundColor Red
        return $false
    }
}

# Function to verify copy results
function Verify-CopyResults {
    param (
        [string]$SourcePath,
        [string]$DestPath,
        [int]$MaxFilesToVerify = 10  # Limit the number of files to verify for performance
    )

    Write-Host "Verifying copy results..." -ForegroundColor Yellow

    # Get source files
    $SourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File

    # Get destination files
    $DestFiles = Get-ChildItem -Path $DestPath -Recurse -File

    # Check file count
    if ($SourceFiles.Count -ne $DestFiles.Count) {
        Write-Host "Verification failed: File count mismatch. Source: $($SourceFiles.Count), Destination: $($DestFiles.Count)" -ForegroundColor Red
        return $false
    }

    Write-Host "File count matches: $($SourceFiles.Count) files" -ForegroundColor Green

    # Select a sample of files to verify
    $FilesToVerify = @()

    # Always include first and last file
    $FilesToVerify += $SourceFiles[0]
    if ($SourceFiles.Count -gt 1) {
        $FilesToVerify += $SourceFiles[$SourceFiles.Count - 1]
    }

    # Add some files from the middle if there are more than 2 files
    if ($SourceFiles.Count -gt 2) {
        $Step = [Math]::Max(1, [Math]::Floor($SourceFiles.Count / ($MaxFilesToVerify - 2)))
        for ($i = $Step; $i -lt $SourceFiles.Count - 1; $i += $Step) {
            $FilesToVerify += $SourceFiles[$i]
            if ($FilesToVerify.Count -ge $MaxFilesToVerify) {
                break
            }
        }
    }

    # Verify each selected file
    $VerifiedCount = 0
    $FailedCount = 0

    foreach ($SourceFile in $FilesToVerify) {
        # Get relative path
        $RelativePath = $SourceFile.FullName.Substring($SourcePath.Length).TrimStart('\', '/')
        $DestFile = Join-Path $DestPath $RelativePath

        Write-Host "  Verifying: $RelativePath" -ForegroundColor Yellow -NoNewline

        # Check if destination file exists
        if (-not (Test-Path $DestFile)) {
            Write-Host " - FAILED (File not found)" -ForegroundColor Red
            $FailedCount++
            continue
        }

        # Check file size
        $SourceSize = (Get-Item $SourceFile.FullName).Length
        $DestSize = (Get-Item $DestFile).Length

        if ($SourceSize -ne $DestSize) {
            Write-Host " - FAILED (Size mismatch: Source=$SourceSize, Dest=$DestSize)" -ForegroundColor Red
            $FailedCount++
            continue
        }

        # For small files (< 10MB), verify content with hash
        if ($SourceSize -lt 10MB) {
            $SourceHash = (Get-FileHash -Path $SourceFile.FullName -Algorithm MD5).Hash
            $DestHash = (Get-FileHash -Path $DestFile -Algorithm MD5).Hash

            if ($SourceHash -ne $DestHash) {
                Write-Host " - FAILED (Content mismatch)" -ForegroundColor Red
                $FailedCount++
                continue
            }
        }

        Write-Host " - OK" -ForegroundColor Green
        $VerifiedCount++
    }

    # Report verification results
    Write-Host "Verification complete: $VerifiedCount files verified, $FailedCount failures" -ForegroundColor $(if ($FailedCount -eq 0) { "Green" } else { "Red" })

    return ($FailedCount -eq 0)
}

# Function to measure performance
function Measure-CopyPerformance {
    param (
        [string]$Tool,
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Arguments,
        [switch]$CollectMetrics = $CollectDetailedMetrics,
        [int]$MetricsInterval = $MetricSamplingInterval
    )

    # Clear destination directory
    if (Test-Path $DestPath) {
        Remove-Item -Path $DestPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $DestPath | Out-Null

    # Clear file system cache if requested
    if ($DisableCache) {
        $CacheCleared = Clear-FileSystemCache
        Write-Host "File system cache clearing $(if ($CacheCleared) { 'succeeded' } else { 'failed or skipped' })" -ForegroundColor $(if ($CacheCleared) { "Green" } else { "Yellow" })

        # Force garbage collection to free memory
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        # Small delay to ensure cache clearing takes effect
        Start-Sleep -Seconds 2
    }

    # Prepare command
    $Command = ""
    if ($Tool -eq "EACopy") {
        $Command = "$EACopyPath $SourcePath $DestPath $Arguments"
    } elseif ($Tool -eq "Robocopy") {
        $Command = "robocopy $SourcePath $DestPath /E $Arguments"
    }

    Write-Host "Running: $Command" -ForegroundColor Cyan

    # Start performance monitoring if requested
    $MonitoringJob = $null
    if ($CollectMetrics) {
        $MonitoringJob = Start-PerformanceMonitoring -SamplingInterval $MetricsInterval
    }

    # Measure performance
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    $ToolOutput = $null

    if ($Tool -eq "EACopy") {
        # Use Start-Process to avoid output buffer issues
        $ProcessInfo = Start-Process -FilePath $EACopyPath -ArgumentList "$SourcePath $DestPath $Arguments" -NoNewWindow -PassThru -Wait
        $ExitCode = $ProcessInfo.ExitCode
    } elseif ($Tool -eq "Robocopy") {
        # For Robocopy, capture the output to parse performance data
        $TempOutputFile = [System.IO.Path]::GetTempFileName()

        # Run Robocopy and capture its output
        $ProcessInfo = Start-Process -FilePath "robocopy" -ArgumentList "$SourcePath $DestPath /E $Arguments" -NoNewWindow -PassThru -Wait -RedirectStandardOutput $TempOutputFile

        # Robocopy exit codes are different - 0-7 are success with various levels of copying activity
        $ExitCode = if ($ProcessInfo.ExitCode -le 7) { 0 } else { $ProcessInfo.ExitCode }

        # Read the output
        $ToolOutput = Get-Content -Path $TempOutputFile -Raw

        # Clean up
        Remove-Item -Path $TempOutputFile -Force -ErrorAction SilentlyContinue
    }

    $StopWatch.Stop()
    $ElapsedTime = $StopWatch.Elapsed

    # Stop performance monitoring if it was started
    $PerformanceMetrics = $null
    if ($MonitoringJob) {
        $PerformanceMetrics = Stop-PerformanceMonitoring -MonitoringJob $MonitoringJob
    }

    # Force sync to ensure all data is written to disk
    Write-Host "Forcing disk sync..." -ForegroundColor Yellow
    $SyncProcess = Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo Syncing disk cache && echo 3 > NUL" -NoNewWindow -PassThru -Wait

    # Verify copy results if requested
    $VerificationResult = $true
    if ($VerifyCopy) {
        $VerificationResult = Verify-CopyResults -SourcePath $SourcePath -DestPath $DestPath
    }

    # Get total size copied
    $Size = (Get-ChildItem -Path $SourcePath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $SizeMB = [Math]::Round($Size / 1MB, 2)

    # Calculate throughput
    $ThroughputMBps = if ($ElapsedTime.TotalSeconds -gt 0) { [Math]::Round($SizeMB / $ElapsedTime.TotalSeconds, 2) } else { 0 }

    # Parse Robocopy output for its reported performance data
    $RobocopyReportedSpeed = $null
    $RobocopyReportedTime = $null

    if ($Tool -eq "Robocopy" -and $ToolOutput) {
        Write-Host "Parsing Robocopy output for performance data..." -ForegroundColor Yellow

        # Extract speed information
        $SpeedMatch = $ToolOutput | Select-String -Pattern "速度:\s+([0-9,]+)\s+字节/秒" -AllMatches
        if (-not $SpeedMatch) {
            # Try English version
            $SpeedMatch = $ToolOutput | Select-String -Pattern "Speed:\s+([0-9,]+)\s+Bytes/sec" -AllMatches
        }

        if ($SpeedMatch -and $SpeedMatch.Matches.Count -gt 0) {
            $SpeedText = $SpeedMatch.Matches[0].Groups[1].Value
            $SpeedText = $SpeedText -replace ",", ""  # Remove commas
            $SpeedBytesPerSec = [double]$SpeedText
            $SpeedMBps = [Math]::Round($SpeedBytesPerSec / 1MB, 2)
            $RobocopyReportedSpeed = $SpeedMBps
            Write-Host "  Robocopy reported speed: $SpeedMBps MB/s" -ForegroundColor Yellow
        }

        # Extract time information
        $TimeMatch = $ToolOutput | Select-String -Pattern "时间:\s+(\d+):(\d+):(\d+)" -AllMatches
        if (-not $TimeMatch) {
            # Try English version
            $TimeMatch = $ToolOutput | Select-String -Pattern "Times:\s+(\d+):(\d+):(\d+)" -AllMatches
        }

        if ($TimeMatch -and $TimeMatch.Matches.Count -gt 0) {
            $Hours = [int]$TimeMatch.Matches[0].Groups[1].Value
            $Minutes = [int]$TimeMatch.Matches[0].Groups[2].Value
            $Seconds = [int]$TimeMatch.Matches[0].Groups[3].Value
            $TotalSeconds = $Hours * 3600 + $Minutes * 60 + $Seconds
            $RobocopyReportedTime = $TotalSeconds
            Write-Host "  Robocopy reported time: $TotalSeconds seconds" -ForegroundColor Yellow
        }
    }

    # Return result
    $Result = @{
        Tool = $Tool
        ElapsedTime = $ElapsedTime
        ElapsedSeconds = [Math]::Round($ElapsedTime.TotalSeconds, 2)
        SizeMB = $SizeMB
        ThroughputMBps = $ThroughputMBps
        ExitCode = $ExitCode
        VerificationPassed = $VerificationResult
        FileCount = (Get-ChildItem -Path $SourcePath -Recurse -File).Count
    }

    # Add Robocopy's reported performance data if available
    if ($Tool -eq "Robocopy") {
        $Result.ToolOutput = $ToolOutput

        if ($RobocopyReportedSpeed) {
            $Result.ReportedThroughputMBps = $RobocopyReportedSpeed
        }

        if ($RobocopyReportedTime) {
            $Result.ReportedElapsedSeconds = $RobocopyReportedTime
        }
    }

    # Add performance metrics if collected
    if ($PerformanceMetrics) {
        $Result.PerformanceMetrics = $PerformanceMetrics.Summary
        $Result.DetailedMetrics = $PerformanceMetrics.DetailedMetrics
    }

    return $Result
}

# Function to run a test scenario
function Run-TestScenario {
    param (
        [string]$ScenarioName,
        [string]$SourcePath,
        [string]$FilePattern = "*",
        [string]$EACopyArgs = "",
        [string]$RobocopyArgs = ""
    )

    Write-Host "`n========== Running Test Scenario: $ScenarioName ==========" -ForegroundColor Cyan

    # Handle special scenarios by creating a temporary source directory for file filtering
    $UseTemporarySource = $false
    $TemporarySourceDir = $null

    # Check if file filtering is needed (for scenarios like "Small Files Only")
    if ($FilePattern -ne "*") {
        $UseTemporarySource = $true
        $TemporarySourceDir = Join-Path $TestDir "temp_source_$([Guid]::NewGuid().ToString())"
        New-Item -ItemType Directory -Force -Path $TemporarySourceDir | Out-Null

        Write-Host "Creating temporary source directory for filtered files: $TemporarySourceDir" -ForegroundColor Yellow

        # Copy matching files to the temporary directory
        $MatchingFiles = Get-ChildItem -Path $SourcePath -Recurse -File | Where-Object { $_.Name -like $FilePattern }
        $FileCount = 0

        foreach ($File in $MatchingFiles) {
            # Maintain relative path structure
            $RelativePath = $File.FullName.Substring($SourcePath.Length).TrimStart('\', '/')
            $DestinationPath = Join-Path $TemporarySourceDir $RelativePath
            $DestinationDir = Split-Path -Parent $DestinationPath

            if (-not (Test-Path $DestinationDir)) {
                New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
            }

            Copy-Item -Path $File.FullName -Destination $DestinationPath -Force
            $FileCount++
        }

        Write-Host "Copied $FileCount files matching pattern '$FilePattern' to temporary directory" -ForegroundColor Yellow

        # Update source path to use the temporary directory
        $EffectiveSourcePath = $TemporarySourceDir
    } else {
        $EffectiveSourcePath = $SourcePath
    }

    try {
        # Run EACopy
        $EACopyResult = Measure-CopyPerformance -Tool "EACopy" -SourcePath $EffectiveSourcePath -DestPath $DestDir1 -Arguments $EACopyArgs

        # Run Robocopy
        $RobocopyResult = Measure-CopyPerformance -Tool "Robocopy" -SourcePath $EffectiveSourcePath -DestPath $DestDir2 -Arguments $RobocopyArgs
    }
    finally {
        # Clean up temporary directory
        if ($UseTemporarySource -and (Test-Path $TemporarySourceDir)) {
            Write-Host "Cleaning up temporary source directory" -ForegroundColor Yellow
            Remove-Item -Path $TemporarySourceDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

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

    # Format results with consistent decimal places
    $EACopyTimeFormatted = [Math]::Round($EACopyResult.ElapsedSeconds, 2).ToString("0.00")
    $EACopyThroughputFormatted = [Math]::Round($EACopyResult.ThroughputMBps, 2).ToString("0.00")
    $RobocopyTimeFormatted = [Math]::Round($RobocopyResult.ElapsedSeconds, 2).ToString("0.00")
    $RobocopyThroughputFormatted = [Math]::Round($RobocopyResult.ThroughputMBps, 2).ToString("0.00")
    $TimeDiffFormatted = [Math]::Round($TimeDiff, 2).ToString("0.00")
    $TimeDiffPercentFormatted = [Math]::Round($TimeDiffPercent, 2).ToString("0.00")
    $ThroughputDiffFormatted = [Math]::Round($ThroughputDiff, 2).ToString("0.00")
    $ThroughputDiffPercentFormatted = [Math]::Round($ThroughputDiffPercent, 2).ToString("0.00")

    # Print results
    Write-Host "`nResults for ${ScenarioName}:" -ForegroundColor Green
    Write-Host "EACopy: ${EACopyTimeFormatted} seconds, ${EACopyThroughputFormatted} MB/s"

    # For Robocopy, show both our measured performance and Robocopy's reported performance
    if ($RobocopyResult.ContainsKey("ReportedThroughputMBps")) {
        $ReportedThroughputFormatted = [Math]::Round($RobocopyResult.ReportedThroughputMBps, 2).ToString("0.00")
        Write-Host "Robocopy (measured): ${RobocopyTimeFormatted} seconds, ${RobocopyThroughputFormatted} MB/s"
        Write-Host "Robocopy (reported): $(if ($RobocopyResult.ReportedElapsedSeconds) { $RobocopyResult.ReportedElapsedSeconds } else { "N/A" }) seconds, ${ReportedThroughputFormatted} MB/s"
    } else {
        Write-Host "Robocopy: ${RobocopyTimeFormatted} seconds, ${RobocopyThroughputFormatted} MB/s"
    }

    Write-Host "Difference: ${TimeDiffFormatted} seconds (${TimeDiffPercentFormatted}%), ${ThroughputDiffFormatted} MB/s (${ThroughputDiffPercentFormatted}%)"
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
    Write-Host "Script version: 1.1 (Enhanced CI Compatibility)" -ForegroundColor Yellow
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    Write-Host "Script directory: $PSScriptRoot" -ForegroundColor Yellow

    # Create a debug log file for CI troubleshooting
    $DebugLogPath = Join-Path $TestDir "debug_log.txt"
    "Performance Test Debug Log - $(Get-Date)" | Out-File -FilePath $DebugLogPath -Encoding utf8
    "Current directory: $(Get-Location)" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "Script directory: $PSScriptRoot" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "EACopy path: $EACopyPath" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "Test directory: $TestDir" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append

    # Collect system information
    Write-Host "Collecting system information..." -ForegroundColor Yellow
    try {
        $SystemInfo = Get-SystemInfo
        "System information collected successfully" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    }
    catch {
        Write-Host "Error collecting system information: $_" -ForegroundColor Red
        "Error collecting system information: $_" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
        # Create a minimal system info object to allow the script to continue
        $SystemInfo = @{
            CPU = @{
                Model = "Unknown (CI Environment)"
                Cores = 0
                LogicalProcessors = 0
                MaxClockSpeedMHz = 0
            }
            Memory = @{
                TotalGB = 0
            }
            OS = @{
                Version = "Unknown"
                Build = "Unknown"
            }
            Disk = @{
                Type = "Unknown"
                SizeGB = 0
                FreeGB = 0
                ReadSpeedMBps = 0
                WriteSpeedMBps = 0
            }
        }
    }

    # Display system information summary
    Write-Host "`nSystem Information:" -ForegroundColor Cyan
    Write-Host "CPU: $($SystemInfo.CPU.Model) ($($SystemInfo.CPU.Cores) cores, $($SystemInfo.CPU.LogicalProcessors) logical processors)"
    Write-Host "Memory: $($SystemInfo.Memory.TotalGB) GB"
    Write-Host "OS: $($SystemInfo.OS.Version) (Build $($SystemInfo.OS.Build))"
    Write-Host "Disk: $($SystemInfo.Disk.Type), $($SystemInfo.Disk.SizeGB) GB total, $($SystemInfo.Disk.FreeGB) GB free"
    Write-Host "Disk Performance: Read $($SystemInfo.Disk.ReadSpeedMBps) MB/s, Write $($SystemInfo.Disk.WriteSpeedMBps) MB/s"

    # Log system information
    "CPU: $($SystemInfo.CPU.Model) ($($SystemInfo.CPU.Cores) cores, $($SystemInfo.CPU.LogicalProcessors) logical processors)" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "Memory: $($SystemInfo.Memory.TotalGB) GB" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "OS: $($SystemInfo.OS.Version) (Build $($SystemInfo.OS.Build))" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "Disk: $($SystemInfo.Disk.Type), $($SystemInfo.Disk.SizeGB) GB total, $($SystemInfo.Disk.FreeGB) GB free" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append
    "Disk Performance: Read $($SystemInfo.Disk.ReadSpeedMBps) MB/s, Write $($SystemInfo.Disk.WriteSpeedMBps) MB/s" | Out-File -FilePath $DebugLogPath -Encoding utf8 -Append

    # Auto-detect EACopy.exe if path not provided
    if (-not $EACopyPath) {
        $PossiblePaths = @(
            # Correct paths based on user feedback
            ".\build\Release\EACopy.exe",
            ".\build\Debug\EACopy.exe",
            "..\build\Release\EACopy.exe",
            "..\build\Debug\EACopy.exe",
            "$PSScriptRoot\..\build\Release\EACopy.exe",
            "$PSScriptRoot\..\build\Debug\EACopy.exe",

            # Local development paths
            ".\Release\EACopy.exe",
            ".\Debug\EACopy.exe",
            "..\Release\EACopy.exe",
            "..\Debug\EACopy.exe",
            ".\build_Release\Release\EACopy.exe",
            ".\build_Debug\Debug\EACopy.exe",
            "..\build_Release\Release\EACopy.exe",
            "..\build_Debug\Debug\EACopy.exe",

            # CI environment paths
            "$PSScriptRoot\..\Release\EACopy.exe",
            "$PSScriptRoot\..\Debug\EACopy.exe",
            "$PSScriptRoot\..\build_Release\Release\EACopy.exe",
            "$PSScriptRoot\..\build_Debug\Debug\EACopy.exe",

            # Additional CI paths
            ".\EACopy-Release\EACopy.exe",
            ".\Release\EACopy.exe",
            ".\Debug\EACopy.exe"
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
        # Print current directory and environment info for debugging
        Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
        Write-Host "Script directory: $PSScriptRoot" -ForegroundColor Yellow
        Write-Host "Directory contents:" -ForegroundColor Yellow
        Get-ChildItem -Path "." -Recurse -Depth 2 -Include "*.exe" | ForEach-Object { Write-Host "  - $($_.FullName)" }

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
    $Results += Run-TestScenario -ScenarioName "Small Files Only" -SourcePath $SourceDir -FilePattern "small*"
    $Results += Run-TestScenario -ScenarioName "Medium Files Only" -SourcePath $SourceDir -FilePattern "medium*"
    $Results += Run-TestScenario -ScenarioName "Large Files Only" -SourcePath $SourceDir -FilePattern "large*"

    # Normalize results based on hardware capabilities
    $NormalizedResults = Normalize-PerformanceResults -Results $Results -SystemInfo $SystemInfo

    # Generate summary
    Write-Host "`n========== Performance Test Summary ==========" -ForegroundColor Yellow

    # Display system information
    Write-Host "`nSystem Information:" -ForegroundColor Cyan
    Write-Host "CPU: $($SystemInfo.CPU.Model) ($($SystemInfo.CPU.Cores) cores, $($SystemInfo.CPU.LogicalProcessors) logical processors)"
    Write-Host "Memory: $($SystemInfo.Memory.TotalGB) GB"
    Write-Host "OS: $($SystemInfo.OS.Version) (Build $($SystemInfo.OS.Build))"
    Write-Host "Disk: $($SystemInfo.Disk.Type), $($SystemInfo.Disk.SizeGB) GB total, $($SystemInfo.Disk.FreeGB) GB free"
    Write-Host "Disk Performance: Read $($SystemInfo.Disk.ReadSpeedMBps) MB/s, Write $($SystemInfo.Disk.WriteSpeedMBps) MB/s"

    # Display test configuration
    Write-Host "`nTest Configuration:" -ForegroundColor Cyan
    Write-Host "Small Files: $SmallFileCount files of $([Math]::Round($SmallFileSize/1KB, 2)) KB each"
    Write-Host "Medium Files: $MediumFileCount files of $([Math]::Round($MediumFileSize/1MB, 2)) MB each"
    Write-Host "Large Files: $LargeFileCount files of $([Math]::Round($LargeFileSize/1MB, 2)) MB each"

    # Display results table
    Write-Host "`nResults:" -ForegroundColor Cyan
    Write-Host "| Scenario | EACopy | Robocopy | Difference | Faster Tool |"
    Write-Host "|----------|--------|----------|------------|-------------|"

    foreach ($Result in $Results) {
        $ScenarioName = $Result.ScenarioName

        # Format time with 2 decimal places
        $EACopyTimeFormatted = [Math]::Round($Result.EACopy.ElapsedSeconds, 2).ToString("0.00")
        $RobocopyTimeFormatted = [Math]::Round($Result.Robocopy.ElapsedSeconds, 2).ToString("0.00")

        # Format throughput with 2 decimal places
        $EACopyThroughputFormatted = [Math]::Round($Result.EACopy.ThroughputMBps, 2).ToString("0.00")
        $RobocopyThroughputFormatted = [Math]::Round($Result.Robocopy.ThroughputMBps, 2).ToString("0.00")

        # Format time difference with 2 decimal places
        $TimeDiffFormatted = [Math]::Round($Result.TimeDiff, 2).ToString("0.00")
        $TimeDiffPercentFormatted = [Math]::Round($Result.TimeDiffPercent, 2).ToString("0.00")

        # Format throughput difference with 2 decimal places
        $ThroughputDiffFormatted = [Math]::Round($Result.ThroughputDiff, 2).ToString("0.00")
        $ThroughputDiffPercentFormatted = [Math]::Round($Result.ThroughputDiffPercent, 2).ToString("0.00")

        $EACopyTime = "${EACopyTimeFormatted}s (${EACopyThroughputFormatted} MB/s)"
        $RobocopyTime = "${RobocopyTimeFormatted}s (${RobocopyThroughputFormatted} MB/s)"
        $Difference = "${TimeDiffFormatted}s (${TimeDiffPercentFormatted}%), ${ThroughputDiffFormatted} MB/s (${ThroughputDiffPercentFormatted}%)"
        $FasterTool = $Result.FasterTool

        Write-Host "| $ScenarioName | $EACopyTime | $RobocopyTime | $Difference | $FasterTool |"
    }

    # Generate JSON output for CI
    $JsonOutput = @{
        TestDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SystemInfo = $SystemInfo
        TestResults = $Results
        NormalizedResults = $NormalizedResults
        TestConfiguration = @{
            SmallFiles = @{
                Count = $SmallFileCount
                Size = $SmallFileSize
            }
            MediumFiles = @{
                Count = $MediumFileCount
                Size = $MediumFileSize
            }
            LargeFiles = @{
                Count = $LargeFileCount
                Size = $LargeFileSize
            }
            CollectDetailedMetrics = $CollectDetailedMetrics
            MetricSamplingInterval = $MetricSamplingInterval
        }
    } | ConvertTo-Json -Depth 10

    $JsonOutputPath = Join-Path $TestDir "performance_results.json"
    $JsonOutput | Out-File -FilePath $JsonOutputPath -Encoding utf8

    Write-Host "`nPerformance test results saved to: $JsonOutputPath" -ForegroundColor Green

    # Save to history directory if specified
    if ($HistoryDir) {
        # Create history directory if it doesn't exist
        if (-not (Test-Path $HistoryDir)) {
            try {
                Write-Host "Creating history directory: $HistoryDir" -ForegroundColor Yellow
                New-Item -ItemType Directory -Path $HistoryDir -Force -ErrorAction Stop | Out-Null
                Write-Host "Successfully created history directory" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Failed to create history directory: $_" -ForegroundColor Red
                # Create a fallback directory in the current location
                $HistoryDir = "./history_fallback"
                if (-not (Test-Path $HistoryDir)) {
                    try {
                        New-Item -ItemType Directory -Path $HistoryDir -Force | Out-Null
                        Write-Host "Created fallback history directory: $HistoryDir" -ForegroundColor Yellow
                    } catch {
                        Write-Host "Critical: Failed to create fallback history directory: $_" -ForegroundColor Red
                        # If we can't create any directory, just use the current directory
                        $HistoryDir = "."
                        Write-Host "Using current directory for history" -ForegroundColor Yellow
                    }
                }
            }
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

### System Information
- **CPU**: $($SystemInfo.CPU.Model) ($($SystemInfo.CPU.Cores) cores, $($SystemInfo.CPU.LogicalProcessors) logical processors)
- **Memory**: $($SystemInfo.Memory.TotalGB) GB
- **OS**: $($SystemInfo.OS.Version) (Build $($SystemInfo.OS.Build))
- **Disk**: $($SystemInfo.Disk.Type), $($SystemInfo.Disk.SizeGB) GB total, $($SystemInfo.Disk.FreeGB) GB free
- **Disk Performance**: Read $($SystemInfo.Disk.ReadSpeedMBps) MB/s, Write $($SystemInfo.Disk.WriteSpeedMBps) MB/s

### Test Configuration
- **Small Files**: $SmallFileCount files of $([Math]::Round($SmallFileSize/1KB, 2)) KB each
- **Medium Files**: $MediumFileCount files of $([Math]::Round($MediumFileSize/1MB, 2)) MB each
- **Large Files**: $LargeFileCount files of $([Math]::Round($LargeFileSize/1MB, 2)) MB each
- **File System Cache**: $(if ($DisableCache) { "Disabled" } else { "Enabled" })
- **Copy Verification**: $(if ($VerifyCopy) { "Enabled" } else { "Disabled" })

### Performance Results
| Scenario | EACopy | Robocopy (Measured) | Robocopy (Reported) | Difference | Faster Tool |
|----------|--------|---------------------|---------------------|------------|-------------|
"@

    foreach ($Result in $Results) {
        $ScenarioName = $Result.ScenarioName

        # Format time with 2 decimal places
        $EACopyTimeFormatted = [Math]::Round($Result.EACopy.ElapsedSeconds, 2).ToString("0.00")
        $RobocopyTimeFormatted = [Math]::Round($Result.Robocopy.ElapsedSeconds, 2).ToString("0.00")

        # Format throughput with 2 decimal places
        $EACopyThroughputFormatted = [Math]::Round($Result.EACopy.ThroughputMBps, 2).ToString("0.00")
        $RobocopyThroughputFormatted = [Math]::Round($Result.Robocopy.ThroughputMBps, 2).ToString("0.00")

        # Format time difference with 2 decimal places
        $TimeDiffFormatted = [Math]::Round($Result.TimeDiff, 2).ToString("0.00")
        $TimeDiffPercentFormatted = [Math]::Round($Result.TimeDiffPercent, 2).ToString("0.00")

        # Format throughput difference with 2 decimal places
        $ThroughputDiffFormatted = [Math]::Round($Result.ThroughputDiff, 2).ToString("0.00")
        $ThroughputDiffPercentFormatted = [Math]::Round($Result.ThroughputDiffPercent, 2).ToString("0.00")

        $EACopyTime = "${EACopyTimeFormatted}s (${EACopyThroughputFormatted} MB/s)"
        $RobocopyMeasuredTime = "${RobocopyTimeFormatted}s (${RobocopyThroughputFormatted} MB/s)"

        # Add Robocopy's reported performance if available
        $RobocopyReportedTime = "N/A"
        if ($Result.Robocopy.ContainsKey("ReportedThroughputMBps")) {
            $ReportedThroughputFormatted = [Math]::Round($Result.Robocopy.ReportedThroughputMBps, 2).ToString("0.00")
            $ReportedTimeFormatted = if ($Result.Robocopy.ReportedElapsedSeconds) {
                $Result.Robocopy.ReportedElapsedSeconds.ToString("0.00")
            } else {
                "N/A"
            }
            $RobocopyReportedTime = "${ReportedTimeFormatted}s (${ReportedThroughputFormatted} MB/s)"
        }

        $Difference = "${TimeDiffFormatted}s (${TimeDiffPercentFormatted}%), ${ThroughputDiffFormatted} MB/s (${ThroughputDiffPercentFormatted}%)"
        $FasterTool = $Result.FasterTool

        $MarkdownReport += "`n| $ScenarioName | $EACopyTime | $RobocopyMeasuredTime | $RobocopyReportedTime | $Difference | $FasterTool |"
    }

    # Add normalized results if available
    if ($NormalizedResults) {
        $MarkdownReport += @"

### Normalized Performance Results
*Normalized to a reference system with 4 cores @ 3.0 GHz and 500 MB/s disk read speed*

| Scenario | EACopy | Robocopy (Measured) | Robocopy (Reported) | Difference | Faster Tool |
|----------|--------|---------------------|---------------------|------------|-------------|
"@

        foreach ($Result in $NormalizedResults.Results) {
            $ScenarioName = $Result.ScenarioName

            # Format time with 2 decimal places
            $EACopyTimeFormatted = [Math]::Round($Result.EACopy.NormalizedElapsedSeconds, 2).ToString("0.00")
            $RobocopyTimeFormatted = [Math]::Round($Result.Robocopy.NormalizedElapsedSeconds, 2).ToString("0.00")

            # Format throughput with 2 decimal places
            $EACopyThroughputFormatted = [Math]::Round($Result.EACopy.NormalizedThroughputMBps, 2).ToString("0.00")
            $RobocopyThroughputFormatted = [Math]::Round($Result.Robocopy.NormalizedThroughputMBps, 2).ToString("0.00")

            # Format time difference with 2 decimal places
            $TimeDiffFormatted = [Math]::Round($Result.NormalizedTimeDiff, 2).ToString("0.00")
            $TimeDiffPercentFormatted = [Math]::Round($Result.NormalizedTimeDiffPercent, 2).ToString("0.00")

            # Format throughput difference with 2 decimal places
            $ThroughputDiffFormatted = [Math]::Round($Result.NormalizedThroughputDiff, 2).ToString("0.00")
            $ThroughputDiffPercentFormatted = [Math]::Round($Result.NormalizedThroughputDiffPercent, 2).ToString("0.00")

            $EACopyTime = "${EACopyTimeFormatted}s (${EACopyThroughputFormatted} MB/s)"
            $RobocopyMeasuredTime = "${RobocopyTimeFormatted}s (${RobocopyThroughputFormatted} MB/s)"

            # Add Robocopy's reported performance if available (not normalized)
            $RobocopyReportedTime = "N/A"
            if ($Result.Robocopy.ContainsKey("ReportedThroughputMBps")) {
                $ReportedThroughputFormatted = [Math]::Round($Result.Robocopy.ReportedThroughputMBps, 2).ToString("0.00")
                $ReportedTimeFormatted = if ($Result.Robocopy.ReportedElapsedSeconds) {
                    $Result.Robocopy.ReportedElapsedSeconds.ToString("0.00")
                } else {
                    "N/A"
                }
                $RobocopyReportedTime = "${ReportedTimeFormatted}s (${ReportedThroughputFormatted} MB/s)*"
            }

            $Difference = "${TimeDiffFormatted}s (${TimeDiffPercentFormatted}%), ${ThroughputDiffFormatted} MB/s (${ThroughputDiffPercentFormatted}%)"
            $FasterTool = $Result.NormalizedFasterTool

            $MarkdownReport += "`n| $ScenarioName | $EACopyTime | $RobocopyMeasuredTime | $RobocopyReportedTime | $Difference | $FasterTool |"
        }

        # Add normalization factors
        $MarkdownReport += @"

**Normalization Factors**:
- CPU Factor: $([Math]::Round($NormalizedResults.NormalizationFactors.CPU, 4).ToString("0.0000"))
- Disk Factor: $([Math]::Round($NormalizedResults.NormalizationFactors.Disk, 4).ToString("0.0000"))
- Combined Factor: $([Math]::Round($NormalizedResults.NormalizationFactors.Combined, 4).ToString("0.0000"))
"@
    }

    # Add system performance metrics if available
    if ($CollectDetailedMetrics) {
        $MarkdownReport += @"

### System Performance During Tests
| Scenario | CPU Avg | CPU Max | Memory Avg | Memory Max | Disk Read | Disk Write |
|----------|---------|---------|------------|------------|-----------|------------|
"@

        foreach ($Result in $Results) {
            $ScenarioName = $Result.ScenarioName

            if ($Result.EACopy.PerformanceMetrics) {
                $CPUAvg = "$($Result.EACopy.PerformanceMetrics.CPU.AverageUsagePercent)%"
                $CPUMax = "$($Result.EACopy.PerformanceMetrics.CPU.MaxUsagePercent)%"
                $MemoryAvg = "$($Result.EACopy.PerformanceMetrics.Memory.AverageUsagePercent)%"
                $MemoryMax = "$($Result.EACopy.PerformanceMetrics.Memory.MaxUsagePercent)%"
                $DiskRead = "$($Result.EACopy.PerformanceMetrics.Disk.AverageReadMBps) MB/s"
                $DiskWrite = "$($Result.EACopy.PerformanceMetrics.Disk.AverageWriteMBps) MB/s"

                $MarkdownReport += "`n| $ScenarioName (EACopy) | $CPUAvg | $CPUMax | $MemoryAvg | $MemoryMax | $DiskRead | $DiskWrite |"
            }

            if ($Result.Robocopy.PerformanceMetrics) {
                $CPUAvg = "$($Result.Robocopy.PerformanceMetrics.CPU.AverageUsagePercent)%"
                $CPUMax = "$($Result.Robocopy.PerformanceMetrics.CPU.MaxUsagePercent)%"
                $MemoryAvg = "$($Result.Robocopy.PerformanceMetrics.Memory.AverageUsagePercent)%"
                $MemoryMax = "$($Result.Robocopy.PerformanceMetrics.Memory.MaxUsagePercent)%"
                $DiskRead = "$($Result.Robocopy.PerformanceMetrics.Disk.AverageReadMBps) MB/s"
                $DiskWrite = "$($Result.Robocopy.PerformanceMetrics.Disk.AverageWriteMBps) MB/s"

                $MarkdownReport += "`n| $ScenarioName (Robocopy) | $CPUAvg | $CPUMax | $MemoryAvg | $MemoryMax | $DiskRead | $DiskWrite |"
            }
        }
    }

    $MarkdownReport += @"

### Test Configuration
- Small Files: $SmallFileCount files of $([Math]::Round($SmallFileSize/1KB, 2)) KB each (Total: $([Math]::Round($SmallFileCount * $SmallFileSize/1MB, 2)) MB)
- Medium Files: $MediumFileCount files of $([Math]::Round($MediumFileSize/1MB, 2)) MB each (Total: $([Math]::Round($MediumFileCount * $MediumFileSize/1MB, 2)) MB)
- Large Files: $LargeFileCount files of $([Math]::Round($LargeFileSize/1MB, 2)) MB each (Total: $([Math]::Round($LargeFileCount * $LargeFileSize/1MB, 2)) MB)
- Total Files: $($SmallFileCount + $MediumFileCount + $LargeFileCount)
- Total Data: $([Math]::Round(($SmallFileCount * $SmallFileSize + $MediumFileCount * $MediumFileSize + $LargeFileCount * $LargeFileSize)/1MB, 2)) MB
- Detailed Metrics Collection: $(if ($CollectDetailedMetrics) { "Enabled" } else { "Disabled" })
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
