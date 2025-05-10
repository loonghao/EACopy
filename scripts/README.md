# EACopy Performance Testing

This directory contains scripts for performance testing EACopy against Robocopy and tracking performance trends over time.

## Scripts Overview

### `performance_test.ps1`

This script compares the performance of EACopy and Robocopy for various file operations.

**Usage:**
```powershell
.\performance_test.ps1 -EACopyPath ".\Release\EACopy.exe" -TestDir ".\perf_test" -SmallFileCount 100 -MediumFileCount 20 -LargeFileCount 5 -CleanupAfterTest $false -HistoryDir ".\performance_history" -CommitId "abc1234"
```

**Parameters:**
- `EACopyPath`: Path to the EACopy executable
- `TestDir`: Directory to store test files and results
- `SmallFileCount`: Number of small files to create for testing
- `SmallFileSize`: Size of each small file (default: 10KB)
- `MediumFileCount`: Number of medium files to create for testing
- `MediumFileSize`: Size of each medium file (default: 1MB)
- `LargeFileCount`: Number of large files to create for testing
- `LargeFileSize`: Size of each large file (default: 10MB)
- `CleanupAfterTest`: Whether to clean up test files after testing
- `HistoryDir`: Directory to store historical performance data
- `CommitId`: Git commit ID to associate with the test results

### `post_performance_results.ps1`

This script posts performance test results as a PR comment on GitHub.

**Usage:**
```powershell
.\post_performance_results.ps1 -MarkdownReportPath ".\perf_test\performance_results.md" -GithubToken $env:GITHUB_TOKEN -RepoOwner "username" -RepoName "repo" -PrNumber 123
```

**Parameters:**
- `MarkdownReportPath`: Path to the markdown report file
- `GithubToken`: GitHub API token
- `RepoOwner`: Repository owner
- `RepoName`: Repository name
- `PrNumber`: Pull request number

### `generate_performance_trends.ps1`

This script generates performance trend visualizations from historical test data.

**Usage:**
```powershell
.\generate_performance_trends.ps1 -HistoryDir ".\performance_history" -OutputDir ".\performance_trends" -MaxHistoryEntries 10
```

**Parameters:**
- `HistoryDir`: Directory containing historical performance data
- `OutputDir`: Directory to output trend visualizations
- `MaxHistoryEntries`: Number of historical entries to include in trends

## Performance History

Performance history is stored in the `performance_history` directory as JSON files with the naming format:
```
performance_YYYYMMDD_HHMMSS_COMMIT.json
```

Each file contains:
- Test date and time
- Test results for different scenarios
- Performance metrics for both EACopy and Robocopy

## Performance Trends

Performance trends are generated as HTML visualizations in the `performance_trends` directory:
- `performance_trends.html`: Interactive charts showing performance trends over time
- `performance_summary.md`: Markdown summary of the latest performance results

## CI Integration

These scripts are integrated into the CI pipeline to:
1. Run performance tests on each PR
2. Save results to the performance history
3. Generate trend visualizations
4. Post results as a PR comment

## Manual Testing

To run a performance test manually:

```powershell
# Create test directories
mkdir -p perf_test
mkdir -p performance_history
mkdir -p performance_trends

# Run performance test
.\scripts\performance_test.ps1 -EACopyPath ".\Release\EACopy.exe" -TestDir ".\perf_test" -HistoryDir ".\performance_history"

# Generate trends
.\scripts\generate_performance_trends.ps1 -HistoryDir ".\performance_history" -OutputDir ".\performance_trends"
```

The HTML report can be opened in a browser to view the performance trends.
