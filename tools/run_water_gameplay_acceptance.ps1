param(
    [Parameter(Position = 0)]
    [string]$Mode = "shore",
    [switch]$QaCapture
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$godot = Join-Path $projectRoot "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.2 console not found. Expected tools\godot\Godot_v4.7.2-stable_win64_console.exe"
}

$normalized = $Mode.Trim().ToLowerInvariant()
if ($normalized -notin @("shore", "pier")) {
    throw "Unknown mode '$Mode'. Expected shore or pier."
}

$godotArgs = @(
    "--path", $projectRoot,
    "--script", "res://tools/water_gameplay_acceptance.gd",
    "--",
    $normalized
)
if ($QaCapture) {
    $godotArgs += "qa-capture"
}

Write-Output "WATER_GAMEPLAY_ACCEPTANCE launching $normalized"
& $godot @godotArgs
exit $LASTEXITCODE
