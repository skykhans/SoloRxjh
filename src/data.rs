use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
};

use bevy::prelude::*;
use serde::Deserialize;

use crate::{
    app::AppState,
    gameplay::{collision::Aabb, config::GameRules, progress::QuestRules},
};

#[derive(Resource, Debug)]
pub struct RuntimePaths {
    pub assets: PathBuf,
}

impl RuntimePaths {
    pub fn resolve(explicit_assets: Option<PathBuf>) -> Result<Self, String> {
        let assets = match explicit_assets {
            Some(path) => std::path::absolute(path).map_err(|error| error.to_string())?,
            None if cfg!(debug_assertions) => {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets")
            }
            None => std::env::current_exe()
                .map_err(|error| error.to_string())?
                .parent()
                .ok_or("Executable has no parent directory")?
                .join("assets"),
        };
        Ok(Self { assets })
    }
}

#[derive(Resource, Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct WorldConfig {
    pub map_size: f32,
    pub spawn: [f32; 3],
    pub safe_zone: SafeZone,
    pub objects: Vec<WorldObject>,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct SafeZone {
    pub center: [f32; 2],
    pub radius: f32,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct WorldObject {
    pub id: String,
    pub label: String,
    pub kind: ObjectKind,
    pub center: [f32; 3],
    pub size: [f32; 3],
}

#[derive(Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObjectKind {
    Building,
    Rock,
    Fence,
    Gate,
    Water,
    Bridge,
    Path,
    ValleyGround,
    SnowGround,
    Bamboo,
    Npc,
    ToolRack,
    BindingPoint,
}

impl ObjectKind {
    pub fn blocks_movement(self) -> bool {
        !matches!(
            self,
            Self::Bridge | Self::Path | Self::ValleyGround | Self::SnowGround | Self::BindingPoint
        )
    }

    pub fn blocks_camera(self) -> bool {
        self.blocks_movement() && self != Self::Water
    }

    pub fn interactable(self) -> bool {
        matches!(
            self,
            Self::Npc | Self::ToolRack | Self::BindingPoint | Self::Gate
        )
    }
}

impl WorldObject {
    pub fn bounds(&self) -> Aabb {
        Aabb::from_center_size(self.center.into(), self.size.into())
    }
}

impl WorldConfig {
    pub fn parse(source: &str) -> Result<Self, String> {
        let config: Self = ron::from_str(source).map_err(|error| error.to_string())?;
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<(), String> {
        if !self.map_size.is_finite() || self.map_size <= 0.0 {
            return Err("map_size must be finite and positive".into());
        }
        let half = self.map_size * 0.5;
        if !self.spawn.iter().all(|value| value.is_finite())
            || self.spawn[0].abs() >= half
            || self.spawn[2].abs() >= half
            || self.spawn[1] != 0.0
        {
            return Err("spawn must lie on the ground inside the map".into());
        }
        if !self.safe_zone.radius.is_finite()
            || self.safe_zone.radius <= 0.0
            || self
                .safe_zone
                .center
                .iter()
                .any(|value| !value.is_finite() || value.abs() + self.safe_zone.radius >= half)
        {
            return Err("safe_zone must have finite coordinates and fit inside the map".into());
        }
        let mut ids = HashSet::new();
        for object in &self.objects {
            if object.id.is_empty()
                || !object
                    .id
                    .bytes()
                    .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == b'_')
                || !ids.insert(&object.id)
                || object.label.trim().is_empty()
            {
                return Err(format!(
                    "Object has an empty/invalid/duplicate id or label: {}",
                    object.id
                ));
            }
            if object.center.iter().any(|value| !value.is_finite())
                || object
                    .size
                    .iter()
                    .any(|value| !value.is_finite() || *value <= 0.0)
            {
                return Err(format!(
                    "Object coordinates and size must be finite; size must be positive: {}",
                    object.id
                ));
            }
            let bounds = object.bounds();
            if bounds.min.x < -half
                || bounds.min.z < -half
                || bounds.max.x > half
                || bounds.max.z > half
            {
                return Err(format!("Object lies outside the map: {}", object.id));
            }
        }
        Ok(())
    }

