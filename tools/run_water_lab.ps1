param(
    [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$godotCandidates = @(
    (Join-Path $projectRoot "tools\godot\Godot_v4.7.2-stable_win64.exe"),
    (Join-Path $env:USERPROFILE "Projects\ember-godot\tools\godot\Godot_v4.7.2-stable_win64.exe")
)
$godot = $godotCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($godot)) {
    throw "Godot 4.7.2 not found. Expected tools\godot\Godot_v4.7.2-stable_win64.exe"
}

$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Temp"))
$runtime = [System.IO.Path]::GetFullPath((Join-Path $tempRoot "ember-water-lab-d97c"))
if (-not $runtime.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Water Lab runtime escaped the temporary directory: $runtime"
}

foreach ($directory in @("scenes", "tools", "materials", "shaders", "scripts")) {
    New-Item -ItemType Directory -Path (Join-Path $runtime $directory) -Force | Out-Null
}

Copy-Item -LiteralPath (Join-Path $projectRoot "scenes\water_lab.tscn") -Destination (Join-Path $runtime "scenes\water_lab.tscn") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "tools\water_lab.gd") -Destination (Join-Path $runtime "tools\water_lab.gd") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "tools\test_water_lab.gd") -Destination (Join-Path $runtime "tools\test_water_lab.gd") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "tools\water_lab_projection.gd") -Destination (Join-Path $runtime "tools\water_lab_projection.gd") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "scripts\ember_water_contact_3d.gd") -Destination (Join-Path $runtime "scripts\ember_water_contact_3d.gd") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "scripts\ember_water_collision_footprint.gd") -Destination (Join-Path $runtime "scripts\ember_water_collision_footprint.gd") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "materials\ember_voxel_surface_water.tres") -Destination (Join-Path $runtime "materials\ember_voxel_surface_water.tres") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "materials\ember_voxel_surface_foam.tres") -Destination (Join-Path $runtime "materials\ember_voxel_surface_foam.tres") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "materials\ember_water_contact.tres") -Destination (Join-Path $runtime "materials\ember_water_contact.tres") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "materials\ember_water_wake.tres") -Destination (Join-Path $runtime "materials\ember_water_wake.tres") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_voxel_surface_water.gdshader") -Destination (Join-Path $runtime "shaders\ember_voxel_surface_water.gdshader") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_voxel_surface_water.gdshader.uid") -Destination (Join-Path $runtime "shaders\ember_voxel_surface_water.gdshader.uid") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_voxel_surface_foam.gdshader") -Destination (Join-Path $runtime "shaders\ember_voxel_surface_foam.gdshader") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_voxel_surface_foam.gdshader.uid") -Destination (Join-Path $runtime "shaders\ember_voxel_surface_foam.gdshader.uid") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_water_wave.gdshaderinc") -Destination (Join-Path $runtime "shaders\ember_water_wave.gdshaderinc") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_water_contact.gdshader") -Destination (Join-Path $runtime "shaders\ember_water_contact.gdshader") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_water_wake.gdshader") -Destination (Join-Path $runtime "shaders\ember_water_wake.gdshader") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "shaders\ember_diorama_light.gdshaderinc") -Destination (Join-Path $runtime "shaders\ember_diorama_light.gdshaderinc") -Force
$runtimeMaterial = Join-Path $runtime "materials\ember_voxel_surface_water.tres"
$materialText = [System.IO.File]::ReadAllText($runtimeMaterial)
$materialText = $materialText -replace '\[ext_resource type="Shader" uid="[^"]+" path=', '[ext_resource type="Shader" path='
[System.IO.File]::WriteAllText($runtimeMaterial, $materialText, [System.Text.UTF8Encoding]::new($false))
$runtimeFoamMaterial = Join-Path $runtime "materials\ember_voxel_surface_foam.tres"
$foamMaterialText = [System.IO.File]::ReadAllText($runtimeFoamMaterial)
$foamMaterialText = $foamMaterialText -replace '\[ext_resource type="Shader" uid="[^"]+" path=', '[ext_resource type="Shader" path='
[System.IO.File]::WriteAllText($runtimeFoamMaterial, $foamMaterialText, [System.Text.UTF8Encoding]::new($false))
$runtimeContactMaterial = Join-Path $runtime "materials\ember_water_contact.tres"
$contactMaterialText = [System.IO.File]::ReadAllText($runtimeContactMaterial)
$contactMaterialText = $contactMaterialText -replace '\[ext_resource type="Shader" uid="[^"]+" path=', '[ext_resource type="Shader" path='
[System.IO.File]::WriteAllText($runtimeContactMaterial, $contactMaterialText, [System.Text.UTF8Encoding]::new($false))

@'
; Generated Water Lab runtime. Source files are copied from the Ember worktree.
config_version=5

[application]
config/name="Ember Water Lab"
run/main_scene="res://scenes/water_lab.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[display]
window/size/viewport_width=1600
window/size/viewport_height=900
window/stretch/mode="canvas_items"

[rendering]
textures/default_filters/use_nearest_mipmap_filter=false
'@ | Set-Content -LiteralPath (Join-Path $runtime "project.godot") -Encoding UTF8

Write-Output "Water Lab prepared: $runtime"
if (-not $PrepareOnly) {
    Start-Process -FilePath $godot -ArgumentList @("--path", "`"$runtime`"")
}
