"""Create an original two-bone coordinate/animation fixture in Blender 4.5 LTS.

Run: blender --background --factory-startup --python tools/export_animation_probe.py
The retained .blend and GLB are generated from this script, with no external assets.
"""
from pathlib import Path
import math
import bpy

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "models" / "probes"
DEST.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0
bpy.context.scene.render.fps = 30
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 61


def material(name, color):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    result.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1.0)
    return result


def box(name, center, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


jade = material("ProbeJade", (0.12, 0.65, 0.46))
gold = material("ProbeGold", (0.95, 0.58, 0.08))
red = material("AxisRightRed", (0.9, 0.1, 0.1))
green = material("AxisForwardGreen", (0.1, 0.9, 0.1))
blue = material("AxisUpBlue", (0.1, 0.2, 0.9))

bpy.ops.object.armature_add(enter_editmode=True)
rig = bpy.context.object
rig.name = "ProbeRig"
root = rig.data.edit_bones[0]
root.name = "Root"
root.head = (0, 0, 0)
root.tail = (0, 0, 1)
upper = rig.data.edit_bones.new("Upper")
upper.head = (0, 0, 1)
upper.tail = (0, 0, 2)
upper.parent = root
upper.use_connect = True
bpy.ops.object.mode_set(mode="OBJECT")

lower = box("Lower", (0, 0, 0.5), (0.5, 0.4, 1.0), jade)
upper_mesh = box("UpperMesh", (0, 0, 1.5), (0.7, 0.4, 1.0), gold)
for obj, bone in [(lower, "Root"), (upper_mesh, "Upper")]:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new("ProbeSkin", "ARMATURE")
    modifier.object = rig
    obj.parent = rig

box("BasisRight", (1, 0, 0.1), (0.2, 0.2, 0.2), red)
box("BasisForward", (0, 1, 0.1), (0.2, 0.2, 0.2), green)
box("BasisUp", (0, 0, 2.5), (0.2, 0.2, 0.2), blue)

bone = rig.pose.bones["Upper"]
bone.rotation_mode = "XYZ"
for frame, angle in [(1, 0), (16, 30), (31, 0), (46, -30), (61, 0)]:
    bone.rotation_euler.x = math.radians(angle)
    bone.keyframe_insert(data_path="rotation_euler", frame=frame)
rig.animation_data.action.name = "ProbeWave"
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST / "animation_probe.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(DEST / "animation_probe.glb"),
    export_format="GLB", export_yup=True,
    export_animations=True, export_skins=True,
    export_animation_mode="ACTIONS", export_frame_range=True,
    export_force_sampling=True,
)
print("PROBE_EXPORTED", DEST / "animation_probe.glb")
