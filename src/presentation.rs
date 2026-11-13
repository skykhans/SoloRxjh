use std::{
    collections::{BTreeMap, HashSet},
    path::{Component, Path},
};

use bevy::{
    asset::LoadState, ecs::system::SystemParam, gltf::GltfAssetLabel, prelude::*,
    scene::SceneInstanceReady,
};
use serde::Deserialize;

use crate::{
    app::{AppState, SessionState},
    data::LoadError,
    gameplay::{
        combat::{EnemyState, GameSession, PlayerAction},
        exploration::Player,
        progress::StoryStage,
    },
};

#[derive(Resource, Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssetManifest {
    pub font: String,
    pub models: Vec<ModelSpec>,
    pub audio: Vec<AssetSpec>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ModelSpec {
    pub id: String,
    pub path: String,
    pub animations: Vec<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssetSpec {
    pub id: String,
    pub path: String,
}

impl AssetManifest {
    pub fn load(root: &Path) -> Result<Self, String> {
        let path = root.join("config/assets.ron");
        let text =
            std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        Self::parse(&text, root)
    }

    fn parse(text: &str, root: &Path) -> Result<Self, String> {
        let path = root.join("config/assets.ron");
        let manifest: Self = ron::from_str(text).map_err(|e| format!("{}: {e}", path.display()))?;
        let mut ids = HashSet::new();
        for (id, relative) in manifest
            .models
            .iter()
            .map(|m| (&m.id, &m.path))
            .chain(manifest.audio.iter().map(|a| (&a.id, &a.path)))
        {
            if id.is_empty()
                || !ids.insert(id)
                || Path::new(relative)
                    .components()
                    .any(|c| !matches!(c, Component::Normal(_)))
            {
                return Err(format!(
                    "{}: invalid/duplicate asset ID or relative path: {id}",
                    path.display()
                ));
            }
            let asset = root.join(relative);
            if !asset.is_file() {
                return Err(format!("{}: required asset not found", asset.display()));
            }
        }
        let model_ids = manifest
            .models
            .iter()
            .map(|m| m.id.as_str())
            .collect::<HashSet<_>>();
        let audio_ids = manifest
            .audio
            .iter()
            .map(|a| a.id.as_str())
            .collect::<HashSet<_>>();
        if model_ids
            != HashSet::from([
                "fang_chen",
                "cao_bin",
                "boar",
                "mountain_wolf",
                "bamboo_beast",
                "linglong_bamboo",
            ])
            || audio_ids
                != HashSet::from([
                    "qianzhu_theme",
                    "bamboo_battle",
                    "swing",
                    "hit",
                    "windup",
                    "hurt",
                    "energy",
                    "pickup",
                    "heal",
                    "level_up",
                    "ui_confirm",
                ])
            || manifest.font != "fonts/NotoSansCJKsc-Regular.otf"
            || manifest.models.iter().any(|m| {
                let required: &[&str] = match m.id.as_str() {
                    "fang_chen" => &[
                        "Idle", "Walk", "Run", "Attack1", "Attack2", "Attack3", "Energy",
                        "Piercing", "Guard", "Mend", "Dodge", "Hit", "Death", "Bind",
                    ],
                    "cao_bin" => &["Idle"],
                    "bamboo_beast" => &["Idle", "Walk", "Attack", "Heavy", "Hit", "Death"],
                    "boar" | "mountain_wolf" => &["Idle", "Walk", "Attack", "Hit", "Death"],
                    "linglong_bamboo" => &[],
                    _ => return true,
                };
                m.animations.len() != required.len()
                    || m.animations
                        .iter()
                        .map(String::as_str)
                        .collect::<HashSet<_>>()
                        != required.iter().copied().collect::<HashSet<_>>()
            })
        {
            return Err(format!(
                "{}: manifest must name the required models, animations, audio and font",
                path.display()
            ));
        }
        let font_path = root.join(&manifest.font);
        let bytes =
            std::fs::read(&font_path).map_err(|e| format!("{}: {e}", font_path.display()))?;
        Font::try_from_bytes(bytes).map_err(|e| format!("{}: {e}", font_path.display()))?;
        Ok(manifest)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asset_contract_rejects_missing_action_clips_and_unsafe_paths_before_gameplay() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("assets");
        let source = include_str!("../assets/config/assets.ron");
        assert!(AssetManifest::parse(source, &root).is_ok());
        for invalid in [
            source.replacen("\"Attack1\", ", "", 1),
            source.replacen("\"Idle\", \"Walk\"", "\"Idle\", \"Idle\"", 1),
            source.replace("models/characters/fang_chen.glb", "../fang_chen.glb"),
            source.replace("audio/hit.wav", "audio/absent.wav"),
        ] {
            assert!(AssetManifest::parse(&invalid, &root).is_err());
        }
    }

    #[test]
    fn newly_instantiated_animation_player_catches_up_to_existing_movement_state() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (config, _) = crate::data::load_configs(&root).unwrap();
        let rules = crate::gameplay::config::GameRules::load(&root, &config).unwrap();
        let quests = crate::gameplay::progress::QuestRules::load(&root).unwrap();
        let mut session = GameSession::new(&config, &rules, &quests);
        session.movement_speed = 4.0;
        let (_, clips) =
            AnimationGraph::from_clips([Handle::<AnimationClip>::default(), Handle::default()]);
        let mut app = App::new();
        app.insert_resource(session)
            .insert_resource(State::new(SessionState::Playing))
            .insert_resource(Time::<()>::default())
            .insert_resource(ModelLibrary {
                models: BTreeMap::from([(
                    "fang_chen".into(),
                    ModelAsset {
                        gltf: Handle::default(),
                        scene: Handle::default(),
                        graph: Handle::default(),
                        clips: BTreeMap::from([
                            ("Idle".into(), clips[0]),
                            ("Walk".into(), clips[1]),
                        ]),
                    },
                )]),
                audio: BTreeMap::new(),
                font: Handle::default(),
                ready: true,
            })
            .add_systems(Update, animate_models);
        app.world_mut().spawn((Player, Transform::default()));
        let mut model = AnimatedModel::new("fang_chen", "fang_chen");
        // Logical state was observed before the asynchronous GLB instance existed.
        model.current = "Walk".into();
        let root = app.world_mut().spawn(model).id();
        let mut animation = AnimationPlayer::default();
        animation.play(clips[0]).repeat();
        let instance = app.world_mut().spawn(animation).id();
        app.world_mut().entity_mut(root).add_child(instance);
        app.update();
        let animation = app.world().get::<AnimationPlayer>(instance).unwrap();
        assert!(animation.is_playing_animation(clips[1]));
        assert!(!animation.is_playing_animation(clips[0]));
    }
}

