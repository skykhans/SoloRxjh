use bevy::{core_pipeline::tonemapping::Tonemapping, prelude::*, render::view::NoIndirectDrawing};

use crate::{
    app::{AppState, WorldEntity},
    data::{ExplorationConfig, ObjectKind, WorldConfig},
    gameplay::{
        collision::CollisionMap,
        exploration::{CameraRig, Player},
    },
};

pub struct WorldPlugin;

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) struct SpawnWorldSet;

impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(bevy::light::DirectionalLightShadowMap { size: 1024 });
        // Default features are disabled; register the supported GLB scene schema explicitly.
        app.register_type::<Name>()
            .register_type::<Transform>()
            .register_type::<GlobalTransform>()
            .register_type::<bevy::transform::components::TransformTreeChanged>()
            .register_type::<Visibility>()
            .register_type::<InheritedVisibility>()
            .register_type::<ViewVisibility>()
            .register_type::<Children>()
            .register_type::<ChildOf>()
            .register_type::<Mesh3d>()
            .register_type::<MeshMaterial3d<StandardMaterial>>()
            .register_type::<bevy::camera::primitives::Aabb>()
            .register_type::<bevy::gltf::GltfMeshName>()
            .register_type::<bevy::gltf::GltfMaterialName>()
            .register_type::<bevy::mesh::skinning::SkinnedMesh>()
            .register_type::<AnimationPlayer>()
            .register_type::<bevy::animation::AnimationTarget>()
            .add_systems(Startup, prepare_scene_assets)
            .add_systems(OnEnter(AppState::InGame), spawn_world.in_set(SpawnWorldSet));
    }
}

#[derive(Resource)]
struct SceneAssets {
    cube: Handle<Mesh>,
    capsule: Handle<Mesh>,
    cylinder: Handle<Mesh>,
    rock: Handle<Mesh>,
    ground: Handle<StandardMaterial>,
    valley: Handle<StandardMaterial>,
    snow: Handle<StandardMaterial>,
    stone: Handle<StandardMaterial>,
    wall: Handle<StandardMaterial>,
    roof: Handle<StandardMaterial>,
    jade: Handle<StandardMaterial>,
    wood: Handle<StandardMaterial>,
    bamboo: Handle<StandardMaterial>,
    water: Handle<StandardMaterial>,
    gold: Handle<StandardMaterial>,
    gate: Handle<StandardMaterial>,
}

fn prepare_scene_assets(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    let mut material = |r, g, b| {
        materials.add(StandardMaterial {
            base_color: Color::srgb(r, g, b),
            perceptual_roughness: 0.95,
            ..default()
        })
    };
    commands.insert_resource(SceneAssets {
        cube: meshes.add(Cuboid::default()),
        capsule: meshes.add(Capsule3d::default()),
        cylinder: meshes.add(Cylinder::new(0.5, 1.0)),
        rock: meshes.add(Sphere::new(0.5).mesh().ico(1).expect("valid rock mesh")),
        ground: material(0.30, 0.43, 0.34),
        valley: material(0.47, 0.48, 0.26),
        snow: material(0.76, 0.84, 0.86),
        stone: material(0.62, 0.63, 0.54),
        wall: material(0.83, 0.79, 0.64),
        roof: material(0.13, 0.23, 0.24),
        jade: material(0.24, 0.68, 0.58),
        wood: material(0.34, 0.23, 0.15),
        bamboo: material(0.16, 0.4, 0.18),
        water: material(0.12, 0.4, 0.56),
        gold: material(0.74, 0.53, 0.22),
        gate: material(0.65, 0.25, 0.16),
    });
}

