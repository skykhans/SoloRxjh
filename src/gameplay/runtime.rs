use bevy::{ecs::system::SystemParam, input::InputSystems, prelude::*};

use super::{
    collision::CollisionMap,
    combat::{CombatInput, EffectKind, EnemyState, GameSession},
    config::GameRules,
    exploration::{MovementIntent, MovementSet, Player},
    progress::{Item, QuestRules},
};
use crate::{
    app::{AppState, SessionState, WorldEntity},
    data::{ExplorationConfig, WorldConfig},
};

#[derive(Resource, Default)]
struct PendingCombat(CombatInput);

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GameplaySet {
    Tick,
    Sync,
}

pub struct GameplayPlugin;

#[derive(SystemParam)]
struct GameConfig<'w> {
    world: Res<'w, WorldConfig>,
    rules: Res<'w, GameRules>,
    exploration: Res<'w, ExplorationConfig>,
}

#[derive(SystemParam)]
struct MeshAssets<'w> {
    meshes: ResMut<'w, Assets<Mesh>>,
    materials: ResMut<'w, Assets<StandardMaterial>>,
    models: Option<Res<'w, crate::presentation::ModelLibrary>>,
    rules: Res<'w, GameRules>,
}

impl Plugin for GameplayPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PendingCombat>()
            .add_systems(
                OnEnter(AppState::InGame),
                start_session.after(crate::world::SpawnWorldSet),
            )
            .add_systems(OnExit(AppState::InGame), end_session)
            .add_systems(OnEnter(SessionState::Paused), clear_input)
            .add_systems(
                PreUpdate,
                capture_input
                    .after(InputSystems)
                    .after(crate::ui::UiInputSet)
                    .after(super::click_move::PointerInputSet)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .configure_sets(
                FixedUpdate,
                (GameplaySet::Tick, MovementSet, GameplaySet::Sync).chain(),
            )
            .add_systems(
                FixedUpdate,
                tick.in_set(GameplaySet::Tick)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .add_systems(
                FixedUpdate,
                sync_position
                    .in_set(GameplaySet::Sync)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .add_systems(Update, sync_visuals.run_if(in_state(AppState::InGame)));
        if app.is_plugin_added::<bevy::gizmos::GizmoPlugin>() {
            app.add_systems(Update, draw_combat.run_if(in_state(AppState::InGame)));
        }
    }
}

fn start_session(
    mut commands: Commands,
    config: GameConfig,
    quests: Res<QuestRules>,
    mut resume: Option<ResMut<crate::save::ResumeGame>>,
    mut rig: ResMut<super::exploration::CameraRig>,
    mut player: Query<&mut Transform, With<Player>>,
) {
    let GameConfig {
        world,
        rules,
        exploration,
    } = config;
    let mut session = GameSession::new(&world, &rules, &quests);
    if let Some(snapshot) = resume.as_mut().and_then(|r| r.0.take()) {
        session.progress = snapshot.progress;
        session.position = snapshot.position.into();
        session.yaw = snapshot.yaw;
        session.restore_scene(&rules);
        rig.distance = snapshot.settings.camera_distance;
        commands.insert_resource(snapshot.settings);
    } else {
        commands.insert_resource(crate::save::GameSettings {
            volume: 0.7,
            camera_distance: exploration.camera.distance,
        });
    }
    let mut transform = player.single_mut().expect("one player at session creation");
    transform.translation = Vec3::new(
        session.position.x,
        exploration.player_height * 0.5,
        session.position.y,
    );
    transform.rotation = Quat::from_rotation_y(session.yaw);
    commands.insert_resource(session.rebuild_map(&world, &rules));
    commands.insert_resource(session);
    commands.insert_resource(PendingCombat::default());
}

fn end_session(mut commands: Commands) {
    commands.remove_resource::<GameSession>();
    commands.insert_resource(PendingCombat::default());
}

fn clear_input(mut pending: ResMut<PendingCombat>) {
    pending.0 = CombatInput::default();
}

fn capture_input(
    keys: Res<ButtonInput<KeyCode>>,
    mut pointer: ResMut<super::click_move::ClickMove>,
    mut session: ResMut<GameSession>,
    mut player: Query<&mut Transform, With<Player>>,
    mut pending: ResMut<PendingCombat>,
) {
    pending.0.attack |= keys.just_pressed(KeyCode::KeyJ);
    if let Some((position, enemy)) = pointer.attack.take() {
        let delta = position - session.position;
        session.yaw = (-delta.x).atan2(-delta.y);
        player.single_mut().expect("one player in game").rotation =
            Quat::from_rotation_y(session.yaw);
        session.locked = enemy;
        pending.0.attack = true;
    }
    pending.0.energy |= keys.just_pressed(KeyCode::KeyQ);
    for (key, skill) in [
        (KeyCode::KeyR, super::skills::Skill::Piercing),
        (KeyCode::KeyG, super::skills::Skill::Guard),
        (KeyCode::KeyV, super::skills::Skill::Mend),
    ] {
        if keys.just_pressed(key) {
            pending.0.skill = Some(skill);
            break;
        }
    }
    pending.0.dodge |= keys.just_pressed(KeyCode::Space);
    pending.0.potion |= keys.just_pressed(KeyCode::Digit1);
    pending.0.lock |= keys.just_pressed(KeyCode::Tab);
}

fn tick(
    mut session: ResMut<GameSession>,
    mut pending: ResMut<PendingCombat>,
    intent: Res<MovementIntent>,
    mut player: Query<&mut Transform, With<Player>>,
    config: GameConfig,
    mut map: ResMut<CollisionMap>,
    time: Res<Time<Fixed>>,
) {
    let GameConfig {
        world,
        rules,
        exploration: config,
    } = config;
    let mut transform = player.single_mut().expect("one player in a game session");
    session.position = transform.translation.xz();
    session.yaw = transform.rotation.to_euler(EulerRot::YXZ).0;
    if session.map_dirty {
        *map = session.rebuild_map(&world, &rules);
    }
    let mut input = std::mem::take(&mut pending.0);
    input.direction = intent.direction;
    session.request(input, &rules, &map);
    session.tick(
        time.delta_secs(),
        &rules,
        &world,
        &map,
        config.player_radius,
    );
    transform.translation.x = session.position.x;
    transform.translation.z = session.position.y;
    transform.rotation = Quat::from_rotation_y(session.yaw);
    if session.map_dirty {
        *map = session.rebuild_map(&world, &rules);
    }
}

fn sync_position(
    mut session: ResMut<GameSession>,
    player: Query<&Transform, With<Player>>,
    rig: Res<super::exploration::CameraRig>,
    mut settings: Option<ResMut<crate::save::GameSettings>>,
    time: Res<Time<Fixed>>,
) {
    let transform = player.single().expect("one player in a game session");
    let position = transform.translation.xz();
    session.movement_speed = position.distance(session.position) / time.delta_secs();
    if session.position != position {
        session.dirty = true;
    }
    session.position = position;
    session.yaw = transform.rotation.to_euler(EulerRot::YXZ).0;
    if let Some(settings) = settings.as_mut()
        && settings.camera_distance != rig.distance
    {
        session.dirty = true;
        settings.camera_distance = rig.distance;
    }
}

#[derive(Component)]
struct EnemyVisual(String);

#[derive(Component)]
struct DropVisual(u64);

type StaticObjects = (With<WorldEntity>, Without<EnemyVisual>, Without<DropVisual>);

fn sync_visuals(
    mut commands: Commands,
    session: Res<GameSession>,
    asset_storage: MeshAssets,
    mut enemies: Query<(Entity, &EnemyVisual, &mut Transform, &mut Visibility)>,
    mut drops: Query<(Entity, &DropVisual, &mut Visibility), Without<EnemyVisual>>,
    mut objects: Query<(&Name, &mut Visibility), StaticObjects>,
    mut assets: Local<Option<CombatAssets>>,
) {
    let MeshAssets {
        mut meshes,
        mut materials,
        models,
        rules,
    } = asset_storage;
    let assets = assets.get_or_insert_with(|| CombatAssets {
        beast: meshes.add(Cuboid::new(0.9, 0.85, 1.5)),
        drop: meshes.add(Cuboid::new(0.25, 0.5, 0.25)),
        boar: materials.add(Color::srgb(0.40, 0.22, 0.13)),
        wolf: materials.add(Color::srgb(0.47, 0.52, 0.55)),
        boss: materials.add(Color::srgb(0.65, 0.14, 0.12)),
        bamboo: materials.add(Color::srgb(0.45, 0.85, 0.25)),
        ore: materials.add(Color::srgb(0.45, 0.7, 1.0)),
        potion: materials.add(Color::srgb(0.95, 0.25, 0.3)),
        material: materials.add(Color::srgb(0.8, 0.65, 0.35)),
    });
    for enemy in &session.enemies {
        if let Some((_, _, mut transform, mut visibility)) =
            enemies.iter_mut().find(|(_, v, _, _)| v.0 == enemy.id)
        {
            let delta = if matches!(enemy.state, EnemyState::Windup { .. }) {
                session.position - enemy.position
            } else {
                enemy.position - transform.translation.xz()
            };
            if delta.length_squared() > 1e-6 {
                transform.rotation = Quat::from_rotation_y((-delta.x).atan2(-delta.y));
            }
            transform.translation = Vec3::new(enemy.position.x, 0.0, enemy.position.y);
            *visibility = if enemy.hp > 0
                || matches!(enemy.state, EnemyState::Dead(t) if t > rules.ai.respawn - 0.8)
            {
                Visibility::Visible
            } else {
                Visibility::Hidden
            };
        } else {
            let material = match enemy.kind.as_str() {
                "boar" => &assets.boar,
                "mountain_wolf" => &assets.wolf,
                _ => &assets.boss,
            };
            let mut entity = commands.spawn((
                WorldEntity,
                EnemyVisual(enemy.id.clone()),
                Name::new(enemy.id.clone()),
                Transform::from_xyz(enemy.position.x, 0.0, enemy.position.y)
                    .with_scale(Vec3::splat(rules.enemy(&enemy.kind).scale)),
                if enemy.hp > 0 {
                    Visibility::Visible
                } else {
                    Visibility::Hidden
                },
            ));
            if let Some(models) = &models {
                entity.insert((
                    SceneRoot(models.model(&rules.enemy(&enemy.kind).model).scene.clone()),
                    crate::presentation::AnimatedModel::new(
                        &rules.enemy(&enemy.kind).model,
                        &enemy.id,
                    ),
                ));
            } else {
                entity.insert((
                    Mesh3d(assets.beast.clone()),
                    MeshMaterial3d(material.clone()),
                ));
            }
        }
    }
    for (entity, visual, _, _) in &enemies {
        if !session.enemies.iter().any(|e| e.id == visual.0) {
            commands.entity(entity).despawn();
        }
    }
    for drop in &session.drops {
        if !drops.iter().any(|(_, v, _)| v.0 == drop.id) {
            commands.spawn((
                WorldEntity,
                DropVisual(drop.id),
                Name::new(drop.item.label()),
                Mesh3d(assets.drop.clone()),
                MeshMaterial3d(match drop.item {
                    Item::LinglongBamboo => assets.bamboo.clone(),
                    Item::SpiritOre => assets.ore.clone(),
                    Item::HealingPotion => assets.potion.clone(),
                    Item::BeastHide | Item::WolfFang => assets.material.clone(),
                }),
                Transform::from_xyz(drop.position.x, 0.4, drop.position.y),
            ));
        }
    }
    for (entity, visual, _) in &mut drops {
        if !session.drops.iter().any(|d| d.id == visual.0) {
            commands.entity(entity).despawn();
        }
    }
    for (name, mut visibility) in &mut objects {
        if name.as_str() == "challenge_gate" {
            *visibility = if session.progress.stage.gate_open() {
                Visibility::Hidden
            } else {
                Visibility::Visible
            };
        } else if let Some(node) = session.bamboo.iter().find(|n| n.id == name.as_str()) {
            *visibility = if node.remaining > 0.0 {
                Visibility::Hidden
            } else {
                Visibility::Visible
            };
        }
    }
}

struct CombatAssets {
    beast: Handle<Mesh>,
    drop: Handle<Mesh>,
    boar: Handle<StandardMaterial>,
    wolf: Handle<StandardMaterial>,
    boss: Handle<StandardMaterial>,
    bamboo: Handle<StandardMaterial>,
    ore: Handle<StandardMaterial>,
    potion: Handle<StandardMaterial>,
    material: Handle<StandardMaterial>,
}

fn draw_combat(mut gizmos: Gizmos, session: Res<GameSession>, rules: Res<GameRules>) {
    let horizontal = Quat::from_rotation_x(std::f32::consts::FRAC_PI_2);
    let origin = Vec3::new(session.position.x, 0.15, session.position.y);
    if session.guard_remaining > 0.0 {
        gizmos.circle(
            Isometry3d::new(origin, horizontal),
            1.0,
            Color::srgb(0.3, 0.9, 1.0),
        );
    }
    if matches!(
        session.action,
        super::combat::PlayerAction::Skill {
            skill: super::skills::Skill::Piercing,
            ..
        }
    ) {
        let forward = Vec3::new(-session.yaw.sin(), 0.0, -session.yaw.cos());
        gizmos.line(
            origin,
            origin + forward * rules.skills.piercing.range,
            Color::srgb(0.5, 0.9, 1.0),
        );
    }
    for enemy in &session.enemies {
        if enemy.hp == 0 {
            continue;
        }
        let position = Vec3::new(enemy.position.x, 0.08, enemy.position.y);
        if let EnemyState::Windup { elapsed, heavy } = enemy.state {
            let radius = if heavy {
                rules.ai.heavy_range
            } else {
                rules.ai.range
            };
            let duration = if heavy {
                rules.ai.heavy_windup
            } else {
                rules.ai.windup
            };
            gizmos.circle(
                Isometry3d::new(position, horizontal),
                radius,
                Color::srgb(1.0, 0.2, 0.08),
            );
            gizmos.circle(
                Isometry3d::new(position + Vec3::Y * 0.02, horizontal),
                radius * elapsed / duration,
                Color::srgb(1.0, 0.8, 0.1),
            );
        }
        if session.locked.as_ref() == Some(&enemy.id) {
            gizmos.circle(
                Isometry3d::new(position + Vec3::Y * 0.03, horizontal),
                0.7,
                Color::srgb(1.0, 0.9, 0.3),
            );
        }
        let max_hp = rules.enemy(&enemy.kind).hp as f32;
        let bar = position + Vec3::Y * if enemy.boss() { 3.0 } else { 1.5 };
        gizmos.line(
            bar - Vec3::X * 0.6,
            bar + Vec3::X * 0.6,
            Color::srgb(0.2, 0.1, 0.1),
        );
        gizmos.line(
            bar - Vec3::X * 0.6,
            bar - Vec3::X * 0.6 + Vec3::X * 1.2 * enemy.hp as f32 / max_hp,
            Color::srgb(0.9, 0.2, 0.1),
        );
    }
    for node in &session.bamboo {
        if node.remaining == 0.0 {
            gizmos.circle(
                Isometry3d::new(
                    Vec3::new(node.position.x, 0.06, node.position.y),
                    horizontal,
                ),
                0.8,
                Color::srgb(0.5, 0.9, 0.3),
            );
        }
    }
    for effect in &session.effects {
        let color = match effect.kind {
            EffectKind::Damage | EffectKind::Hurt => Color::srgb(1.0, 0.15, 0.1),
            EffectKind::Heal | EffectKind::Gather | EffectKind::LevelUp => {
                Color::srgb(0.3, 1.0, 0.5)
            }
            _ => Color::srgb(1.0, 0.85, 0.3),
        };
        let radius = match effect.kind {
            EffectKind::Energy => rules.sword_energy.range,
            EffectKind::Swing => rules.combo.range,
            _ => 0.6,
        } * (1.0 - effect.remaining / 0.9);
        gizmos.circle(
            Isometry3d::new(
                Vec3::new(effect.position.x, 0.15, effect.position.y),
                horizontal,
            ),
            radius,
            color,
        );
    }
}