pub struct ModelAsset {
    pub gltf: Handle<Gltf>,
    pub scene: Handle<Scene>,
    pub graph: Handle<AnimationGraph>,
    pub clips: BTreeMap<String, AnimationNodeIndex>,
}

#[derive(Resource)]
pub struct ModelLibrary {
    pub models: BTreeMap<String, ModelAsset>,
    pub audio: BTreeMap<String, Handle<AudioSource>>,
    font: Handle<Font>,
    ready: bool,
}

impl ModelLibrary {
    pub fn model(&self, id: &str) -> &ModelAsset {
        self.models.get(id).expect("validated model ID")
    }
}

#[derive(Component)]
pub struct AnimatedModel {
    pub model: String,
    pub actor: String,
    current: String,
    last_position: Vec2,
    last_hp: Option<u32>,
    stage: Option<StoryStage>,
    reaction: f32,
    moving: f32,
}

impl AnimatedModel {
    pub fn new(model: &str, actor: &str) -> Self {
        Self {
            model: model.into(),
            actor: actor.into(),
            current: String::new(),
            last_position: Vec2::ZERO,
            last_hp: None,
            stage: None,
            reaction: 0.0,
            moving: 0.0,
        }
    }
}

pub struct PresentationPlugin;

#[derive(SystemParam)]
struct AnimationTargets<'w, 's> {
    children: Query<'w, 's, &'static Children>,
    players: Query<'w, 's, &'static mut AnimationPlayer>,
    swords: Query<'w, 's, (&'static Name, &'static mut Visibility)>,
}

impl Plugin for PresentationPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (load_assets, prepare_assets)
                .chain()
                .run_if(in_state(AppState::Loading)),
        )
        .add_observer(scene_ready)
        .add_systems(Update, animate_models.run_if(in_state(AppState::InGame)));
    }
}

