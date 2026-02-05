$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking latest CI Run status..."

# Ensure gh is authenticated
try {
    # Using null redirection compatible with most PS versions
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Not authenticated" }
} catch {
    Write-Error "❌ GitHub CLI is not authenticated. Please run 'gh auth login'."
    exit 1
}

# Get the latest run for the 'validate' workflow
$latestRunJson = gh run list --workflow ci.yaml --limit 1 --json status,conclusion,url | Out-String

# Trim whitespace - safely handle null
$jsonStr = if ($latestRunJson) { $latestRunJson.Trim() } else { "" }

if ([string]::IsNullOrEmpty($jsonStr) -or $jsonStr -eq '[]') {
    Write-Warning "⚠️ No runs found for workflow ci.yaml"
    exit 0
}

try {
    $runs = $latestRunJson | ConvertFrom-Json
    $latestRun = $runs[0]

    $status = $latestRun.status
    $conclusion = $latestRun.conclusion
    $url = $latestRun.url

    Write-Host "   Status: $status"

    if ($status -eq "in_progress" -or $status -eq "queued") {
        Write-Host "⏳ CI is currently running. Watching logs..."
        gh run watch
        
        # Check exit code
        gh run view --exit-status 2>&1 | Out-Null
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
} catch {
    Write-Error "Failed to parse JSON or monitor run: $_"
    exit 1
}