    pub fn validate_spawn(&self, exploration: &ExplorationConfig) -> Result<(), String> {
        let point = Vec3::from_array(self.spawn).xz();
        let limit = self.map_size * 0.5 - exploration.player_radius;
        if point.abs().max_element() >= limit
            || self.objects.iter().any(|object| {
                object.kind.blocks_movement()
                    && object
                        .bounds()
                        .overlaps_circle(point, exploration.player_radius)
            })
        {
            return Err("Player spawn overlaps an obstacle or map boundary".into());
        }
        if point.distance(self.safe_zone.center.into()) + exploration.player_radius
            > self.safe_zone.radius
        {
            return Err("Player spawn must be inside the safe zone".into());
        }
        Ok(())
    }
}

#[derive(Resource, Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct ExplorationConfig {
    pub walk_speed: f32,
    pub run_speed: f32,
    pub player_radius: f32,
    pub player_height: f32,
    pub interaction_distance: f32,
    pub camera: CameraConfig,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct CameraConfig {
    pub distance: f32,
    pub min_distance: f32,
    pub max_distance: f32,
    pub initial_pitch: f32,
    pub min_pitch: f32,
    pub max_pitch: f32,
    pub rotation_sensitivity: f32,
    pub scroll_sensitivity: f32,
    pub follow_sharpness: f32,
    pub margin: f32,
}

impl ExplorationConfig {
    pub fn parse(source: &str) -> Result<Self, String> {
        let config: Self = ron::from_str(source).map_err(|error| error.to_string())?;
        let camera = &config.camera;
        let positive = [
            config.walk_speed,
            config.run_speed,
            config.player_radius,
            config.player_height,
            config.interaction_distance,
            camera.distance,
            camera.min_distance,
            camera.max_distance,
            camera.initial_pitch,
            camera.min_pitch,
            camera.max_pitch,
            camera.rotation_sensitivity,
            camera.scroll_sensitivity,
            camera.follow_sharpness,
            camera.margin,
        ];
        if positive
            .iter()
            .any(|value| !value.is_finite() || *value <= 0.0)
            || config.run_speed < config.walk_speed
            || config.player_height < config.player_radius * 2.0
            || camera.min_distance > camera.distance
            || camera.distance > camera.max_distance
            || camera.min_pitch > camera.initial_pitch
            || camera.initial_pitch > camera.max_pitch
            || camera.max_pitch >= 90.0
            || camera.margin >= config.player_radius
        {
            return Err(
                "Invalid exploration speeds, player shape, camera ranges or clearance".into(),
            );
        }
        Ok(config)
    }
}

#[derive(Resource)]
pub struct LoadError(pub String);

pub struct DataPlugin;

impl Plugin for DataPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(OnEnter(AppState::Loading), load_world_config);
    }
}

fn read_source(path: &Path) -> Result<String, String> {
    fs::read_to_string(path).map_err(|error| {
        let mut reason = format!(
            "{}\nCannot read configuration: {:?}",
            path.display(),
            error.kind()
        );
        if let Some(code) = error.raw_os_error() {
            reason.push_str(&format!(" (OS error {code})"));
        }
        reason
    })
}

pub fn load_configs(assets: &Path) -> Result<(WorldConfig, ExplorationConfig), String> {
    let world_path = assets.join("config/world.ron");
    let world = WorldConfig::parse(&read_source(&world_path)?)
        .map_err(|reason| format!("{}\n{reason}", world_path.display()))?;
    let exploration_path = assets.join("config/exploration.ron");
    let exploration = ExplorationConfig::parse(&read_source(&exploration_path)?)
        .map_err(|reason| format!("{}\n{reason}", exploration_path.display()))?;
    world
        .validate_spawn(&exploration)
        .map_err(|reason| format!("{}\n{reason}", world_path.display()))?;
    Ok((world, exploration))
}