fn load_assets(
    mut commands: Commands,
    manifest: Option<Res<AssetManifest>>,
    library: Option<Res<ModelLibrary>>,
    server: Res<AssetServer>,
) {
    if library.is_some() {
        return;
    }
    let Some(manifest) = manifest else {
        return;
    };
    let models = manifest
        .models
        .iter()
        .map(|spec| {
            (
                spec.id.clone(),
                ModelAsset {
                    gltf: server.load(spec.path.clone()),
                    scene: server.load(GltfAssetLabel::Scene(0).from_asset(spec.path.clone())),
                    graph: Handle::default(),
                    clips: BTreeMap::new(),
                },
            )
        })
        .collect();
    let audio = manifest
        .audio
        .iter()
        .map(|spec| (spec.id.clone(), server.load(spec.path.clone())))
        .collect();
    commands.insert_resource(ModelLibrary {
        models,
        audio,
        font: server.load(manifest.font.clone()),
        ready: false,
    });
}

fn prepare_assets(world: &mut World) {
    if !world.contains_resource::<ModelLibrary>() || world.resource::<ModelLibrary>().ready {
        return;
    }
    let result = prepare_loaded_assets(world);
    match result {
        Ok(true) => {
            world.resource_mut::<ModelLibrary>().ready = true;
            info!("All required assets loaded; main menu ready");
            world
                .resource_mut::<NextState<AppState>>()
                .set(AppState::MainMenu);
        }
        Ok(false) => {}
        Err(error) => {
            error!("Asset loading failed: {error}");
            world.insert_resource(LoadError(error));
            world
                .resource_mut::<NextState<AppState>>()
                .set(AppState::LoadError);
        }
    }
}

fn prepare_loaded_assets(world: &mut World) -> Result<bool, String> {
    let library = world.resource::<ModelLibrary>();
    let handles = library
        .models
        .values()
        .map(|m| m.gltf.clone().untyped())
        .chain(library.audio.values().map(|h| h.clone().untyped()))
        .chain(std::iter::once(library.font.clone().untyped()))
        .collect::<Vec<_>>();
    let server = world.resource::<AssetServer>();
    let mut waiting = false;
    for handle in handles {
        if let Some(LoadState::Failed(error)) = server.get_load_state(handle.id()) {
            let path = server
                .get_path(handle.id())
                .map(|p| p.to_string())
                .unwrap_or_else(|| format!("{:?}", handle.id()));
            return Err(format!("{path}: {error}"));
        }
        waiting |= !server.is_loaded_with_dependencies(handle.id());
    }
    if waiting {
        return Ok(false);
    }
    let specs = world.resource::<AssetManifest>().models.clone();
    for spec in specs {
        let gltf_handle = world
            .resource::<ModelLibrary>()
            .model(&spec.id)
            .gltf
            .clone();
        let gltf = world
            .resource::<Assets<Gltf>>()
            .get(&gltf_handle)
            .ok_or_else(|| format!("{}: loaded asset absent", spec.path))?;
        if gltf.scenes.len() != 1 || gltf.meshes.is_empty() {
            return Err(format!("{}: expected one nonempty scene", spec.path));
        }
        let clips = spec
            .animations
            .iter()
            .map(|name| {
                gltf.named_animations
                    .get(name.as_str())
                    .cloned()
                    .ok_or_else(|| format!("{}: missing animation {name}", spec.path))
            })
            .collect::<Result<Vec<_>, _>>()?;
        if !clips.is_empty() && gltf.skins.is_empty() {
            return Err(format!("{}: animated character has no skin", spec.path));
        }
        let (graph, indices) = AnimationGraph::from_clips(clips);
        let graph = world.resource_mut::<Assets<AnimationGraph>>().add(graph);
        let mut library = world.resource_mut::<ModelLibrary>();
        let model = library
            .models
            .get_mut(&spec.id)
            .expect("validated manifest ID");
        model.graph = graph;
        model.clips = spec.animations.into_iter().zip(indices).collect();
    }
    Ok(true)
}

fn scene_ready(
    event: On<SceneInstanceReady>,
    mut commands: Commands,
    models: Query<&AnimatedModel>,
    children: Query<&Children>,
    mut players: Query<&mut AnimationPlayer>,
    library: Res<ModelLibrary>,
) {
    let Ok(model) = models.get(event.entity) else {
        return;
    };
    let asset = library.model(&model.model);
    for entity in children.iter_descendants(event.entity) {
        if let Ok(mut player) = players.get_mut(entity) {
            player
                .play(*asset.clips.get("Idle").expect("validated Idle animation"))
                .repeat();
            commands
                .entity(entity)
                .insert(AnimationGraphHandle(asset.graph.clone()));
        }
    }
}

