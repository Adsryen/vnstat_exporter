$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ImageName = "adsryen/vnstat_exporter:latest"
$VnstatVersion = "1.15"
$Tarball = "vnstat-$VnstatVersion.tar.gz"
$TarballPath = Join-Path $ScriptDir $Tarball

Write-Host ">>> Checking $Tarball ..."
if (-Not (Test-Path $TarballPath)) {
    Write-Host ">>> Downloading vnstat $VnstatVersion ..."
    Invoke-WebRequest -Uri "https://humdi.net/vnstat/$Tarball" -OutFile $TarballPath
    Write-Host ">>> Download complete"
} else {
    Write-Host ">>> Already exists, skipping download"
}

Write-Host ">>> Building image $ImageName ..."
docker build --no-cache -t $ImageName $ScriptDir
if ($LASTEXITCODE -ne 0) {
    Write-Host ">>> Build failed, aborting"
    exit 1
}

Write-Host ">>> Pushing image $ImageName ..."
docker push $ImageName

Write-Host ">>> Done"
