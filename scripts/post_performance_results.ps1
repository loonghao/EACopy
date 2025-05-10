# Script to post performance test results as a PR comment
param (
    [string]$MarkdownReportPath = ".\perf_test\performance_results.md",
    [string]$GithubToken,
    [string]$RepoOwner,
    [string]$RepoName,
    [int]$PrNumber
)

# Check if required parameters are provided
if (-not $GithubToken -or -not $RepoOwner -or -not $RepoName -or -not $PrNumber) {
    Write-Error "Missing required parameters. Please provide GithubToken, RepoOwner, RepoName, and PrNumber."
    exit 1
}

# Check if markdown report exists
if (-not (Test-Path $MarkdownReportPath)) {
    Write-Error "Markdown report not found at: $MarkdownReportPath"
    exit 1
}

# Read the markdown report
$MarkdownContent = Get-Content -Path $MarkdownReportPath -Raw

# Create the comment body
$CommentBody = @{
    body = $MarkdownContent
}

# Convert to JSON
$JsonBody = $CommentBody | ConvertTo-Json

# API URL for creating a PR comment
$ApiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/issues/$PrNumber/comments"

# Headers for the API request
$Headers = @{
    Authorization = "token $GithubToken"
    Accept = "application/vnd.github.v3+json"
}

# Post the comment
try {
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $Headers -Body $JsonBody -ContentType "application/json"
    Write-Host "Successfully posted performance test results to PR #$PrNumber"
    Write-Host "Comment URL: $($Response.html_url)"
} catch {
    Write-Error "Failed to post comment: $_"
    exit 1
}
