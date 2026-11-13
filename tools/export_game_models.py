"""Original low-poly characters and beasts. Blender 4.5 LTS, metres, +Y forward.
Run: blender --background --factory-startup --python tools/export_game_models.py
"""
from pathlib import Path
import math
import bpy

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets" / "models" / "characters"
DEST.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, 61


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
    m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = .85
    return m


skin = mat("Warm skin", (.72, .47, .30))
hair = mat("Ink hair", (.035, .046, .049))
jade = mat("Servant teal cloth", (.12, .35, .31))
navy = mat("Dark robe", (.07, .12, .14))
paper = mat("Linen", (.78, .72, .55))
leather = mat("Worn leather", (.22, .13, .075))
metal = mat("Dark floating immortal sword", (.09, .12, .13))
edge = mat("Sword edge", (.72, .84, .88))
rust = mat("Rust", (.41, .20, .08))
red = mat("Steward ochre", (.48, .25, .11))
boar_mat = mat("Wild boar hide", (.26, .14, .09))
wolf_mat = mat("Mountain wolf fur", (.32, .39, .40))
boss_mat = mat("Bamboo beast hide", (.33, .10, .075))


def shape(name, location, scale, material, kind="box", rotation=(0, 0, 0)):
    if kind == "ico":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=location)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=.5, radius2=0, depth=1, location=location)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(material)
    return obj


def armature(name, bones):
    bpy.ops.object.armature_add(enter_editmode=True)
    rig = bpy.context.object
    rig.name = name
    rig.data.edit_bones.remove(rig.data.edit_bones[0])
    for bone_name, head, tail, parent in bones:
        bone = rig.data.edit_bones.new(bone_name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = rig.data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
    return rig


def bind(obj, rig, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    obj.modifiers.new("Rigid cloth skin", "ARMATURE").object = rig
    obj.parent = rig


def animate(rig, name, duration, poses):
    rig.animation_data_create()
    action = bpy.data.actions.new(rig.name + "_" + name)
    rig.animation_data.action = action
    for fraction, changes in poses:
        for bone in rig.pose.bones:
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
        for bone_name, angles in changes.items():
            rig.pose.bones[bone_name].rotation_euler = tuple(math.radians(x) for x in angles)
        frame = 1 + fraction * duration * 30
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame)
            bone.keyframe_insert("location", frame=frame)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)


def export(name, rig, objects):
    merged = []
    groups = [(sword, [obj for obj in objects if obj.name.startswith("Sword") == sword])
        for sword in [False, True]]
    for sword, group in groups:
        if not group:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in group:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()
        combined = bpy.context.object
        combined.name = "Sword" if sword else name + "_Body"
        merged.append(combined)
    objects = merged
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig, *objects]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    scene.frame_set(1)
    bpy.ops.export_scene.gltf(filepath=str(DEST / (name + ".glb")), export_format="GLB",
        use_selection=True, export_yup=True, export_animations=True, export_skins=True,
        export_animation_mode="NLA_TRACKS", export_force_sampling=True)
    print("GAME_MODEL_EXPORTED", name)


