$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ImageName = "adsryen/vnstat_exporter:latest"

Write-Host ">>> Building image $ImageName ..."
docker build --no-cache -t $ImageName $ScriptDir
if ($LASTEXITCODE -ne 0) {
    Write-Host ">>> Build failed, aborting"
    exit 1
}

Write-Host ">>> Pushing image $ImageName ..."
docker push $ImageName

Write-Host ">>> Done"
