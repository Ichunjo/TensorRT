# Load config if run directly
if ($null -eq $Workspace) {
    . "$PSScriptRoot/config.ps1"
}

# --- PACKAGE TENSORRT_LIBS WHEEL ---
Write-Host "`nPackaging standalone tensorrt_libs wheel..." -ForegroundColor Cyan
$LibsTemp = "$ModuleBuildDir/libs_wheel_temp"
if (Test-Path $LibsTemp) {
    Remove-Item -Recurse -Force $LibsTemp
}
Copy-Item -Path "$Workspace/python/packaging/libs_wheel" -Destination $LibsTemp -Recurse

# Copy build backend
Copy-Item -Path "$Workspace/python/packaging/tensorrt_build_backend" -Destination "$LibsTemp/tensorrt_build_backend" -Recurse

# Copy requirements.txt
Copy-Item -Path "$Workspace/python/packaging/requirements.txt" -Destination "$LibsTemp/requirements.txt"

# Copy all TensorRT DLLs / Shared Libraries
if ($IsOSWindows) {
    Write-Host "Copying TensorRT DLLs to tensorrt_libs..." -ForegroundColor Green
    Get-ChildItem -Path "$TrtSdkDir/bin" -Filter "*.dll" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination "$LibsTemp/tensorrt_libs" -Force
    }
}
else {
    Write-Host "Copying TensorRT shared libraries to tensorrt_libs..." -ForegroundColor Green
    # Copy only the specific major-versioned TensorRT shared libraries to avoid duplicate files from symlinks
    $LibFiles = Get-ChildItem -Path "$TrtSdkDir/lib" -Filter "*.so.$TrtMajor"
    if ($LibFiles.Count -eq 0) {
        $LibFiles = Get-ChildItem -Path "$TrtSdkDir/lib" -Filter "*.so"
    }
    $LibFiles | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination "$LibsTemp/tensorrt_libs" -Force
    }
}

# Replace placeholders
Write-Host "Replacing template placeholders in tensorrt_libs..." -ForegroundColor Green
$TextFiles = Get-ChildItem -Path $LibsTemp -Recurse -File | Where-Object { $_.Extension -in @(".py", ".toml", ".cfg", ".txt") }
foreach ($File in $TextFiles) {
    $Content = Get-Content -Path $File.FullName -Raw -Encoding utf8
    foreach ($Key in $Replacements.Keys) {
        $Content = $Content.Replace($Key, $Replacements[$Key])
    }
    [System.IO.File]::WriteAllText($File.FullName, $Content, (New-Object System.Text.UTF8Encoding $false))
}

# Run PEP 517 build for libs
Push-Location $LibsTemp
try {
    uv build --wheel --no-build-isolation `
        --config-setting wheel-type=libs `
        --config-setting python-tag=py3 `
        --config-setting plat-name=$PlatName `
        --out-dir $DistDir
}
finally {
    Pop-Location
}