def human(name, steward=False):
    bones = [
        ("Root", (0, 0, 0), (0, 0, .8), None),
        ("Chest", (0, 0, .8), (0, 0, 1.24), "Root"),
        ("Head", (0, 0, 1.25), (0, 0, 1.7), "Chest"),
        ("ArmL", (-.32, 0, 1.24), (-.32, 0, .78), "Chest"),
        ("ArmR", (.32, 0, 1.24), (.32, 0, .78), "Chest"),
        ("LegL", (-.14, 0, .78), (-.14, 0, .12), "Root"),
        ("LegR", (.14, 0, .78), (.14, 0, .12), "Root"),
    ]
    if not steward:
        bones.append(("WristR", (.34, .015, .77), (.34, .015, .65), "ArmR"))
    rig = armature(name, bones)
    parts = []
    def part(label, center, scale, material, bone, kind="box", rotation=(0,0,0)):
        obj = shape(label, center, scale, material, kind, rotation)
        bind(obj, rig, bone)
        parts.append(obj)
        return obj
    cloth = red if steward else jade
    for sign, side in [(-1, "L"), (1, "R")]:
        part("Boot"+side, (sign*.14, .035, .12), (.21,.34,.24), leather, "Leg"+side)
        part("Trouser"+side, (sign*.14, 0, .44), (.20,.24,.48), navy, "Leg"+side)
        part("Sleeve"+side, (sign*.34, 0, 1.02), (.20,.27,.45), cloth, "Arm"+side)
        hand_bone = "WristR" if side == "R" and not steward else "Arm"+side
        part("Hand"+side, (sign*.34, .015, .77), (.16,.18,.16), skin, hand_bone, "ico")
    part("RobeSkirt", (0,0,.78), (.52,.35,.35), cloth, "Root")
    part("RobeChest", (0,0,1.08), (.51,.32,.42), cloth, "Chest")
    part("Belt", (0,.01,.90), (.54,.36,.075), leather, "Chest")
    part("BeltKnot", (.04,.20,.89), (.08,.08,.13), paper, "Chest")
    part("CollarL", (-.07,.17,1.19), (.08,.025,.25), paper, "Chest", rotation=(0,.0,-.4))
    part("CollarR", (.07,.18,1.19), (.08,.025,.25), paper, "Chest", rotation=(0,.0,.4))
    part("Face", (0,0,1.44), (.24,.23,.25), skin, "Head", "ico")
    part("Hair", (0,-.03,1.57), (.245,.22,.16), hair, "Head", "ico")
    part("Topknot", (0,-.02,1.72), (.11,.12,.10), hair, "Head", "ico")
    part("HairTie", (0,0,1.66), (.12,.12,.035), paper, "Head")
    for sign in [-1,1]:
        part("Eye", (sign*.085,.205,1.49), (.045,.018,.028), hair, "Head")
    part("Nose", (0,.235,1.42), (.045,.04,.065), skin, "Head")
    if steward:
        part("Beard", (0,.16,1.29), (.10,.08,.15), hair, "Head", "cone", (math.pi,0,0))
    else:
        part("MendedPatch", (-.14,.173,1.0), (.13,.015,.11), paper, "Chest")
        part("SwordGrip", (.34,.14,.77), (.06,.26,.06), leather, "WristR")
        part("SwordGuard", (.34,.30,.77), (.22,.05,.04), rust, "WristR")
        part("SwordBlade", (.34,.86,.77), (.10,1.1,.04), metal, "WristR")
        part("SwordEdge", (.285,.86,.77), (.02,1.1,.042), edge, "WristR")
        part("SwordRust", (.34,.55,.795), (.07,.14,.008), rust, "WristR")
    hold = {} if steward else {"ArmR":(20,0,-10),"WristR":(-30,0,0)}
    animate(rig, "Idle", 2.0, [(0,hold),(.5,{**hold,"Chest":(2,0,0)}),(1,hold)])
    if steward:
        export(name,rig,parts)
        return
    for action, duration, angle in [("Walk",.8,25),("Run",.55,40)]:
        animate(rig, action, duration, [(0,{**hold,"LegL":(angle,0,0),"LegR":(-angle,0,0),"ArmL":(-angle,0,0),"ArmR":(20+angle*.3,0,-10)}),
            (.5,{**hold,"LegL":(-angle,0,0),"LegR":(angle,0,0),"ArmL":(angle,0,0),"ArmR":(20-angle*.3,0,-10)}),
            (1,{**hold,"LegL":(angle,0,0),"LegR":(-angle,0,0),"ArmL":(-angle,0,0),"ArmR":(20+angle*.3,0,-10)})])
    # Upright bones turn about local Y; local Z would bend the torso sideways.
    # Wrist counter-rotation keeps the blade level while the arm lifts forward.
    for i, angle in [(1,55),(2,-65),(3,90)]:
        strike = {"ArmR":(65,0,-10),"WristR":(-65,0,0)}
        animate(rig, "Attack"+str(i), .4, [(0,{**strike,"Chest":(0,-angle*.6,0)}),
            (.45,{**strike,"Chest":(0,angle*.6,0)}),(1,hold)])
    sweep = {"ArmR":(70,0,-10),"WristR":(-70,0,0)}
    animate(rig,"Energy",.6,[(0,{**sweep,"Chest":(0,-55,0)}),(.42,{**sweep,"Chest":(0,55,0)}),(1,hold)])
    animate(rig,"Piercing",.65,[(0,{"Chest":(0,-15,0),"ArmR":(25,0,0),"WristR":(-25,0,0)}),
        (.38,{"Chest":(-10,0,0),"ArmR":(85,0,0),"WristR":(-75,0,0),"LegL":(25,0,0)}),(1,hold)])
    animate(rig,"Guard",.5,[(0,hold),(.4,{"ArmR":(70,0,25),"WristR":(-30,0,0),"ArmL":(70,0,-25),"Chest":(0,8,0)}),
        (1,{"ArmR":(60,0,20),"WristR":(-20,0,0),"ArmL":(60,0,-20)})])
    animate(rig,"Mend",.7,[(0,hold),(.43,{"ArmL":(80,0,-15),"ArmR":(35,0,-15),"WristR":(-50,0,0),"Head":(-10,0,0)}),(1,hold)])
    animate(rig,"Dodge",.6,[(0,hold),(.5,{**hold,"Root":(-40,0,0),"LegL":(-50,0,0),"LegR":(50,0,0)}),(1,hold)])
    animate(rig,"Hit",.3,[(0,hold),(.3,{**hold,"Chest":(-18,0,0)}),(1,hold)])
    animate(rig,"Death",.8,[(0,hold),(.7,{**hold,"Root":(-85,0,0)}),(1,{**hold,"Root":(-85,0,0)})])
    animate(rig,"Bind",1.2,[(0,hold),(.5,{"ArmR":(70,0,0),"WristR":(-70,0,0),"ArmL":(50,0,0)}),(1,hold)])
    export(name,rig,parts)


