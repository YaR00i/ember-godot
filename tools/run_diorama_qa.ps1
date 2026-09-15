param([string]$Fixture, [string]$Godot, [string]$OutputDirectory, [switch]$Resume, [string[]]$SelectedCases)
$ErrorActionPreference = 'Stop'
$fixtureAbsolute = [IO.Path]::GetFullPath($Fixture)
$tempAbsolute = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
if (-not $fixtureAbsolute.StartsWith($tempAbsolute + 'ember-graphics-d97c-', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only the owned disposable graphics Temp fixture is permitted.'
}
$graphicsTree = Split-Path $PSScriptRoot -Parent
$ownedFiles = @('shaders/ember_voxel_toon.gdshader', 'shaders/ember_voxel_transparent.gdshader',
    'shaders/ember_voxel_surface_water.gdshader', 'materials/ember_voxel_toon.tres',
    'materials/ember_voxel_transparent.tres', 'scripts/ember_lights.gd')
$hook = "`tEmberLights.apply_diorama_environment(e, _content_node(`"Look/Sun`") as DirectionalLight3D)"
function Set-Variant([bool]$Baseline) {
    foreach ($file in $ownedFiles) {
        $variantRoot = Join-Path $fixtureAbsolute 'graphics-baseline'
        if (-not $Baseline) { $variantRoot = $graphicsTree }
        Copy-Item -LiteralPath (Join-Path $variantRoot $file) -Destination (Join-Path $fixtureAbsolute $file)
    }
    if (-not $Baseline) {
        Copy-Item -LiteralPath (Join-Path $graphicsTree 'shaders/ember_diorama_light.gdshaderinc') -Destination (Join-Path $fixtureAbsolute 'shaders/ember_diorama_light.gdshaderinc')
        Copy-Item -LiteralPath (Join-Path $graphicsTree 'shaders/ember_water_wave.gdshaderinc') -Destination (Join-Path $fixtureAbsolute 'shaders/ember_water_wave.gdshaderinc')
    }
    $loaderPath = Join-Path $fixtureAbsolute 'scripts/ember_map_loader.gd'
    $loader = Get-Content -Raw -LiteralPath $loaderPath
    $loader = $loader.Replace($hook, '')
    if (-not $Baseline) {
        $loader = $loader.Replace('e.volumetric_fog_enabled = false', 'e.volumetric_fog_enabled = false' + [Environment]::NewLine + $hook)
    }
    Set-Content -LiteralPath $loaderPath -Value $loader -Encoding utf8
}
function Invoke-Capture([string]$Name, [string[]]$Options) {
    $logPath = Join-Path $OutputDirectory ($Name + '.log')
    if ($Resume -and $Name.StartsWith('baseline') -and (Test-Path -LiteralPath $logPath)) {
        $oldLog = Get-Content -Raw -LiteralPath $logPath
        if ($oldLog.Contains('PASS DIORAMA_RENDER') -and $oldLog -notmatch 'SCRIPT ERROR:|ERROR:|FAIL ') {
            Write-Output "REUSE verified fixed baseline $Name"
            return
        }
    }
    $godotArgs = @('--path', $fixtureAbsolute, '--script', 'res://tools/render_diorama.gd', '--') + $Options
    & $Godot @godotArgs 2>&1 | Out-File -LiteralPath $logPath -Encoding utf8
    $code = $LASTEXITCODE
    $errors = Select-String -LiteralPath $logPath -Pattern '^ERROR:|SCRIPT ERROR:|^FAIL '
    if ($code -ne 0 -or $errors) { Get-Content -LiteralPath $logPath; throw "Capture failed $Name code=$code" }
    Select-String -LiteralPath $logPath -Pattern 'LIGHT_PROFILE|METRICS|PASS DIORAMA' | ForEach-Object { $_.Line }
}
$cases = @(
    @{Name='corner'; Args=@('--mode=corner')},
    @{Name='world'; Args=@('--mode=world')},
    @{Name='pier'; Args=@('--mode=pier')},
    @{Name='fan8'; Args=@('--mode=fan','--profile=8')},
    @{Name='fan12'; Args=@('--mode=fan','--profile=12')},
    @{Name='corner-night'; Args=@('--mode=corner','--night')},
    @{Name='corner-warm-moon'; Args=@('--mode=corner','--night','--warm-moon')},
    @{Name='combat'; Args=@('--mode=combat')}
)
if ($SelectedCases) { $cases = $cases | Where-Object { $_.Name -in $SelectedCases } }
try {
    foreach ($baseline in @($true,$false)) {
        Set-Variant $baseline
        foreach ($case in $cases) {
            $label = 'candidate'
            if ($baseline) { $label = 'baseline' }
            if ($case.Name -eq 'corner-warm-moon') { $label += '-warm-moon' }
            if ($case.Name -eq 'fan12') { $label += '-stress12' }
            Invoke-Capture ($label+'-'+$case.Name) ($case.Args + @('--label='+$label))
        }
    }
    if (-not $SelectedCases) {
        Invoke-Capture 'candidate-world-unlit' @('--mode=world','--label=unlit','--unlit','--diagnostic')
        Invoke-Capture 'candidate-world-no-shadows' @('--mode=world','--label=no-shadows','--diagnostic')
        Invoke-Capture 'candidate-water-time8' @('--mode=corner','--label=water-time8','--time=8.25')
    }
} finally {
    Set-Variant $false
}
