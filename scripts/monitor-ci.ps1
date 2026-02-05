$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking latest CI Run status..."

# Ensure gh is authenticated
try {
    gh auth status *>$null
    if ($LASTEXITCODE -ne 0) { throw "Not authenticated" }
} catch {
    Write-Error "❌ GitHub CLI is not authenticated. Please run 'gh auth login'."
    exit 1
}

# Get the latest run for the 'validate' workflow
# ConvertFrom-Json automatically handles the JSON output
$latestRunJson = gh run list --workflow ci.yaml --limit 1 --json status,conclusion,url | Out-String

if ([string]::IsNullOrWhiteSpace($latestRunJson) -or $latestRunJson.Trim() -eq "[]") {
    Write-Warning "⚠️ No runs found for workflow ci.yaml"
    exit 0
}

$runs = $latestRunJson | ConvertFrom-Json
$latestRun = $runs[0]

$status = $latestRun.status
$conclusion = $latestRun.conclusion
$url = $latestRun.url

Write-Host "   Status: $status"

if ($status -eq "in_progress" -or $status -eq "queued") {
    Write-Host "⏳ CI is currently running. Watching logs..."
    gh run watch
    
    # Re-check status using exit code of gh run view --exit-status
    # This command exits with 1 if the run failed
    gh run view --exit-status *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ CI Succeeded!" -ForegroundColor Green
    } else {
        Write-Host "❌ CI Failed." -ForegroundColor Red
    }
    
} elseif ($conclusion -eq "success") {
    Write-Host "✅ Latest CI Run Succeeded." -ForegroundColor Green
    Write-Host "   URL: $url"
    
} else {
    Write-Host "❌ Latest CI Run Failed ($conclusion)." -ForegroundColor Red
    Write-Host "   URL: $url"
    Write-Host "   Fetching failure logs..."
    gh run view --log-failed
    exit 1
}