def beast(name, kind):
    scale = 2.1 if kind == "boss" else 1.0
    rig = armature(name, [("Root",(0,0,0),(0,0,.6),None),
        ("Head",(0,.5,.6),(0,.9,.8),"Root"),
        ("FrontL",(-.25,.4,.5),(-.25,.4,.1),"Root"),
        ("FrontR",(.25,.4,.5),(.25,.4,.1),"Root"),
        ("BackL",(-.25,-.4,.5),(-.25,-.4,.1),"Root"),
        ("BackR",(.25,-.4,.5),(.25,-.4,.1),"Root"),
        ("Tail",(0,-.6,.6),(0,-1,.6),"Root")])
    parts=[]
    material = wolf_mat if kind == "wolf" else boss_mat if kind == "boss" else boar_mat
    def part(label,center,size,mat,bone,shape_kind="ico",rotation=(0,0,0)):
        obj=shape(label,center,size,mat,shape_kind,rotation)
        bind(obj,rig,bone); parts.append(obj)
    wolf = kind == "wolf"
    part("Body",(0,0,.63),(.36 if wolf else .45,.68,.33 if wolf else .43),material,"Root")
    part("Head",(0,.63,.77 if wolf else .60),(.27,.32,.30),material,"Head")
    part("Muzzle",(0,.91,.70 if wolf else .48),(.20,.28,.15),paper if wolf else leather,"Head")
    part("Nose",(0,1.10,.70 if wolf else .48),(.12,.06,.09),hair,"Head")
    for side,sign in [("L",-1),("R",1)]:
        for prefix,y in [("Front",.4),("Back",-.4)]:
            part(prefix+side,(sign*.25,y,.25),(.12,.13,.25),material,prefix+side,"box")
            part("Paw",(sign*.25,y+.05,.07),(.18,.23,.14),hair,prefix+side,"box")
        part("Ear",(sign*.19,.58,1.0 if wolf else .86),(.20,.16,.32),material,"Head","cone")
        part("Eye",(sign*.20,.85,.82 if wolf else .67),(.04,.045,.035),hair,"Head","box")
        if not wolf:
            part("Tusk",(sign*.21,.94,.48),(.10,.10,.30),paper,"Head","cone",(.0,sign*.3,0))
    part("Tail",(0,-.84,.72),(.13,.42,.14),material,"Tail")
    if kind == "boss":
        for sign in [-1,1]:
            part("Horn",(sign*.22,.52,1.12),(.18,.18,.6),rust,"Head","cone",(0,sign*.3,0))
        part("Crest",(0,-.05,1.0),(.12,.65,.24),hair,"Root","box")
    # Apply global size to rig and meshes together before export.
    rig.scale=(scale,scale,scale)
    animate(rig,"Idle",2,[(0,{}),(.5,{"Head":(3,0,0)}),(1,{})])
    animate(rig,"Walk",.65,[(0,{"FrontL":(30,0,0),"BackR":(30,0,0),"FrontR":(-30,0,0),"BackL":(-30,0,0)}),
        (.5,{"FrontL":(-30,0,0),"BackR":(-30,0,0),"FrontR":(30,0,0),"BackL":(30,0,0)}),
        (1,{"FrontL":(30,0,0),"BackR":(30,0,0),"FrontR":(-30,0,0),"BackL":(-30,0,0)})])
    animate(rig,"Attack",.6,[(0,{}),(.5,{"Head":(-35,0,0)}),(1,{"Head":(25,0,0)})])
    if kind == "boss":
        animate(rig,"Heavy",1.2,[(0,{}),(.7,{"Root":(-25,0,0),"FrontL":(-50,0,0),"FrontR":(-50,0,0)}),(1,{"Root":(15,0,0)})])
    animate(rig,"Hit",.3,[(0,{}),(.5,{"Head":(-15,0,10)}),(1,{})])
    animate(rig,"Death",.7,[(0,{}),(.7,{"Root":(0,85,0)}),(1,{"Root":(0,85,0)})])
    export(name,rig,parts)


