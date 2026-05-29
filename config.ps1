# config.ps1
# --- CONFIGURATION ---

$IsOSWindows = ($env:OS -eq "Windows_NT")
$IsOSLinux = -not $IsOSWindows

$Workspace = Resolve-Path "$PSScriptRoot" | Select-Object -ExpandProperty Path

# Ensure virtual environment exists
if (-not (Test-Path "$Workspace/.venv")) {
    uv venv "$Workspace/.venv" | Out-Null
}

# Dynamic environment variable checking for Linux system-installed TensorRT
if ($IsOSLinux) {
    $TempTrtSdkDir = $env:TRT_SDK_DIR
    if ([string]::IsNullOrEmpty($TempTrtSdkDir) -or $TempTrtSdkDir -eq "/usr" -or $TempTrtSdkDir -eq "/usr/") {
        if (Test-Path "/usr/include/NvInfer.h") {
            $SdkLinkDir = "$Workspace/tensorrt_sdk"
            if (-not (Test-Path $SdkLinkDir)) {
                New-Item -ItemType Directory -Force -Path $SdkLinkDir | Out-Null
            }
            if (-not (Test-Path "$SdkLinkDir/include")) {
                New-Item -ItemType SymbolicLink -Path "$SdkLinkDir/include" -Target "/usr/include" -Force | Out-Null
            }
            if (-not (Test-Path "$SdkLinkDir/lib")) {
                $LibTarget = if (Test-Path "/usr/lib64") { "/usr/lib64" } else { "/usr/lib" }
                New-Item -ItemType SymbolicLink -Path "$SdkLinkDir/lib" -Target $LibTarget -Force | Out-Null
            }
            $env:TRT_SDK_DIR = $SdkLinkDir
        }
    }
}

$PythonPath = (uv run python -c "import sys; print(sys.base_prefix)").Trim()
if ([string]::IsNullOrEmpty($PythonPath) -or -not (Test-Path $PythonPath)) {
    throw "Could not resolve Python path via uv"
}

$CudaPath = $env:CUDA_PATH
if ([string]::IsNullOrEmpty($CudaPath)) {
    $CudaPath = if ($IsOSWindows) { "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2" } else { "/usr/local/cuda" }
}
$CudaIncludeDir = "$CudaPath/include"

$TrtSdkDir = $env:TRT_SDK_DIR
if ([string]::IsNullOrEmpty($TrtSdkDir)) {
    $PossibleTrtDir = "$Workspace/TensorRT-10.16.1.11"
    if (Test-Path $PossibleTrtDir) {
        $TrtSdkDir = $PossibleTrtDir
    }
    else {
        if ($IsOSWindows) {
            $TrtSdkDir = "d:\TensorRT\TensorRT-10.16.1.11"
        }
        else {
            $TrtSdkDir = "/usr/local/tensorrt"
        }
    }
}

$TrtVersion = $env:TRT_VERSION
if ([string]::IsNullOrEmpty($TrtVersion)) { $TrtVersion = "10.16.1" }

$TrtPyVersion = $env:TRT_PY_VERSION
if ([string]::IsNullOrEmpty($TrtPyVersion)) { $TrtPyVersion = "10.16.1.11" }

$TrtMajor = $env:TRT_MAJOR
if ([string]::IsNullOrEmpty($TrtMajor)) { $TrtMajor = "10" }

$TrtMinor = $env:TRT_MINOR
if ([string]::IsNullOrEmpty($TrtMinor)) { $TrtMinor = "16" }

$CudaMajor = $env:CUDA_MAJOR
if ([string]::IsNullOrEmpty($CudaMajor)) { $CudaMajor = "13" }

$PlatName = $env:PLAT_NAME
if ([string]::IsNullOrEmpty($PlatName)) {
    if ($IsOSWindows) {
        $PlatName = "win_amd64"
    }
    else {
        $PlatName = "linux_x86_64"
    }
}

$ExtDir = "$Workspace/ext"
$BuildDir = "$Workspace/python/build"
$ModuleBuildDir = "$BuildDir/build_tensorrt"
$DistDir = "$BuildDir/dist"

# Shared Replacements Map
$Replacements = @{
    "##TENSORRT_VERSION##"         = $TrtVersion
    "##TENSORRT_MAJMINPATCH##"     = $TrtVersion
    "##TENSORRT_PYTHON_VERSION##"  = $TrtPyVersion
    "##TENSORRT_MODULE##"          = "tensorrt"
    "##TENSORRT_NVINFER_NAME##"    = "nvinfer"
    "##TENSORRT_MINOR##"           = $TrtMinor
    "##TENSORRT_MAJOR##"           = $TrtMajor
    "##TENSORRT_ONNXPARSER_NAME##" = "nvonnxparser"
    "##TENSORRT_PLUGIN_DISABLED##" = "False"
    "##CUDA_MAJOR##"               = $CudaMajor
    "##TENSORRT_README##"          = "Standalone python bindings for TensorRT"
}
