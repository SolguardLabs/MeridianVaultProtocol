$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $root
try {
    & forge test @args
    if ($LASTEXITCODE -ne 0) {
        throw "forge test finalizó con código $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