fn animate_models(
    session: Res<GameSession>,
    state: Res<State<SessionState>>,
    library: Res<ModelLibrary>,
    mut models: Query<(Entity, &mut AnimatedModel)>,
    targets: AnimationTargets,
    player: Query<&Transform, With<Player>>,
    time: Res<Time>,
) {
    let AnimationTargets {
        children,
        mut players,
        mut swords,
    } = targets;
    let player = player.single().expect("one player for character animation");
    for (root, mut model) in &mut models {
        let paused = *state.get() == SessionState::Paused;
        if !paused {
            model.reaction = (model.reaction - time.delta_secs()).max(0.0);
            model.moving = (model.moving - time.delta_secs()).max(0.0);
        }
        let (clip, position) = if model.actor == "fang_chen" {
            let position = player.translation.xz();
            if model.stage == Some(StoryStage::BindSword)
                && session.progress.stage == StoryStage::Gathering
            {
                model.reaction = 1.2;
            } else if model.last_hp.is_some_and(|hp| session.progress.hp < hp) {
                model.reaction = 0.3;
            }
            model.stage = Some(session.progress.stage);
            model.last_hp = Some(session.progress.hp);
            let clip = match session.action {
                PlayerAction::Melee { stage: 0, .. } => "Attack1",
                PlayerAction::Melee { stage: 1, .. } => "Attack2",
                PlayerAction::Melee { .. } => "Attack3",
                PlayerAction::Energy { .. } => "Energy",
                PlayerAction::Skill { skill, .. } => match skill {
                    crate::gameplay::skills::Skill::Energy => "Energy",
                    crate::gameplay::skills::Skill::Piercing => "Piercing",
                    crate::gameplay::skills::Skill::Guard => "Guard",
                    crate::gameplay::skills::Skill::Mend => "Mend",
                },
                PlayerAction::Dodge { .. } => "Dodge",
                PlayerAction::Dead => "Death",
                PlayerAction::Idle
                    if model.reaction > 0.3 || model.current == "Bind" && model.reaction > 0.0 =>
                {
                    "Bind"
                }
                PlayerAction::Idle if model.reaction > 0.0 => "Hit",
                PlayerAction::Idle if session.movement_speed > 5.0 => "Run",
                PlayerAction::Idle if session.movement_speed > 0.1 => "Walk",
                _ => "Idle",
            };
            (clip, position)
        } else if model.actor == "cao_bin" {
            ("Idle", Vec2::ZERO)
        } else {
            let Some(enemy) = session.enemies.iter().find(|e| e.id == model.actor) else {
                continue;
            };
            if model.last_hp.is_some_and(|hp| enemy.hp < hp) {
                model.reaction = 0.3;
            }
            model.last_hp = Some(enemy.hp);
            if enemy.position.distance(model.last_position) > 0.001 {
                model.moving = 0.1;
            }
            let clip = match enemy.state {
                EnemyState::Windup { heavy: true, .. } => "Heavy",
                EnemyState::Windup { .. } => "Attack",
                EnemyState::Dead(_) => "Death",
                _ if model.reaction > 0.0 => "Hit",
                _ if model.moving > 0.0 => "Walk",
                _ => "Idle",
            };
            (clip, enemy.position)
        };
        model.last_position = position;
        let asset = library.model(&model.model);
        let index = *asset.clips.get(clip).expect("validated required animation");
        for entity in children.iter_descendants(root) {
            if let Ok(mut animation) = players.get_mut(entity) {
                // The death panel pauses rules, while the player's death pose finishes.
                if paused && !(model.actor == "fang_chen" && clip == "Death") {
                    animation.pause_all();
                    continue;
                }
                animation.resume_all();
                if model.current != clip || !animation.is_playing_animation(index) {
                    animation.stop_all();
                    let active = animation.play(index);
                    if matches!(clip, "Idle" | "Walk" | "Run") {
                        active.repeat();
                    }
                }
            }
            if model.actor == "fang_chen"
                && let Ok((name, mut visible)) = swords.get_mut(entity)
                && name.as_str().starts_with("Sword")
            {
                *visible = if session.progress.loadout.weapon.is_some() {
                    Visibility::Inherited
                } else {
                    Visibility::Hidden
                };
            }
        }
        if !paused || model.actor == "fang_chen" && clip == "Death" {
            model.current = clip.into();
        }
    }
}
