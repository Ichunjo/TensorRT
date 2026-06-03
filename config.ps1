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
$VersionFileContent = (Get-Content "$Workspace/VERSION" -Raw).Trim()

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
    $PossibleTrtDir = "$Workspace/TensorRT-$TrtPyVersion"
    if (Test-Path $PossibleTrtDir) {
        $TrtSdkDir = $PossibleTrtDir
    }
    else {
        if ($IsOSWindows) {
            $TrtSdkDir = "d:\TensorRT\TensorRT-$TrtPyVersion"
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

# --- HELPER FUNCTIONS ---

function Remove-LinkOrDirectory {
    <#
    .SYNOPSIS
        Removes a symlink, junction, or regular directory.
        Handles broken junctions (e.g., stale WSL-path reparse points) gracefully.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path)) { return }

    if ($IsOSWindows) {
        $Item = Get-Item $Path
        if ($Item.Attributes -match "ReparsePoint") {
            # Try Directory::Delete first (normal junctions), fall back to File::Delete
            # for broken reparse points that the system doesn't recognize as directories
            try {
                [System.IO.Directory]::Delete($Path)
            }
            catch {
                [System.IO.File]::Delete($Path)
            }
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
        [System.IO.File]::WriteAllText($File.FullName, $Content, (New-Object System.Text.UTF8Encoding $false))
    }
}