fn spawn_world(
    mut commands: Commands,
    assets: Res<SceneAssets>,
    config: Res<WorldConfig>,
    exploration: Res<ExplorationConfig>,
    models: Option<Res<crate::presentation::ModelLibrary>>,
) {
    let spawn = Vec3::from_array(config.spawn);
    let target = spawn + Vec3::Y * exploration.player_height * 0.75;
    let rig = CameraRig::new(&exploration);
    commands.spawn((
        WorldEntity,
        Name::new("World camera"),
        Camera3d::default(),
        // wgpu 26 DX12 multi-draw validation misaligns batched indirect arguments.
        NoIndirectDrawing,
        IsDefaultUiCamera,
        Tonemapping::Reinhard,
        Transform::from_translation(rig.desired_position(target)).looking_at(target, Vec3::Y),
        DistanceFog {
            color: Color::srgb(0.45, 0.62, 0.58),
            falloff: FogFalloff::Linear {
                start: 35.0,
                end: 100.0,
            },
            ..default()
        },
    ));
    commands.insert_resource(rig);
    commands.insert_resource(CollisionMap {
        half_size: config.map_size * 0.5,
        movement: config
            .objects
            .iter()
            .filter(|object| object.kind.blocks_movement())
            .map(|object| object.bounds())
            .collect(),
        camera: config
            .objects
            .iter()
            .filter(|object| object.kind.blocks_camera())
            .map(|object| object.bounds())
            .collect(),
    });
    commands.spawn((
        WorldEntity,
        Name::new("Sun"),
        DirectionalLight {
            illuminance: 13_000.0,
            shadows_enabled: true,
            ..default()
        },
        bevy::light::CascadeShadowConfigBuilder {
            num_cascades: 1,
            maximum_distance: 36.0,
            ..default()
        }
        .build(),
        Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.85, -0.6, 0.0)),
    ));
    commands.spawn((
        WorldEntity,
        Name::new("Ground"),
        Mesh3d(assets.cube.clone()),
        MeshMaterial3d(assets.ground.clone()),
        Transform::from_xyz(0.0, -0.25, 0.0).with_scale(Vec3::new(
            config.map_size,
            0.5,
            config.map_size,
        )),
    ));
    let mut player = commands.spawn((
        WorldEntity,
        Player,
        Name::new("Fang Chen"),
        Visibility::default(),
        Transform::from_translation(spawn + Vec3::Y * exploration.player_height * 0.5),
    ));
    if let Some(models) = &models {
        player.with_children(|parent| {
            parent.spawn((
                SceneRoot(models.model("fang_chen").scene.clone()),
                crate::presentation::AnimatedModel::new("fang_chen", "fang_chen"),
                Transform::from_xyz(0.0, -exploration.player_height * 0.5, 0.0),
            ));
        });
    } else {
        // Explicit geometry for headless rule tests without an asset server.
        player.insert((
            Mesh3d(assets.capsule.clone()),
            MeshMaterial3d(assets.jade.clone()),
        ));
        player.with_children(|parent| {
            parent.spawn((
                Mesh3d(assets.cube.clone()),
                MeshMaterial3d(assets.gold.clone()),
                Transform::from_xyz(0.0, 0.2, -0.52).with_scale(Vec3::new(0.2, 0.2, 0.25)),
            ));
        });
    }
    for object in &config.objects {
        let size = Vec3::from_array(object.size);
        let mut entity = commands.spawn((
            WorldEntity,
            Name::new(object.id.clone()),
            Transform::from_translation(object.center.into()),
            Visibility::default(),
        ));
        match object.kind {
            ObjectKind::Npc if models.is_some() => {
                let library = models.as_ref().expect("model branch");
                entity.with_children(|parent| {
                    parent.spawn((
                        SceneRoot(library.model("cao_bin").scene.clone()),
                        crate::presentation::AnimatedModel::new("cao_bin", "cao_bin"),
                        Transform::from_xyz(0.0, -size.y * 0.5, 0.0),
                    ));
                });
            }
            ObjectKind::Bamboo if models.is_some() => {
                let library = models.as_ref().expect("model branch");
                entity.with_children(|parent| {
                    parent.spawn((
                        SceneRoot(library.model("linglong_bamboo").scene.clone()),
                        Transform::from_xyz(0.0, -size.y * 0.5, 0.0).with_scale(Vec3::new(
                            size.x / 0.8,
                            size.y / 7.0,
                            size.z / 0.8,
                        )),
                    ));
                });
            }
            ObjectKind::Building => {
                entity.with_children(|parent| {
                    parent.spawn((
                        Mesh3d(assets.cube.clone()),
                        MeshMaterial3d(assets.wall.clone()),
                        Transform::from_xyz(0.0, -size.y * 0.16, 0.0).with_scale(Vec3::new(
                            size.x,
                            size.y * 0.68,
                            size.z,
                        )),
                    ));
                    for side in [-1.0, 1.0] {
                        parent.spawn((
                            Mesh3d(assets.cube.clone()),
                            MeshMaterial3d(assets.roof.clone()),
                            Transform::from_xyz(side * size.x * 0.22, size.y * 0.26, 0.0)
                                .with_rotation(Quat::from_rotation_z(-side * 0.4))
                                .with_scale(Vec3::new(size.x * 0.6, 0.12, size.z)),
                        ));
                    }
                    parent.spawn((
                        Mesh3d(assets.cube.clone()),
                        MeshMaterial3d(assets.wood.clone()),
                        Transform::from_xyz(0.0, -size.y * 0.29, size.z * 0.5 + 0.005)
                            .with_scale(Vec3::new(1.2, 2.1, 0.01)),
                    ));
                    for side in [-1.0, 1.0] {
                        for x in [-0.38, 0.38] {
                            part(
                                parent,
                                &assets.cube,
                                &assets.wood,
                                Vec3::new(size.x * x, -size.y * 0.15, side * size.z * 0.49),
                                Vec3::new(0.18, size.y * 0.68, 0.18),
                            );
                        }
                        part(
                            parent,
                            &assets.cube,
                            &assets.wood,
                            Vec3::new(0.0, size.y * 0.12, side * size.z * 0.49),
                            Vec3::new(size.x * 0.98, 0.18, 0.18),
                        );
                        for x in [-0.25, 0.25] {
                            part(
                                parent,
                                &assets.cube,
                                &assets.roof,
                                Vec3::new(x * size.x, -size.y * 0.1, side * size.z * 0.5),
                                Vec3::new(1.15, 0.95, 0.025),
                            );
                            for offset in [-0.4, 0.0, 0.4] {
                                part(
                                    parent,
                                    &assets.cube,
                                    &assets.wood,
                                    Vec3::new(
                                        x * size.x + offset,
                                        -size.y * 0.1,
                                        side * size.z * 0.503,
                                    ),
                                    Vec3::new(0.045, 0.95, 0.03),
                                );
                            }
                        }
                    }
                });
            }
            ObjectKind::Fence | ObjectKind::Gate => {
                entity.with_children(|parent| {
                    let along_x = size.x > size.z;
                    let length = size.x.max(size.z);
                    let count = (length / 0.45).ceil() as usize;
                    let wood = if object.kind == ObjectKind::Gate {
                        &assets.gate
                    } else {
                        &assets.wood
                    };
                    for i in 0..=count {
                        let along =
                            -length * 0.5 + 0.12 + (length - 0.24) * i as f32 / count as f32;
                        part(
                            parent,
                            &assets.cube,
                            wood,
                            if along_x {
                                Vec3::new(along, 0.0, 0.0)
                            } else {
                                Vec3::new(0.0, 0.0, along)
                            },
                            if along_x {
                                Vec3::new(0.22, size.y, size.z * 0.65)
                            } else {
                                Vec3::new(size.x * 0.65, size.y, 0.22)
                            },
                        );
                    }
                    for y in [-0.28, 0.28] {
                        part(
                            parent,
                            &assets.cube,
                            &assets.wood,
                            Vec3::Y * size.y * y,
                            if along_x {
                                Vec3::new(length, 0.16, size.z)
                            } else {
                                Vec3::new(size.x, 0.16, length)
                            },
                        );
                    }
                    if object.kind == ObjectKind::Gate {
                        part(
                            parent,
                            &assets.cube,
                            &assets.gold,
                            Vec3::new(0.0, 0.15, size.z * 0.51),
                            Vec3::new(1.4, 0.7, 0.03),
                        );
                    }
                });
            }
            ObjectKind::Bridge => {
                entity.with_children(|parent| {
                    for i in 0..20 {
                        part(
                            parent,
                            &assets.cube,
                            &assets.wood,
                            Vec3::new(-size.x * 0.5 + size.x * (i as f32 + 0.5) / 20.0, 0.0, 0.0),
                            Vec3::new(size.x / 20.0 * 0.94, size.y, size.z),
                        );
                    }
                });
            }
            ObjectKind::ToolRack => {
                entity.with_children(|parent| {
                    for x in [-0.43, 0.43] {
                        part(
                            parent,
                            &assets.cube,
                            &assets.wood,
                            Vec3::new(size.x * x, 0.0, 0.0),
                            Vec3::new(0.16, size.y, size.z),
                        );
                    }
                    for y in [-0.25, 0.2] {
                        part(
                            parent,
                            &assets.cube,
                            &assets.wood,
                            Vec3::new(0.0, size.y * y, 0.0),
                            Vec3::new(size.x, 0.14, 0.15),
                        );
                    }
                    for x in [-0.5, 0.0, 0.5] {
                        part(
                            parent,
                            &assets.cube,
                            &assets.roof,
                            Vec3::new(x, 0.0, 0.1),
                            Vec3::new(0.08, 1.2, 0.05),
                        );
                        part(
                            parent,
                            &assets.cube,
                            &assets.gold,
                            Vec3::new(x, -0.4, 0.1),
                            Vec3::new(0.27, 0.05, 0.07),
                        );
                    }
                });
            }
            _ => {
                let (mesh, material, scale) = match object.kind {
                    ObjectKind::Bamboo => (&assets.cylinder, &assets.bamboo, size),
                    ObjectKind::Npc => (
                        &assets.capsule,
                        &assets.gold,
                        Vec3::new(size.x, size.y * 0.5, size.z),
                    ),
                    ObjectKind::Gate => (&assets.cube, &assets.gate, size),
                    ObjectKind::Fence | ObjectKind::Bridge | ObjectKind::ToolRack => {
                        (&assets.cube, &assets.wood, size)
                    }
                    ObjectKind::Water => (&assets.cube, &assets.water, size),
                    ObjectKind::BindingPoint => (&assets.cylinder, &assets.jade, size),
                    ObjectKind::Rock => (&assets.rock, &assets.stone, size),
                    ObjectKind::Path => (&assets.cube, &assets.stone, size),
                    ObjectKind::ValleyGround => (&assets.cube, &assets.valley, size),
                    ObjectKind::SnowGround => (&assets.cube, &assets.snow, size),
                    ObjectKind::Building => unreachable!("Buildings are spawned as a hierarchy"),
                };
                entity.insert((
                    Mesh3d(mesh.clone()),
                    MeshMaterial3d(material.clone()),
                    Transform::from_translation(object.center.into()).with_scale(scale),
                ));
            }
        }
    }
    info!(
        "World session created: {} configured objects",
        config.objects.len()
    );
}

