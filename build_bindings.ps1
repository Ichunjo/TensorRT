# Load config if run directly
if ($null -eq $Workspace) {
    . "$PSScriptRoot/config.ps1"
}

# --- COMPILE C++ BINDING LIBRARY ---
Write-Host "`nCompiling C++ Bindings..." -ForegroundColor Cyan
$ModuleBuildDir = "$BuildDir/build_tensorrt"
if (Test-Path $ModuleBuildDir) {
    Remove-Item -Recurse -Force $ModuleBuildDir
}
New-Item -ItemType Directory -Force -Path $ModuleBuildDir | Out-Null

# CMake Configure
Write-Host "Configuring CMake..." -ForegroundColor Green
$CMakeArgs = @(
    "-S", "$Workspace/python",
    "-B", "$ModuleBuildDir",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DTRT_BUILD_ENABLE_NEW_PYTHON_FLOW=OFF",
    "-DPYTHON_MAJOR_VERSION=3",
    "-DPYTHON_MINOR_VERSION=14",
    "-DEXT_PATH=$($ExtDir.Replace('\', '/'))",
    "-DCUDA_INCLUDE_DIRS=$($CudaIncludeDir.Replace('\', '/'))",
    "-DTENSORRT_ROOT=$($Workspace.Replace('\', '/'))",
    "-DTENSORRT_MODULE=tensorrt",
    "-DTENSORRT_LIBPATH=$($TrtSdkDir.Replace('\', '/'))/lib",
    "-DTRT_NVINFER_NAME=nvinfer",
    "-DTENSORRT_MAJOR_VERSION=$TrtMajor",
    "-DTRT_ONNXPARSER_NAME=nvonnxparser"
)

if ($IsOSLinux) {
    $TargetArch = "x86_64"
    if ($PlatName -match "aarch64") {
        $TargetArch = "aarch64"
    }
    $CMakeArgs += "-DTARGET=$TargetArch"
}

uv run --no-project cmake @CMakeArgs

# Compile
Write-Host "Compiling bindings..." -ForegroundColor Green
uv run --no-project cmake --build $ModuleBuildDir --config Release

# --- PACKAGE TENSORRT_BINDINGS WHEEL ---
Write-Host "`nPackaging standalone tensorrt_bindings wheel..." -ForegroundColor Cyan
$BindingsTemp = "$ModuleBuildDir/bindings_wheel_temp"
if (Test-Path $BindingsTemp) {
    Remove-Item -Recurse -Force $BindingsTemp
}
Copy-Item -Path "$Workspace/python/packaging/bindings_wheel" -Destination $BindingsTemp -Recurse

# Rename "tensorrt" directory to "tensorrt_bindings" for standalone import structure
Rename-Item -Path "$BindingsTemp/tensorrt" -NewName "tensorrt_bindings"

# Copy build backend
Copy-Item -Path "$Workspace/python/packaging/tensorrt_build_backend" -Destination "$BindingsTemp/tensorrt_build_backend" -Recurse

# Copy requirements.txt
Copy-Item -Path "$Workspace/python/packaging/requirements.txt" -Destination "$BindingsTemp/requirements.txt"

# Copy compiled library
if ($IsOSWindows) {
    $PossiblePaths = @(
        "$ModuleBuildDir/tensorrt/Release/tensorrt.dll",
        "$ModuleBuildDir/tensorrt/tensorrt.dll",
        "$ModuleBuildDir/Release/tensorrt.dll",
        "$ModuleBuildDir/tensorrt.dll"
    )
    $CompiledLib = $null
    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            $CompiledLib = $Path
            break
        }
    }
    if ($null -eq $CompiledLib) {
        Write-Error "Could not find compiled tensorrt.dll"
        exit 1
    }
    $DstLib = "$BindingsTemp/tensorrt_bindings/tensorrt.pyd"
}
else {
    $PossiblePaths = @(
        "$ModuleBuildDir/tensorrt/tensorrt.so",
        "$ModuleBuildDir/tensorrt.so",
        "$ModuleBuildDir/Release/tensorrt.so"
    )
    $CompiledLib = $null
    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            $CompiledLib = $Path
            break
        }
    }
    if ($null -eq $CompiledLib) {
        Write-Error "Could not find compiled tensorrt.so"
        exit 1
    }
    $DstLib = "$BindingsTemp/tensorrt_bindings/tensorrt.so"
}
Copy-Item -Path $CompiledLib -Destination $DstLib -Force

# Replace placeholders
Write-Host "Replacing template placeholders in tensorrt_bindings..." -ForegroundColor Green
$TextFiles = Get-ChildItem -Path $BindingsTemp -Recurse -File | Where-Object { $_.Extension -in @(".py", ".toml", ".cfg", ".txt") }
foreach ($File in $TextFiles) {
    $Content = Get-Content -Path $File.FullName -Raw -Encoding utf8
    foreach ($Key in $Replacements.Keys) {
        $Content = $Content.Replace($Key, $Replacements[$Key])
    }
    [System.IO.File]::WriteAllText($File.FullName, $Content, (New-Object System.Text.UTF8Encoding $false))
}

# Run PEP 517 build for bindings
Push-Location $BindingsTemp
try {
    uv build --wheel --no-build-isolation `
        --config-setting wheel-type=binding_standalone `
        --config-setting python-tag=cp314 `
        --config-setting plat-name=$PlatName `
        --out-dir $DistDir
}
finally {
    Pop-Location
}
