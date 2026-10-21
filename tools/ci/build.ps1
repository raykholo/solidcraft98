# Builds SolidCraft98.exe with twinBASIC, unattended. Used by CI; works on any
# Windows PC with twinBASIC unzipped somewhere and Python 3 on the PATH.
#
#   tools\ci\build.ps1 -TwinBasic C:\tB -Upx C:\upx\upx.exe -Out out
#
# Leaves out\SolidCraft98.exe (as built) and out\SC98.EXE (UPX-packed, for the
# floppy), and fails if the packed EXE doesn't fit on a 1.44 MB floppy.
param(
    [Parameter(Mandatory)] [string] $TwinBasic,
    [Parameter(Mandatory)] [string] $Upx,
    [string] $Out = "out",
    [int] $TimeoutSeconds = 300
)
$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $Root
$FloppyBytes = 1457664

# 1. twinBASIC's first-run questions, answered in advance: its licence
#    agreement (which the project owner has accepted), no error reporting, and
#    the IDE options. Without these the IDE waits for a click that never comes.
$key = "HKCU:\Software\VB and VBA Program Settings\twinBASIC_IDE\IDESettings"
New-Item -Path $key -Force | Out-Null
$today = (Get-Date).ToString("dd-MMM-yyyy", [Globalization.CultureInfo]::InvariantCulture).ToUpper()
Set-ItemProperty $key LICENCEAGREEMENTV3 ("AGREED_" + $today)
Set-ItemProperty $key ALLOWERRORREPORTINGV3 ("DISAGREED_" + $today)
Set-ItemProperty $key GENERAL (Get-Content -Raw (Join-Path $PSScriptRoot "twinbasic-ide-settings.json"))

# 2. VB6 project -> twinBASIC source folder -> .twinproj
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
python tools/vb2tb.py src/SolidCraft98.vbp build/src
if ($LASTEXITCODE) { throw "vb2tb failed" }
python tools/impexp.py import build/SolidCraft98.twinproj build/src --overwrite
if ($LASTEXITCODE) { throw "impexp failed" }

# 3. Build. On a compile error twinBASIC doesn't exit, so give up after a while.
$proj = Join-Path $Root "build\SolidCraft98.twinproj"
$exe = Join-Path $Root "build\Build\SolidCraft98.exe"
$p = Start-Process -FilePath (Join-Path $TwinBasic "twinBASIC.exe") -ArgumentList "`"$proj`" --buildAndExit32" -PassThru
if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
    Get-Process twinBASIC* -ErrorAction SilentlyContinue | Stop-Process -Force
    throw "twinBASIC didn't finish in $TimeoutSeconds s: probably a compile error. Open build\SolidCraft98.twinproj in the IDE to see it."
}
Get-Process twinBASIC* -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not (Test-Path $exe)) { throw "twinBASIC exited without building $exe" }

# 4. The EXE, and a UPX-packed copy for the floppy, which has to fit.
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item $exe (Join-Path $Out "SolidCraft98.exe") -Force
$packed = Join-Path $Out "SC98.EXE"
Remove-Item $packed -ErrorAction SilentlyContinue
& $Upx --best --lzma -q -o $packed $exe | Out-Host
if ($LASTEXITCODE) { throw "UPX failed" }
$built = (Get-Item $exe).Length
$size = (Get-Item $packed).Length
Write-Host ("SolidCraft98.exe: {0:N0} bytes; packed for the floppy: {1:N0} of {2:N0} bytes ({3:P0})" -f $built, $size, $FloppyBytes, ($size / $FloppyBytes))
if ($size -gt $FloppyBytes) {
    throw "The packed EXE is $size bytes: it no longer fits on a 1.44 MB floppy ($FloppyBytes bytes)."
}
