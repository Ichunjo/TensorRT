# Load config if run directly
if ($null -eq $Workspace) {
    . "$PSScriptRoot/config.ps1"
}

# --- PACKAGE TENSORRT FRONTEND WHEEL ---
Write-Host "`nPackaging tensorrt frontend wheel..." -ForegroundColor Cyan
$FrontendTemp = "$ModuleBuildDir/frontend_sdist_temp"
if (Test-Path $FrontendTemp) {
    Remove-Item -Recurse -Force $FrontendTemp
}
Copy-Item -Path "$Workspace/python/packaging/frontend_sdist" -Destination $FrontendTemp -Recurse

# Copy build backend
Copy-Item -Path "$Workspace/python/packaging/tensorrt_build_backend" -Destination "$FrontendTemp/tensorrt_build_backend" -Recurse

# Copy requirements.txt
Copy-Item -Path "$Workspace/python/packaging/requirements.txt" -Destination "$FrontendTemp/requirements.txt"

# Replace placeholders
Write-Host "Replacing template placeholders in frontend..." -ForegroundColor Green
Invoke-PlaceholderReplacement -Directory $FrontendTemp

# Run PEP 517 build for frontend
Push-Location $FrontendTemp
try {
    uv build --wheel --sdist --no-build-isolation `
        --config-setting wheel-type=frontend `
        --config-setting python-tag=py3 `
        --config-setting plat-name=any `
        --out-dir $DistDir
}
finally {
    Pop-Location
}
