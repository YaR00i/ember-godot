"""Open one Ember work copy and expose its return export in Blender."""

import sys
from pathlib import Path

import bpy


def export_clip(filepath):
    return bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        export_format="GLB",
        export_animation_mode="ACTIVE_ACTIONS",
        export_force_sampling=True,
    )


def open_copy(source, project):
    if project.is_file():
        bpy.ops.wm.open_mainfile(filepath=str(project))
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 60
    bpy.ops.import_scene.gltf(filepath=str(source))
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise RuntimeError("Expected one Mira armature")
    rig = armatures[0]
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    if rig.animation_data and rig.animation_data.action:
        start, end = rig.animation_data.action.frame_range
        bpy.context.scene.frame_start = int(start)
        bpy.context.scene.frame_end = max(int(start) + 1, round(end))
        bpy.context.scene.frame_set(int(start))
    bpy.ops.wm.save_as_mainfile(filepath=str(project))


def install_export_button(output):
    class EmberExportClip(bpy.types.Operator):
        bl_idname = "export_scene.ember_clip"
        bl_label = "Вернуть клип в Ember"

        def execute(self, _context):
            result = export_clip(output)
            if "FINISHED" in result:
                self.report({"INFO"}, "Клип готов. В Godot нажми «Вернуть из Blender».")
            return result

    class VIEW3D_PT_ember_animation(bpy.types.Panel):
        bl_label = "Ember"
        bl_space_type = "VIEW_3D"
        bl_region_type = "UI"
        bl_category = "Ember"

        def draw(self, _context):
            self.layout.operator(EmberExportClip.bl_idname)

    bpy.utils.register_class(EmberExportClip)
    bpy.utils.register_class(VIEW3D_PT_ember_animation)


if __name__ == "__main__":
    source, project, output = map(Path, sys.argv[sys.argv.index("--") + 1:])
    open_copy(source, project)
    install_export_button(output)