human("fang_chen")
human("cao_bin",True)
beast("boar","boar")
beast("mountain_wolf","wolf")
beast("bamboo_beast","boss")

# A reusable authored bamboo cluster. Leaves are visual foliage, not solid walls.
bamboo_mat = mat("Jade bamboo stem", (.18,.38,.12))
leaf_mat = mat("Jade bamboo leaves", (.16,.43,.20))
ring_mat = mat("Bamboo nodes", (.40,.53,.19))
parts = [shape("BambooStem",(0,0,3.5),(.35,.35,7),bamboo_mat)]
for z in [1,2,3,4,5,6]:
    parts.append(shape("BambooNode",(0,0,z),(.39,.39,.06),ring_mat))
for z,side in [(4.5,-1),(5,1),(5.5,-1),(6,1),(6.5,-1),(6.7,1)]:
    parts.append(shape("Leaf",(side*.7,.15,z),(1.0,.22,.08),leaf_mat,"ico",(0,side*.35,side*.22)))
    parts.append(shape("Leaf",(side*.5,-.35,z-.15),(.8,.20,.07),leaf_mat,"ico",(0,side*.4,-side*.3)))
bpy.ops.object.select_all(action="DESELECT")
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join()
bpy.context.object.name="LinglongBamboo"
bpy.ops.export_scene.gltf(filepath=str(DEST / "linglong_bamboo.glb"),export_format="GLB",use_selection=True,export_yup=True,export_animations=False)
# Retain the complete editable source, with rigs and named NLA tracks.
bpy.ops.wm.save_as_mainfile(filepath=str(DEST / "characters.blend"))
