# Script to generate performance trend visualizations from historical test data
param (
    [string]$HistoryDir = ".\performance_history",
    [string]$OutputDir = ".\performance_trends",
    [int]$MaxHistoryEntries = 10  # Number of historical entries to include in trends
)

# Ensure required modules are available
function Ensure-Module {
    param (
        [string]$ModuleName,
        [string]$MinimumVersion = "1.0"
    )
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Installing $ModuleName module..."
        Install-Module -Name $ModuleName -Force -Scope CurrentUser -MinimumVersion $MinimumVersion
    }
    
    Import-Module $ModuleName -MinimumVersion $MinimumVersion
}

# Create directories if they don't exist
if (-not (Test-Path $HistoryDir)) {
    New-Item -ItemType Directory -Force -Path $HistoryDir | Out-Null
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

# Get all historical performance data files
$HistoryFiles = Get-ChildItem -Path $HistoryDir -Filter "performance_*.json" | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -First $MaxHistoryEntries

if ($HistoryFiles.Count -eq 0) {
    Write-Host "No historical performance data found in $HistoryDir"
    exit 0
}

# Load historical data
$HistoryData = @()
foreach ($File in $HistoryFiles) {
    try {
        $Data = Get-Content -Path $File.FullName -Raw | ConvertFrom-Json
        $Data | Add-Member -NotePropertyName "FileName" -NotePropertyValue $File.Name
        $HistoryData += $Data
    } catch {
        Write-Warning "Failed to parse $($File.Name): $_"
    }
}

# Sort by test date
$HistoryData = $HistoryData | Sort-Object TestDate

# Extract commit info from filenames (format: performance_YYYYMMDD_HHMMSS_COMMIT.json)
foreach ($Entry in $HistoryData) {
    if ($Entry.FileName -match "performance_\d{8}_\d{6}_([a-f0-9]+)\.json") {
        $Entry | Add-Member -NotePropertyName "CommitId" -NotePropertyValue $Matches[1]
    } else {
        $Entry | Add-Member -NotePropertyName "CommitId" -NotePropertyValue "unknown"
    }
}

# Generate HTML report with charts
$HtmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>EACopy Performance Trends</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { width: 800px; height: 400px; margin-bottom: 30px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
    </style>
</head>
<body>
    <h1>EACopy Performance Trends</h1>
    <p>Last updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    
    <h2>Execution Time Comparison (seconds)</h2>
    <div class="chart-container">
        <canvas id="timeChart"></canvas>
    </div>
    
    <h2>Throughput Comparison (MB/s)</h2>
    <div class="chart-container">
        <canvas id="throughputChart"></canvas>
    </div>
    
    <h2>Performance Improvement Over Robocopy (%)</h2>
    <div class="chart-container">
        <canvas id="improvementChart"></canvas>
    </div>
    
    <h2>Latest Test Results</h2>
    <table id="latestResults">
        <tr>
            <th>Scenario</th>
            <th>EACopy Time (s)</th>
            <th>EACopy Throughput (MB/s)</th>
            <th>Robocopy Time (s)</th>
            <th>Robocopy Throughput (MB/s)</th>
            <th>Difference (%)</th>
            <th>Faster Tool</th>
        </tr>
    </table>
    
    <h2>Historical Data</h2>
    <table id="historyTable">
        <tr>
            <th>Date</th>
            <th>Commit</th>
            <th>All Files Improvement (%)</th>
            <th>Small Files Improvement (%)</th>
            <th>Medium Files Improvement (%)</th>
            <th>Large Files Improvement (%)</th>
        </tr>
    </table>

    <script>
        // Data from PowerShell
        const historyData = [
"@

# Add JSON data for each history entry
foreach ($Entry in $HistoryData) {
    $JsonEntry = $Entry | ConvertTo-Json -Compress
    $HtmlReport += "            $JsonEntry,`n"
}

$HtmlReport += @"
        ];
        
        // Prepare data for charts
        const dates = historyData.map(entry => new Date(entry.TestDate).toLocaleDateString());
        const commits = historyData.map(entry => entry.CommitId.substring(0, 7));
        const labels = dates.map((date, i) => `${date} (${commits[i]})`);
        
        // Extract scenario data
        const scenarios = ['All Files', 'Small Files Only', 'Medium Files Only', 'Large Files Only'];
        const datasets = {
            eacopyTime: [],
            robocopyTime: [],
            eacopyThroughput: [],
            robocopyThroughput: [],
            improvement: []
        };
        
        // Create datasets for each scenario
        scenarios.forEach((scenario, scenarioIndex) => {
            const eacopyTimeData = [];
            const robocopyTimeData = [];
            const eacopyThroughputData = [];
            const robocopyThroughputData = [];
            const improvementData = [];
            
            historyData.forEach(entry => {
                const result = entry.TestResults.find(r => r.ScenarioName === scenario);
                if (result) {
                    eacopyTimeData.push(result.EACopy.ElapsedSeconds);
                    robocopyTimeData.push(result.Robocopy.ElapsedSeconds);
                    eacopyThroughputData.push(result.EACopy.ThroughputMBps);
                    robocopyThroughputData.push(result.Robocopy.ThroughputMBps);
                    improvementData.push(result.TimeDiffPercent);
                }
            });
            
            datasets.eacopyTime.push({
                label: `EACopy - ${scenario}`,
                data: eacopyTimeData,
                borderColor: getColor(scenarioIndex, 0),
                backgroundColor: getColor(scenarioIndex, 0, 0.1),
                fill: false
            });
            
            datasets.robocopyTime.push({
                label: `Robocopy - ${scenario}`,
                data: robocopyTimeData,
                borderColor: getColor(scenarioIndex, 1),
                backgroundColor: getColor(scenarioIndex, 1, 0.1),
                fill: false,
                borderDash: [5, 5]
            });
            
            datasets.eacopyThroughput.push({
                label: `EACopy - ${scenario}`,
                data: eacopyThroughputData,
                borderColor: getColor(scenarioIndex, 0),
                backgroundColor: getColor(scenarioIndex, 0, 0.1),
                fill: false
            });
            
            datasets.robocopyThroughput.push({
                label: `Robocopy - ${scenario}`,
                data: robocopyThroughputData,
                borderColor: getColor(scenarioIndex, 1),
                backgroundColor: getColor(scenarioIndex, 1, 0.1),
                fill: false,
                borderDash: [5, 5]
            });
            
            datasets.improvement.push({
                label: scenario,
                data: improvementData,
                borderColor: getColor(scenarioIndex, 2),
                backgroundColor: getColor(scenarioIndex, 2, 0.1),
                fill: false
            });
        });
        
        // Helper function to get colors
        function getColor(index, variant, alpha = 1) {
            const colors = [
                ['rgb(54, 162, 235)', 'rgb(54, 162, 235, ' + alpha + ')'],
                ['rgb(255, 99, 132)', 'rgb(255, 99, 132, ' + alpha + ')'],
                ['rgb(75, 192, 192)', 'rgb(75, 192, 192, ' + alpha + ')'],
                ['rgb(255, 159, 64)', 'rgb(255, 159, 64, ' + alpha + ')']
            ];
            
            const variants = [
                [0, 0],  // EACopy
                [1, 0],  // Robocopy
                [2, 0]   // Improvement
            ];
            
            const [colorIndex, alphaIndex] = variants[variant];
            return colors[(index + colorIndex) % colors.length][alphaIndex];
        }
        
        // Create charts
        const timeCtx = document.getElementById('timeChart').getContext('2d');
        new Chart(timeCtx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [...datasets.eacopyTime, ...datasets.robocopyTime]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        title: {
                            display: true,
                            text: 'Time (seconds)'
                        },
                        beginAtZero: true
                    }
                }
            }
        });
        
        const throughputCtx = document.getElementById('throughputChart').getContext('2d');
        new Chart(throughputCtx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [...datasets.eacopyThroughput, ...datasets.robocopyThroughput]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        title: {
                            display: true,
                            text: 'Throughput (MB/s)'
                        },
                        beginAtZero: true
                    }
                }
            }
        });
        
        const improvementCtx = document.getElementById('improvementChart').getContext('2d');
        new Chart(improvementCtx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: datasets.improvement
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        title: {
                            display: true,
                            text: 'Improvement (%)'
                        }
                    }
                }
            }
        });
        
        // Fill latest results table
        const latestData = historyData[historyData.length - 1];
        const latestTable = document.getElementById('latestResults');
        
        latestData.TestResults.forEach(result => {
            const row = latestTable.insertRow();
            row.insertCell(0).textContent = result.ScenarioName;
            row.insertCell(1).textContent = result.EACopy.ElapsedSeconds;
            row.insertCell(2).textContent = result.EACopy.ThroughputMBps;
            row.insertCell(3).textContent = result.Robocopy.ElapsedSeconds;
            row.insertCell(4).textContent = result.Robocopy.ThroughputMBps;
            row.insertCell(5).textContent = result.TimeDiffPercent + '%';
            row.insertCell(6).textContent = result.FasterTool;
        });
        
        // Fill history table
        const historyTable = document.getElementById('historyTable');
        
        historyData.forEach(entry => {
            const row = historyTable.insertRow();
            row.insertCell(0).textContent = new Date(entry.TestDate).toLocaleString();
            row.insertCell(1).textContent = entry.CommitId.substring(0, 7);
            
            // Add improvement percentages for each scenario
            scenarios.forEach((scenario, index) => {
                const result = entry.TestResults.find(r => r.ScenarioName === scenario);
                row.insertCell(2 + index).textContent = result ? result.TimeDiffPercent + '%' : 'N/A';
            });
        });
    </script>
</body>
</html>
"@

# Save HTML report
$HtmlReportPath = Join-Path $OutputDir "performance_trends.html"
$HtmlReport | Out-File -FilePath $HtmlReportPath -Encoding utf8

Write-Host "Performance trends report generated at: $HtmlReportPath"

# Generate a simple markdown summary for the latest results
$LatestData = $HistoryData | Select-Object -Last 1
if ($LatestData) {
    $MarkdownSummary = @"
## EACopy Performance Trends Summary

Latest test: $($LatestData.TestDate)

| Scenario | Improvement over Robocopy |
|----------|---------------------------|
"@

    foreach ($Result in $LatestData.TestResults) {
        $MarkdownSummary += "`n| $($Result.ScenarioName) | $($Result.TimeDiffPercent)% |"
    }

    $MarkdownSummary += @"

[View Full Performance Trends](./performance_trends.html)
"@

    $MarkdownSummaryPath = Join-Path $OutputDir "performance_summary.md"
    $MarkdownSummary | Out-File -FilePath $MarkdownSummaryPath -Encoding utf8
    
    Write-Host "Performance summary generated at: $MarkdownSummaryPath"
}
