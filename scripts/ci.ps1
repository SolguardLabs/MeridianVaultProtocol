$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Command
    )

    & $Command[0] $Command[1..($Command.Length - 1)]
    if ($LASTEXITCODE -ne 0) {
        throw "$($Command -join ' ') finalizó con código $LASTEXITCODE"
    }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $root
try {
    Invoke-Checked @("forge", "fmt", "--check")
    Invoke-Checked @("forge", "build", "--sizes")
    $env:FOUNDRY_PROFILE = "ci"
    Invoke-Checked @("forge", "test", "-vvv")
}
finally {
    Pop-Location
}
