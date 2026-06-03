<#
.SYNOPSIS
    Main orchestration script to compile and package all standalone TensorRT Python 3.14 binding wheels.
#>

# Load configuration
. "$PSScriptRoot/config.ps1"

# Ensure build requirements are installed in the venv
Write-Host "Installing build requirements inside the virtual environment..." -ForegroundColor Green
uv pip install setuptools wheel cmake ninja

# --- STEP 1: VERIFY ENVIRONMENT ---
Write-Host "Step 1: Verifying environment..." -ForegroundColor Cyan
if (-not (Test-Path $PythonPath)) {
    Write-Error "Python path not found: $PythonPath"
    exit 1
}
if (-not (Test-Path $CudaIncludeDir)) {
    Write-Error "CUDA include directory not found: $CudaIncludeDir"
    exit 1
}
if (-not (Test-Path $TrtSdkDir)) {
    Write-Error "TensorRT SDK directory not found: $TrtSdkDir"
    exit 1
}

# --- STEP 2: SETUP EXTERNAL DIRECTORY LINKS ---
Write-Host "`nStep 2: Setting up external directory links..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path "$ExtDir/python3.14" | Out-Null

if ($IsOSWindows) {
    New-LinkItem -Path "$ExtDir/python3.14/include" -Target "$PythonPath/include"
    New-LinkItem -Path "$ExtDir/python3.14/lib" -Target "$PythonPath/libs"
}
else {
    $LinuxIncludeTarget = "$PythonPath/include"
    # Find python include dir (e.g. /usr/include/python3.14)
    $PossibleInclude = Get-ChildItem -Path "$PythonPath/include" -Filter "python3.14*" -Directory | Select-Object -First 1
    if ($null -ne $PossibleInclude) {
        $LinuxIncludeTarget = $PossibleInclude.FullName
    }
    elseif (Test-Path "$PythonPath/include/python3.14") {
        $LinuxIncludeTarget = "$PythonPath/include/python3.14"
    }
    New-LinkItem -Path "$ExtDir/python3.14/include" -Target $LinuxIncludeTarget
    New-LinkItem -Path "$ExtDir/python3.14/lib" -Target "$PythonPath/lib"
}

Remove-LinkOrDirectory -Path "$ExtDir/pybind11"

# Initialize/Clean output directory
if (Test-Path $DistDir) {
    Write-Host "Cleaning output directory: $DistDir..." -ForegroundColor Green
    Remove-Item -Path "$DistDir/*" -Force -Recurse -ErrorAction SilentlyContinue
}
else {
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
}

# --- BUILD ARTIFACTS ---
. "$PSScriptRoot/build_bindings.ps1"
. "$PSScriptRoot/build_libs.ps1"

# Install built bindings and libs wheels to satisfy frontend dependencies
Write-Host "`nInstalling compiled bindings and libs wheels locally to satisfy frontend dependencies..." -ForegroundColor Green
$BuiltWheels = Get-ChildItem -Path $DistDir -Filter "*.whl" | Select-Object -ExpandProperty FullName
if ($BuiltWheels) {
    uv pip install --force-reinstall $BuiltWheels
}

. "$PSScriptRoot/build_frontend.ps1"

Write-Host "`nAll standalone wheels built successfully! Located in: $DistDir" -ForegroundColor Cyan
