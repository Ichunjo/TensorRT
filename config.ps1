# config.ps1
# --- CONFIGURATION ---

$IsOSWindows = ($env:OS -eq "Windows_NT")
$IsOSLinux = -not $IsOSWindows

$Workspace = Resolve-Path "$PSScriptRoot" | Select-Object -ExpandProperty Path

# Ensure virtual environment exists
if (-not (Test-Path "$Workspace/.venv")) {
    uv venv "$Workspace/.venv" | Out-Null
}

# --- VERSION (single source of truth: VERSION file) ---
$IsRTX = ($env:BUILD_RTX -eq "1" -or $env:TRT_RTX -eq "1")
$VersionFileContent = if ($IsRTX) { (Get-Content "$Workspace/VERSION_RTX" -Raw).Trim() } else { (Get-Content "$Workspace/VERSION" -Raw).Trim() }

$TrtPyVersion = if (-not [string]::IsNullOrEmpty($env:TRT_PY_VERSION)) { $env:TRT_PY_VERSION } else { $VersionFileContent }
$VersionParts = $TrtPyVersion.Split(".")

$TrtMajor = if (-not [string]::IsNullOrEmpty($env:TRT_MAJOR)) { $env:TRT_MAJOR } else { $VersionParts[0] }
$TrtMinor = if (-not [string]::IsNullOrEmpty($env:TRT_MINOR)) { $env:TRT_MINOR } else { $VersionParts[1] }
$TrtVersion = if (-not [string]::IsNullOrEmpty($env:TRT_VERSION)) { $env:TRT_VERSION } else { "$($VersionParts[0]).$($VersionParts[1]).$($VersionParts[2])" }

$CudaMajor = $env:CUDA_MAJOR
if ([string]::IsNullOrEmpty($CudaMajor)) { $CudaMajor = "13" }

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
    $SdkPrefix = if ($IsRTX) { "TensorRT-RTX-" } else { "TensorRT-" }
    $PossibleTrtDir = "$Workspace/$SdkPrefix$TrtPyVersion"
    if (Test-Path $PossibleTrtDir) {
        $TrtSdkDir = $PossibleTrtDir
    }
    else {
        if ($IsOSWindows) {
            $TrtSdkDir = "d:\TensorRT\$SdkPrefix$TrtPyVersion"
        }
        else {
            $TrtSdkDir = "/usr/local/tensorrt"
        }
    }
}

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
if ($IsRTX) {
    $Replacements = @{
        "##TENSORRT_VERSION##"         = $TrtVersion
        "##TENSORRT_MAJMINPATCH##"     = $TrtVersion
        "##TENSORRT_PYTHON_VERSION##"  = $TrtPyVersion
        "##TENSORRT_MODULE##"          = "tensorrt_rtx"
        "##TENSORRT_NVINFER_NAME##"    = "tensorrt_rtx"
        "##TENSORRT_MINOR##"           = $TrtMinor
        "##TENSORRT_MAJOR##"           = $TrtMajor
        "##TENSORRT_ONNXPARSER_NAME##" = "tensorrt_onnxparser_rtx"
        "##TENSORRT_PLUGIN_DISABLED##" = "True"
        "##CUDA_MAJOR##"               = $CudaMajor
        "##TENSORRT_README##"          = "NVIDIA TensorRT RTX is an SDK for high-performance AI inference on NVIDIA RTX GPUs. It includes a Just-in-Time compiler for fast on-device inference optimizations that enable portable deployments and runtime performance specialization. It also introduces convenience features such as built-in CUDA graph support, runtime cache, and a simplified development workflow."
    }
}
else {
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
}

# --- HELPER FUNCTIONS ---

function Remove-LinkOrDirectory {
    <#
    .SYNOPSIS
        Removes a symlink, junction, or regular directory.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path)) { return }

    if ($IsOSWindows) {
        $Item = Get-Item $Path
        if ($Item.Attributes -match "ReparsePoint") {
            [System.IO.Directory]::Delete($Path)
        }
        else {
            Remove-Item -Force -Recurse $Path
        }
    }
    else {
        Remove-Item -Force -Recurse $Path
    }
}

function New-LinkItem {
    <#
    .SYNOPSIS
        Creates a Junction (Windows) or SymbolicLink (Linux) at $Path pointing to $Target.
        Removes any existing item at $Path first.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )

    Remove-LinkOrDirectory -Path $Path

    if ($IsOSWindows) {
        New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
    }
    else {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
    }
}

function Invoke-PlaceholderReplacement {
    <#
    .SYNOPSIS
        Replaces all ##PLACEHOLDER## tokens in text files under a directory using the $Replacements map.
    #>
    param(
        [Parameter(Mandatory)][string]$Directory
    )

    $TextFiles = Get-ChildItem -Path $Directory -Recurse -File | Where-Object { $_.Extension -in @(".py", ".toml", ".cfg", ".txt") }
    foreach ($File in $TextFiles) {
        $Content = Get-Content -Path $File.FullName -Raw -Encoding utf8
        foreach ($Key in $Replacements.Keys) {
            $Content = $Content.Replace($Key, $Replacements[$Key])
        }
        Set-Content -Path $File.FullName -Value $Content -Encoding utf8NoBOM -NoNewline
    }
}
