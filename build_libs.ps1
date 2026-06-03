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

# Rename package directory if not default
$TrtModule = if ($IsRTX) { "tensorrt_rtx" } else { "tensorrt" }
$TrtModuleLibs = $TrtModule + "_libs"
if ($TrtModule -ne "tensorrt") {
    Rename-Item -Path "$LibsTemp/tensorrt_libs" -NewName $TrtModuleLibs
}

# Copy build backend
Copy-Item -Path "$Workspace/python/packaging/tensorrt_build_backend" -Destination "$LibsTemp/tensorrt_build_backend" -Recurse

# Copy requirements.txt
Copy-Item -Path "$Workspace/python/packaging/requirements.txt" -Destination "$LibsTemp/requirements.txt"

# Copy all TensorRT DLLs / Shared Libraries
if ($IsOSWindows) {
    Write-Host "Copying TensorRT DLLs to $TrtModuleLibs..." -ForegroundColor Green
    Get-ChildItem -Path "$TrtSdkDir/bin" -Filter "*.dll" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination "$LibsTemp/$TrtModuleLibs" -Force
    }
}
else {
    Write-Host "Copying TensorRT shared libraries to $TrtModuleLibs..." -ForegroundColor Green
    # Copy only the specific major-versioned TensorRT shared libraries to avoid duplicate files from symlinks
    $LibFiles = Get-ChildItem -Path "$TrtSdkDir/lib" -Filter "*.so.$TrtMajor"
    if ($LibFiles.Count -eq 0) {
        $LibFiles = Get-ChildItem -Path "$TrtSdkDir/lib" -Filter "*.so"
    }
    $LibFiles | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination "$LibsTemp/$TrtModuleLibs" -Force
    }
}

# Replace placeholders
Write-Host "Replacing template placeholders in tensorrt_libs..." -ForegroundColor Green
Invoke-PlaceholderReplacement -Directory $LibsTemp

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