fn part(
    parent: &mut ChildSpawnerCommands,
    mesh: &Handle<Mesh>,
    material: &Handle<StandardMaterial>,
    position: Vec3,
    size: Vec3,
) {
    parent.spawn((
        Mesh3d(mesh.clone()),
        MeshMaterial3d(material.clone()),
        Transform::from_translation(position).with_scale(size),
    ));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        app::LifecyclePlugin, data::load_configs, gameplay::exploration::ExplorationPlugin,
        ui::UiPlugin,
    };
    use crate::{
        app::SessionState,
        gameplay::exploration::{CollisionDebug, NearbyInteraction},
    };
    use bevy::{
        input::{
            ButtonState, InputPlugin,
            keyboard::{Key, KeyboardInput},
            mouse::{MouseMotion, MouseScrollUnit, MouseWheel},
        },
        state::app::StatesPlugin,
        time::TimeUpdateStrategy,
    };
    use std::time::Duration;

    pub(crate) fn exploration_app() -> App {
        use crate::gameplay::{combat::GameSession, config::GameRules, progress::QuestRules};
        let (world, exploration) =
            load_configs(&std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets"))
                .unwrap();
        let assets = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
        let rules = GameRules::load(&assets, &world).unwrap();
        let quests = QuestRules::load(&assets).unwrap();
        let mut app = App::new();
        app.add_plugins((MinimalPlugins, InputPlugin, StatesPlugin))
            .insert_resource(Time::<Fixed>::from_hz(60.0))
            .init_resource::<Assets<Mesh>>()
            .init_resource::<Assets<StandardMaterial>>()
            .insert_resource(world)
            .insert_resource(exploration)
            .insert_resource(rules)
            .insert_resource(quests)
            // Exploration tests include the real HUD, but deliberately omit combat ticking.
            .add_systems(
                OnEnter(AppState::InGame),
                |mut commands: Commands,
                 world: Res<WorldConfig>,
                 rules: Res<GameRules>,
                 quests: Res<QuestRules>| {
                    commands.insert_resource(GameSession::new(&world, &rules, &quests));
                },
            )
            .add_systems(OnExit(AppState::InGame), |mut commands: Commands| {
                commands.remove_resource::<GameSession>()
            })
            .add_plugins((LifecyclePlugin, WorldPlugin, UiPlugin, ExplorationPlugin));
        app.update();
        app.world_mut()
            .resource_mut::<NextState<AppState>>()
            .set(AppState::MainMenu);
        app.update();
        app
    }

    fn enter_game(app: &mut App, fps: u32) {
        app.insert_resource(TimeUpdateStrategy::ManualDuration(Duration::from_secs_f64(
            1.0 / f64::from(fps),
        )));
        app.world_mut()
            .resource_mut::<NextState<AppState>>()
            .set(AppState::InGame);
        app.update();
    }

    fn player_position(app: &mut App) -> Vec3 {
        let world = app.world_mut();
        world
            .query_filtered::<&Transform, With<Player>>()
            .single(world)
            .unwrap()
            .translation
    }

    fn key(app: &mut App, code: KeyCode, logical_key: Key, state: ButtonState) {
        app.world_mut().write_message(KeyboardInput {
            key_code: code,
            logical_key,
            state,
            text: None,
            repeat: false,
            window: Entity::PLACEHOLDER,
        });
    }

    #[test]
    fn fixed_movement_matches_at_30_60_144_fps_and_diagonal_speed() {
        for (run, diagonal, expected) in [
            (false, false, 40.0),
            (true, false, 65.0),
            (false, true, 40.0),
        ] {
            let mut distances = Vec::new();
            for fps in [30, 60, 144] {
                let mut app = exploration_app();
                enter_game(&mut app, fps);
                let start = player_position(&mut app);
                let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
                keys.press(KeyCode::KeyW);
                if run {
                    keys.press(KeyCode::ShiftLeft);
                }
                if diagonal {
                    keys.press(KeyCode::KeyD);
                }
                for _ in 0..fps * 10 {
                    app.update();
                }
                let distance = player_position(&mut app).distance(start);
                assert!(
                    (distance - expected).abs() < 0.12,
                    "{fps} FPS: {distance}, expected {expected}"
                );
                distances.push(distance);
            }
            assert!(
                distances.iter().all(|d| (d - distances[0]).abs() < 0.12),
                "{distances:?}"
            );
        }
    }

    #[test]
    fn pause_freezes_movement_camera_and_released_keys_do_not_drift_on_resume() {
        let mut app = exploration_app();
        let menu_count = app.world().entities().len();
        enter_game(&mut app, 60);
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(KeyCode::KeyW);
        for _ in 0..60 {
            app.update();
        }
        assert!(player_position(&mut app).z < 20.1);
        key(&mut app, KeyCode::Escape, Key::Escape, ButtonState::Pressed);
        app.update();
        app.update();
        assert_eq!(
            *app.world().resource::<State<SessionState>>().get(),
            SessionState::Paused
        );
        let position = player_position(&mut app);
        let camera = {
            let world = app.world_mut();
            *world
                .query_filtered::<&Transform, With<Camera3d>>()
                .single(world)
                .unwrap()
        };
        let yaw = app.world().resource::<CameraRig>().yaw;
        app.world_mut()
            .resource_mut::<ButtonInput<MouseButton>>()
            .press(MouseButton::Right);
        key(
            &mut app,
            KeyCode::KeyW,
            Key::Character("w".into()),
            ButtonState::Released,
        );
        key(
            &mut app,
            KeyCode::Escape,
            Key::Escape,
            ButtonState::Released,
        );
        for _ in 0..60 {
            app.world_mut().write_message(MouseMotion {
                delta: Vec2::splat(100.0),
            });
            app.update();
        }
        assert_eq!(player_position(&mut app), position);
        assert_eq!(app.world().resource::<CameraRig>().yaw, yaw);
        {
            let world = app.world_mut();
            assert_eq!(
                *world
                    .query_filtered::<&Transform, With<Camera3d>>()
                    .single(world)
                    .unwrap(),
                camera
            );
        }
        key(&mut app, KeyCode::Escape, Key::Escape, ButtonState::Pressed);
        for _ in 0..10 {
            app.update();
        }
        assert_eq!(
            *app.world().resource::<State<SessionState>>().get(),
            SessionState::Playing
        );
        assert_eq!(player_position(&mut app), position);
        app.world_mut()
            .resource_mut::<NextState<SessionState>>()
            .set(SessionState::Paused);
        app.update();
        app.world_mut()
            .resource_mut::<NextState<AppState>>()
            .set(AppState::MainMenu);
        app.update();
        assert_eq!(
            app.world().entities().len(),
            menu_count,
            "pause UI or world children remain"
        );
    }

    #[test]
    fn mouse_orbit_zoom_and_debug_use_input_messages_and_clamp() {
        let mut app = exploration_app();
        enter_game(&mut app, 60);
        app.world_mut()
            .resource_mut::<ButtonInput<MouseButton>>()
            .press(MouseButton::Right);
        app.world_mut().write_message(MouseMotion {
            delta: Vec2::new(80.0, 10000.0),
        });
        app.world_mut().write_message(MouseWheel {
            unit: MouseScrollUnit::Line,
            x: 0.0,
            y: 100.0,
            window: Entity::PLACEHOLDER,
        });
        key(&mut app, KeyCode::F3, Key::F3, ButtonState::Pressed);
        app.update();
        let rig = app.world().resource::<CameraRig>();
        let config = app.world().resource::<ExplorationConfig>();
        assert!((rig.yaw - (-0.32_f32).rem_euclid(std::f32::consts::TAU)).abs() < 1e-5);
        assert_eq!(rig.pitch, config.camera.max_pitch.to_radians());
        assert_eq!(rig.distance, config.camera.min_distance);
        assert!(app.world().resource::<CollisionDebug>().0);
        app.world_mut().write_message(MouseMotion {
            delta: Vec2::new(0.0, -10000.0),
        });
        app.world_mut().write_message(MouseWheel {
            unit: MouseScrollUnit::Pixel,
            x: 0.0,
            y: -40000.0,
            window: Entity::PLACEHOLDER,
        });
        app.update();
        let rig = app.world().resource::<CameraRig>();
        let config = app.world().resource::<ExplorationConfig>();
        assert_eq!(rig.pitch, config.camera.min_pitch.to_radians());
        assert_eq!(rig.distance, config.camera.max_distance);
    }

    #[test]
    fn configured_map_blocks_gate_water_and_wall_but_allows_bridge_and_nearby() {
        let mut app = exploration_app();
        enter_game(&mut app, 60);
        let scenarios = [
            (Vec3::new(-42.0, 0.85, -20.0), KeyCode::KeyW, -22.35, false),
            (Vec3::new(40.0, 0.85, 10.0), KeyCode::KeyD, 42.65, true),
            (Vec3::new(40.0, 0.85, 0.0), KeyCode::KeyD, 48.0, true),
            (Vec3::new(-12.0, 0.85, 14.0), KeyCode::KeyW, 9.85, false),
        ];
        for (start, code, expected, x_axis) in scenarios {
            let world = app.world_mut();
            world
                .query_filtered::<&mut Transform, With<Player>>()
                .single_mut(world)
                .unwrap()
                .translation = start;
            world.resource_mut::<ButtonInput<KeyCode>>().reset_all();
            world.resource_mut::<ButtonInput<KeyCode>>().press(code);
            for _ in 0..120 {
                app.update();
            }
            let position = player_position(&mut app);
            let actual = if x_axis { position.x } else { position.z };
            assert!(
                (actual - expected).abs() < 0.08,
                "{start:?}: {position:?}, expected {expected}"
            );
        }
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .reset_all();
        {
            let world = app.world_mut();
            world
                .query_filtered::<&mut Transform, With<Player>>()
                .single_mut(world)
                .unwrap()
                .translation = Vec3::new(4.0, 0.85, 16.0);
        }
        app.update();
        assert_eq!(
            app.world()
                .resource::<NearbyInteraction>()
                .0
                .as_ref()
                .unwrap()
                .id,
            "cao_bin"
        );
        {
            let world = app.world_mut();
            world
                .query_filtered::<&mut Transform, With<Player>>()
                .single_mut(world)
                .unwrap()
                .translation
                .z = 17.0;
        }
        app.update();
        assert!(app.world().resource::<NearbyInteraction>().0.is_none());
    }

    #[test]
    fn exploration_route_reaches_all_areas_without_teleport_or_penetration() {
        fn assert_clear(app: &mut App) {
            let position = player_position(app);
            let camera = {
                let world = app.world_mut();
                world
                    .query_filtered::<&Transform, With<Camera3d>>()
                    .single(world)
                    .unwrap()
                    .translation
            };
            let map = app.world().resource::<CollisionMap>();
            let radius = app.world().resource::<ExplorationConfig>().player_radius;
            assert!(
                map.movement
                    .iter()
                    .all(|b| !b.overlaps_circle(position.xz(), radius)),
                "player penetrated at {position:?}"
            );
            assert!(
                map.camera
                    .iter()
                    .all(|b| !(camera.cmpgt(b.min).all() && camera.cmplt(b.max).all())),
                "camera entered an obstacle at {camera:?}"
            );
        }

        fn walk_to(app: &mut App, destination: Vec2) {
            for _ in 0..1800 {
                let delta = destination - player_position(app).xz();
                if delta.length() < 0.12 {
                    app.world_mut()
                        .resource_mut::<ButtonInput<KeyCode>>()
                        .reset_all();
                    app.update();
                    assert_clear(app);
                    return;
                }
                let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
                keys.reset_all();
                if delta.x.abs() > 0.05 {
                    keys.press(if delta.x > 0.0 {
                        KeyCode::KeyD
                    } else {
                        KeyCode::KeyA
                    });
                }
                if delta.y.abs() > 0.05 {
                    keys.press(if delta.y > 0.0 {
                        KeyCode::KeyS
                    } else {
                        KeyCode::KeyW
                    });
                }
                app.update();
                assert_clear(app);
            }
            panic!(
                "Route blocked before {destination:?}, player at {:?}",
                player_position(app)
            );
        }

        let mut app = exploration_app();
        enter_game(&mut app, 60);
        let start = player_position(&mut app);
        let mut visited_bamboo = std::collections::HashSet::new();
        for (x, z, nearby) in [
            (0.0, 16.0, None),
            (4.0, 16.0, Some("cao_bin")),
            (0.0, 16.0, None),
            (-8.0, 16.0, Some("tool_rack")),
            (0.0, 16.0, None),
            (0.0, 8.0, None),
            (22.0, 8.0, None),
            (27.0, 8.0, None),
            (27.0, -8.0, Some("sword_binding_point")),
            (27.0, -16.0, None),
            (30.0, -18.8, None),
            (34.0, -18.8, None),
            (36.0, -22.8, None),
            (40.0, -22.8, None),
            (40.0, -27.0, None),
            (30.0, -27.0, None),
            (30.0, -28.8, None),
            (34.0, -28.8, None),
            (38.0, -32.8, None),
            (27.0, -32.8, None),
            (25.0, -36.8, None),
            (28.0, -36.8, None),
            (28.0, -41.0, None),
            (34.0, -42.8, None),
            (40.0, -42.8, None),
            (40.0, 0.0, None),
            (52.0, 0.0, None),
            (40.0, 0.0, None),
            (22.0, 0.0, None),
            (22.0, 8.0, None),
            (0.0, 8.0, None),
            (0.0, -18.0, None),
            (-42.0, -21.0, Some("challenge_gate")),
        ] {
            walk_to(&mut app, Vec2::new(x, z));
            let position = player_position(&mut app).xz();
            for object in &app.world().resource::<WorldConfig>().objects {
                if object.kind == ObjectKind::Bamboo
                    && object.id.starts_with("bamboo_")
                    && position.distance(Vec3::from_array(object.center).xz()) <= 2.5
                {
                    visited_bamboo.insert(object.id.clone());
                }
            }
            if let Some(expected) = nearby {
                assert_eq!(
                    app.world()
                        .resource::<NearbyInteraction>()
                        .0
                        .as_ref()
                        .map(|n| n.id.as_str()),
                    Some(expected)
                );
            }
        }
        for index in 1..=6 {
            assert!(visited_bamboo.contains(&format!("bamboo_{index:02}")));
        }
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(KeyCode::KeyW);
        for _ in 0..120 {
            app.update();
            assert_clear(&mut app);
        }
        assert!((player_position(&mut app).z + 22.35).abs() < 0.01);
        for waypoint in [Vec2::new(-42.0, -20.0), Vec2::new(0.0, -20.0), start.xz()] {
            walk_to(&mut app, waypoint);
        }
        for point in [
            (0.0, 8.0),
            (22.0, 8.0),
            (22.0, 0.0),
            (85.0, 0.0),
            (120.0, 0.0),
            (120.0, -42.0),
            (120.0, 0.0),
            (22.0, 0.0),
            (22.0, 8.0),
            (0.0, 8.0),
            (0.0, -92.0),
            (0.0, -140.0),
            (0.0, -30.0),
            (0.0, 24.0),
        ] {
            walk_to(&mut app, Vec2::from(point));
        }
        assert!(player_position(&mut app).distance(start) < 0.12);
    }

    #[test]
    fn ten_sessions_remove_all_roots_children_and_session_resources() {
        let mut app = exploration_app();
        let menu_entities = app.world().entities().len();
        let mut previous_count = None;
        for _ in 0..10 {
            app.world_mut()
                .resource_mut::<NextState<AppState>>()
                .set(AppState::InGame);
            app.update();
            let count = app.world().entities().len();
            assert!(count > menu_entities);
            let world = app.world_mut();
            assert_eq!(world.query::<&Camera3d>().iter(world).count(), 1);
            assert_eq!(world.query::<&Camera>().iter(world).count(), 1);
            assert_eq!(world.query::<&DirectionalLight>().iter(world).count(), 1);
            assert_eq!(world.query::<&Player>().iter(world).count(), 1);
            if let Some(previous) = previous_count {
                assert_eq!(count, previous);
            }
            previous_count = Some(count);
            app.world_mut()
                .resource_mut::<NextState<AppState>>()
                .set(AppState::MainMenu);
            app.update();
            let world = app.world_mut();
            assert_eq!(
                world
                    .query_filtered::<Entity, With<WorldEntity>>()
                    .iter(world)
                    .count(),
                0
            );
            assert_eq!(
                world.entities().len(),
                menu_entities,
                "orphaned children remain"
            );
            assert_eq!(world.query::<&Camera>().iter(world).count(), 1);
            assert!(!world.contains_resource::<CameraRig>());
            assert!(!world.contains_resource::<CollisionMap>());
            assert!(!world.contains_resource::<State<crate::app::SessionState>>());
        }
    }
}