fn load_world_config(
    mut commands: Commands,
    paths: Res<RuntimePaths>,
    mut next: ResMut<NextState<AppState>>,
) {
    match load_configs(&paths.assets) {
        Ok((world, exploration)) => {
            let gameplay = GameRules::load(&paths.assets, &world)
                .and_then(|rules| QuestRules::load(&paths.assets).map(|quests| (rules, quests)))
                .and_then(|configs| {
                    crate::presentation::AssetManifest::load(&paths.assets)
                        .map(|manifest| (configs.0, configs.1, manifest))
                });
            let (rules, quests, manifest) = match gameplay {
                Ok(configs) => configs,
                Err(message) => {
                    error!("Gameplay configuration load failed: {message}");
                    commands.insert_resource(LoadError(message));
                    next.set(AppState::LoadError);
                    return;
                }
            };
            info!(
                "World and exploration configuration loaded from {}",
                paths.assets.display()
            );
            commands.insert_resource(world);
            commands.insert_resource(crate::save::GameSettings {
                volume: 0.7,
                camera_distance: exploration.camera.distance,
            });
            commands.insert_resource(exploration);
            commands.insert_resource(rules);
            commands.insert_resource(quests);
            commands.insert_resource(manifest);
        }
        Err(message) => {
            error!("Configuration load failed: {message}");
            commands.insert_resource(LoadError(message));
            next.set(AppState::LoadError);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::LifecyclePlugin;
    use bevy::state::app::StatesPlugin;

    #[test]
    fn shipped_configuration_is_valid() {
        load_configs(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets")).unwrap();
    }

    #[test]
    fn invalid_configuration_is_rejected_instead_of_defaulted() {
        let source = include_str!("../assets/config/world.ron");
        for invalid in [
            source.replace("map_size: 320.0", "map_size: -1.0"),
            source.replace("spawn: (0.0, 0.0, 24.0)", "spawn: (170.0, 0.0, 0.0)"),
            source.replace("spawn: (0.0, 0.0, 24.0)", "spawn: (0.0, 1.0, 0.0)"),
            source.replace("id: \"shed_02\"", "id: \"shed_01\""),
            source.replace("map_size:", "typo:"),
            "(map_size: 160.0)".into(),
        ] {
            assert!(WorldConfig::parse(&invalid).is_err());
        }
        let mut world = WorldConfig::parse(source).unwrap();
        let exploration =
            ExplorationConfig::parse(include_str!("../assets/config/exploration.ron")).unwrap();
        world.spawn = [-12.0, 0.0, 6.0];
        assert!(world.validate_spawn(&exploration).is_err());
    }

    #[test]
    fn non_finite_coordinates_and_invalid_camera_ranges_are_rejected() {
        let mut world = WorldConfig::parse(include_str!("../assets/config/world.ron")).unwrap();
        world.objects[0].center[0] = f32::NAN;
        assert!(world.validate().is_err());
        world.objects[0].center[0] = f32::INFINITY;
        assert!(world.validate().is_err());
        let source = include_str!("../assets/config/exploration.ron");
        for invalid in [
            source.replace("run_speed: 6.5", "run_speed: 0.0"),
            source.replace("max_pitch: 65.0", "max_pitch: 95.0"),
            source.replace("max_distance: 12.0", "max_distance: 2.0"),
        ] {
            assert!(ExplorationConfig::parse(&invalid).is_err());
        }
    }

    #[test]
    fn missing_configuration_enters_error_state_and_does_not_spawn_world() {
        let missing =
            std::env::temp_dir().join(format!("solo-rxjh-missing-assets-{}", std::process::id()));
        assert!(!missing.exists(), "test precondition: path must not exist");
        let mut app = App::new();
        app.add_plugins((MinimalPlugins, StatesPlugin))
            .insert_resource(RuntimePaths {
                assets: missing.clone(),
            })
            .add_plugins((LifecyclePlugin, DataPlugin));
        for _ in 0..3 {
            app.update();
        }
        assert_eq!(
            app.world().resource::<State<AppState>>().get(),
            &AppState::LoadError
        );
        assert!(!app.world().contains_resource::<WorldConfig>());
        assert!(
            app.world()
                .resource::<LoadError>()
                .0
                .contains(&missing.display().to_string())
        );
    }
}
