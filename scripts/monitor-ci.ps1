$ErrorActionPreference = "Stop"

Write-Host "Checking latest CI Run status..."

# Ensure gh is authenticated
try {
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Not authenticated" }
} catch {
    Write-Error "GitHub CLI is not authenticated. Please run 'gh auth login'."
    exit 1
}

# Get the latest run for the 'validate' workflow
$json = gh run list --workflow ci.yaml --limit 1 --json status,conclusion,url | Out-String

if ([string]::IsNullOrWhiteSpace($json) -or $json.Trim() -eq '[]') {
    Write-Warning "No runs found for workflow ci.yaml"
    exit 0
}

try {
    $runs = $json | ConvertFrom-Json
    $run = $runs[0]

    Write-Host "Status: $($run.status)"

    if ($run.status -eq "in_progress" -or $run.status -eq "queued") {
        Write-Host "CI is currently running. Watching logs..."
        gh run watch
        
        if ($?) {
            Write-Host "CI Succeeded!" -ForegroundColor Green
        } else {
            Write-Host "CI Failed." -ForegroundColor Red
        }
        
    } elseif ($run.conclusion -eq "success") {
        Write-Host "Latest CI Run Succeeded." -ForegroundColor Green
        Write-Host "URL: $($run.url)"
        
    } else {
        Write-Host "Latest CI Run Failed ($($run.conclusion))." -ForegroundColor Red
        Write-Host "URL: $($run.url)"
        Write-Host "Fetching failure logs..."
        gh run view --log-failed
        exit 1
    }
} catch {
    Write-Error "Failed to parse JSON or monitor run."
    Write-Error $_
    exit 1
}
