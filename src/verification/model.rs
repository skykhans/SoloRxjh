use bevy::{
    asset::LoadState,
    gltf::{Gltf, GltfNode},
    mesh::skinning::{SkinnedMesh, SkinnedMeshInverseBindposes},
    prelude::*,
    scene::SceneInstanceReady,
};

use crate::app::WorldEntity;

const MODEL: &str = "models/probes/animation_probe.glb";

#[derive(Resource)]
struct Probe {
    handle: Handle<Gltf>,
    spawned: bool,
    initial_rotation: Option<Quat>,
    rotation_changed: bool,
    observed_since: Option<f64>,
}

#[derive(Component)]
struct ProbeAnimation {
    graph: Handle<AnimationGraph>,
    index: AnimationNodeIndex,
}

pub(super) fn check(world: &mut World) -> Result<bool, String> {
    if !world.contains_resource::<Probe>() {
        let handle = world.resource::<AssetServer>().load(MODEL);
        world.insert_resource(Probe {
            handle,
            spawned: false,
            initial_rotation: None,
            rotation_changed: false,
            observed_since: None,
        });
    }
    let handle = world.resource::<Probe>().handle.clone();
    if let Some(LoadState::Failed(error)) =
        world.resource::<AssetServer>().get_load_state(handle.id())
    {
        return Err(format!("{MODEL}: {error}"));
    }
    if !world
        .resource::<AssetServer>()
        .is_loaded_with_dependencies(handle.id())
    {
        return Ok(false);
    }
    if !world.resource::<Probe>().spawned {
        let gltfs = world.resource::<Assets<Gltf>>();
        let gltf = gltfs.get(&handle).ok_or("Loaded GLB asset is absent")?;
        let scene = gltf
            .named_scenes
            .get("Scene")
            .ok_or("GLB has no Scene")?
            .clone();
        let clip = gltf
            .named_animations
            .get("ProbeWave")
            .ok_or("GLB has no ProbeWave animation")?
            .clone();
        if gltf.skins.len() != 1 || gltf.meshes.len() != 5 {
            return Err("GLB skin or mesh count does not match the Blender fixture".into());
        }
        let nodes = world.resource::<Assets<GltfNode>>();
        for (name, expected) in [
            ("BasisRight", Vec3::new(1.0, 0.1, 0.0)),
            ("BasisForward", Vec3::new(0.0, 0.1, -1.0)),
            ("BasisUp", Vec3::new(0.0, 2.5, 0.0)),
            ("Upper", Vec3::Y),
        ] {
            let node = gltf
                .named_nodes
                .get(name)
                .and_then(|h| nodes.get(h))
                .ok_or_else(|| format!("GLB node missing: {name}"))?;
            if node.transform.translation.distance(expected) > 1e-4 {
                return Err(format!("GLB coordinate mismatch: {name}"));
            }
        }
        let (graph, index) = AnimationGraph::from_clip(clip);
        let graph = world.resource_mut::<Assets<AnimationGraph>>().add(graph);
        world
            .spawn((
                WorldEntity,
                Name::new("Blender animation probe"),
                SceneRoot(scene),
                Visibility::default(),
                Transform::from_xyz(2.5, 0.0, 21.0),
                ProbeAnimation { graph, index },
            ))
            .observe(play_when_ready);
        world.resource_mut::<Probe>().spawned = true;
        return Ok(false);
    }
    let root = world
        .query_filtered::<Entity, With<ProbeAnimation>>()
        .single(world)
        .map_err(|e| e.to_string())?;
    let descendants = world
        .query::<&Children>()
        .query(world)
        .iter_descendants(root)
        .collect::<std::collections::HashSet<_>>();
    let skins: Vec<_> = descendants
        .iter()
        .filter_map(|e| world.get::<SkinnedMesh>(*e))
        .cloned()
        .collect();
    if skins.len() != 2 {
        return Ok(false);
    }
    for skin in &skins {
        let bindposes = world
            .resource::<Assets<SkinnedMeshInverseBindposes>>()
            .get(&skin.inverse_bindposes)
            .ok_or("GLB inverse bindposes missing")?;
        if skin.joints.len() != 2
            || bindposes.len() != 2
            || bindposes.iter().any(|m| !m.is_finite())
        {
            return Err("GLB must have two valid joints and inverse bindposes".into());
        }
    }
    for (entity, name, parent) in world
        .query_filtered::<(Entity, &Name, &ChildOf), With<InheritedVisibility>>()
        .iter(world)
    {
        if descendants.contains(&entity)
            && world.get::<InheritedVisibility>(parent.parent()).is_none()
        {
            return Err(format!(
                "GLB visibility hierarchy is incomplete above {name}"
            ));
        }
    }
    let rotation = world
        .query::<(Entity, &Name, &Transform)>()
        .iter(world)
        .find_map(|(entity, name, t)| {
            (descendants.contains(&entity) && name.as_str() == "Upper").then_some(t.rotation)
        })
        .ok_or("GLB Upper joint missing")?;
    let now = world.resource::<Time>().elapsed_secs_f64();
    let mut probe = world.resource_mut::<Probe>();
    if let Some(initial) = probe.initial_rotation {
        probe.rotation_changed |= initial.angle_between(rotation) > 0.1;
    } else {
        probe.initial_rotation = Some(rotation);
        probe.observed_since = Some(now);
    }
    if now
        - probe
            .observed_since
            .expect("Observation start set with initial rotation")
        < 2.2
    {
        return Ok(false);
    }
    if !probe.rotation_changed {
        return Err("GLB animation did not change the Upper joint rotation".into());
    }
    Ok(true)
}

fn play_when_ready(
    ready: On<SceneInstanceReady>,
    mut commands: Commands,
    children: Query<&Children>,
    probes: Query<&ProbeAnimation>,
    mut players: Query<&mut AnimationPlayer>,
) {
    let Ok(probe) = probes.get(ready.entity) else {
        return;
    };
    for child in children.iter_descendants(ready.entity) {
        if let Ok(mut player) = players.get_mut(child) {
            player.play(probe.index).repeat();
            commands
                .entity(child)
                .insert(AnimationGraphHandle(probe.graph.clone()));
        }
    }
}
