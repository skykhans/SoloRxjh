use bevy::{
    input::{
        InputSystems,
        mouse::{AccumulatedMouseMotion, AccumulatedMouseScroll, MouseScrollUnit},
    },
    prelude::*,
    transform::TransformSystems,
};

use super::collision::{CollisionMap, camera_position, move_circle};
use crate::{
    app::{AppState, SessionState},
    data::{ExplorationConfig, ObjectKind, WorldConfig},
};

#[derive(Component)]
pub struct Player;

#[derive(Resource)]
pub struct CameraRig {
    pub yaw: f32,
    pub pitch: f32,
    pub distance: f32,
}

impl CameraRig {
    pub fn new(config: &ExplorationConfig) -> Self {
        Self {
            yaw: 0.0,
            pitch: config.camera.initial_pitch.to_radians(),
            distance: config.camera.distance,
        }
    }

    pub fn desired_position(&self, target: Vec3) -> Vec3 {
        let horizontal = self.distance * self.pitch.cos();
        target
            + Vec3::new(
                horizontal * self.yaw.sin(),
                self.distance * self.pitch.sin(),
                horizontal * self.yaw.cos(),
            )
    }
}

#[derive(Resource, Default)]
pub(crate) struct MovementIntent {
    pub direction: Vec2,
    pub(crate) running: bool,
}

#[derive(Clone)]
pub struct NearbyObject {
    pub id: String,
    pub label: String,
    pub kind: ObjectKind,
    pub distance: f32,
}

#[derive(Resource, Default)]
pub struct NearbyInteraction(pub Option<NearbyObject>);

#[derive(Resource, Default)]
pub struct CollisionDebug(pub bool);

pub struct ExplorationPlugin;

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct MovementSet;

impl Plugin for ExplorationPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MovementIntent>()
            .add_plugins(super::click_move::ClickMovePlugin)
            .init_resource::<NearbyInteraction>()
            .init_resource::<CollisionDebug>()
            .add_systems(OnEnter(AppState::InGame), reset_intent)
            .add_systems(OnEnter(SessionState::Playing), movement_input)
            .add_systems(OnEnter(SessionState::Paused), clear_movement)
            .add_systems(OnExit(AppState::InGame), end_session)
            .add_systems(
                PreUpdate,
                (camera_input, movement_input)
                    .chain()
                    .after(InputSystems)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .add_systems(
                FixedUpdate,
                move_player
                    .in_set(MovementSet)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .add_systems(
                PostUpdate,
                (follow_camera, find_nearby)
                    .before(TransformSystems::Propagate)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            );
        // Headless ECS tests deliberately omit presentation plugins.
        if app.is_plugin_added::<bevy::gizmos::GizmoPlugin>() {
            app.add_systems(
                Update,
                draw_collision_debug.run_if(in_state(AppState::InGame)),
            );
        }
    }
}

fn clear_movement(mut intent: ResMut<MovementIntent>) {
    *intent = MovementIntent::default();
}

fn reset_intent(
    mut intent: ResMut<MovementIntent>,
    mut nearby: ResMut<NearbyInteraction>,
    mut debug: ResMut<CollisionDebug>,
) {
    *intent = MovementIntent::default();
    nearby.0 = None;
    debug.0 = false;
}

fn end_session(
    mut commands: Commands,
    mut intent: ResMut<MovementIntent>,
    mut nearby: ResMut<NearbyInteraction>,
) {
    commands.remove_resource::<CameraRig>();
    commands.remove_resource::<CollisionMap>();
    *intent = MovementIntent::default();
    nearby.0 = None;
}

pub fn movement_direction(axis: Vec2, yaw: f32) -> Vec2 {
    let direction = Quat::from_rotation_y(yaw) * Vec3::new(axis.x, 0.0, axis.y).normalize_or_zero();
    direction.xz()
}

fn movement_input(
    keys: Res<ButtonInput<KeyCode>>,
    rig: Res<CameraRig>,
    mut intent: ResMut<MovementIntent>,
) {
    let axis = Vec2::new(
        f32::from(u8::from(keys.pressed(KeyCode::KeyD)))
            - f32::from(u8::from(keys.pressed(KeyCode::KeyA))),
        f32::from(u8::from(keys.pressed(KeyCode::KeyS)))
            - f32::from(u8::from(keys.pressed(KeyCode::KeyW))),
    );
    intent.direction = movement_direction(axis, rig.yaw);
    intent.running = keys.pressed(KeyCode::ShiftLeft) || keys.pressed(KeyCode::ShiftRight);
}

fn camera_input(
    buttons: Res<ButtonInput<MouseButton>>,
    motion: Res<AccumulatedMouseMotion>,
    scroll: Res<AccumulatedMouseScroll>,
    keys: Res<ButtonInput<KeyCode>>,
    config: Res<ExplorationConfig>,
    mut rig: ResMut<CameraRig>,
    mut debug: ResMut<CollisionDebug>,
) {
    let camera = &config.camera;
    if buttons.pressed(MouseButton::Right) {
        rig.yaw = (rig.yaw - motion.delta.x * camera.rotation_sensitivity)
            .rem_euclid(std::f32::consts::TAU);
        rig.pitch = (rig.pitch + motion.delta.y * camera.rotation_sensitivity)
            .clamp(camera.min_pitch.to_radians(), camera.max_pitch.to_radians());
    }
    let scroll_lines = match scroll.unit {
        MouseScrollUnit::Line => scroll.delta.y,
        MouseScrollUnit::Pixel => scroll.delta.y / 40.0,
    };
    rig.distance = (rig.distance - scroll_lines * camera.scroll_sensitivity)
        .clamp(camera.min_distance, camera.max_distance);
    if keys.just_pressed(KeyCode::F3) {
        debug.0 = !debug.0;
    }
}

pub(crate) fn move_player(
    mut players: Query<&mut Transform, With<Player>>,
    intent: Res<MovementIntent>,
    config: Res<ExplorationConfig>,
    map: Res<CollisionMap>,
    time: Res<Time<Fixed>>,
    session: Option<Res<super::combat::GameSession>>,
) {
    if session.is_some_and(|session| session.movement_blocked) {
        return;
    }
    let speed = if intent.running {
        config.run_speed
    } else {
        config.walk_speed
    };
    for mut transform in &mut players {
        let position = move_circle(
            transform.translation.xz(),
            intent.direction * speed * time.delta_secs(),
            config.player_radius,
            &map,
        );
        transform.translation.x = position.x;
        transform.translation.z = position.y;
        if intent.direction.length_squared() > 0.0 {
            transform.rotation =
                Quat::from_rotation_y((-intent.direction.x).atan2(-intent.direction.y));
        }
    }
}

fn follow_camera(
    player: Query<&Transform, With<Player>>,
    mut cameras: Query<&mut Transform, (With<Camera3d>, Without<Player>)>,
    rig: Res<CameraRig>,
    config: Res<ExplorationConfig>,
    map: Res<CollisionMap>,
    time: Res<Time>,
) {
    let player = player
        .single()
        .expect("InGame must contain exactly one player");
    let target = player.translation + Vec3::Y * config.player_height * 0.25;
    let alpha = 1.0 - (-config.camera.follow_sharpness * time.delta_secs()).exp();
    for mut transform in &mut cameras {
        let desired = rig.desired_position(target);
        let smoothed = transform.translation.lerp(desired, alpha);
        let position = camera_position(target, smoothed, config.camera.margin, &map);
        *transform = Transform::from_translation(position).looking_at(target, Vec3::Y);
    }
}

fn find_nearby(
    player: Query<&Transform, With<Player>>,
    world: Res<WorldConfig>,
    config: Res<ExplorationConfig>,
    mut nearby: ResMut<NearbyInteraction>,
) {
    let player = player
        .single()
        .expect("InGame must contain exactly one player");
    nearby.0 = world
        .objects
        .iter()
        .filter(|object| object.kind.interactable())
        .filter_map(|object| {
            let distance = player
                .translation
                .xz()
                .distance(Vec3::from_array(object.center).xz());
            (distance <= config.interaction_distance).then_some((object, distance))
        })
        .min_by(|(left, a), (right, b)| a.total_cmp(b).then_with(|| left.id.cmp(&right.id)))
        .map(|(object, distance)| NearbyObject {
            id: object.id.clone(),
            label: object.label.clone(),
            kind: object.kind,
            distance,
        });
}

fn draw_collision_debug(
    mut gizmos: Gizmos,
    map: Res<CollisionMap>,
    world: Res<WorldConfig>,
    config: Res<ExplorationConfig>,
    players: Query<&Transform, With<Player>>,
    debug: Res<CollisionDebug>,
) {
    if !debug.0 {
        return;
    }
    for bounds in &map.movement {
        gizmos.cuboid(
            Transform::from_translation((bounds.min + bounds.max) * 0.5)
                .with_scale(bounds.max - bounds.min),
            Color::srgb(0.0, 1.0, 1.0),
        );
    }
    let horizontal = Quat::from_rotation_x(std::f32::consts::FRAC_PI_2);
    gizmos.circle(
        Isometry3d::new(
            Vec3::new(world.safe_zone.center[0], 0.08, world.safe_zone.center[1]),
            horizontal,
        ),
        world.safe_zone.radius,
        Color::srgb(0.2, 1.0, 0.3),
    );
    for player in &players {
        gizmos.circle(
            Isometry3d::new(
                Vec3::new(player.translation.x, 0.08, player.translation.z),
                horizontal,
            ),
            config.player_radius,
            Color::srgb(1.0, 0.8, 0.1),
        );
    }
    gizmos.cuboid(
        Transform::from_xyz(0.0, 1.0, 0.0).with_scale(Vec3::new(
            map.half_size * 2.0,
            2.0,
            map.half_size * 2.0,
        )),
        Color::srgb(1.0, 0.4, 0.1),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagonal_is_normalized_and_movement_rotates_with_camera() {
        assert!((movement_direction(Vec2::new(1.0, -1.0), 0.0).length() - 1.0).abs() < 1e-6);
        let turned = movement_direction(Vec2::new(0.0, -1.0), std::f32::consts::FRAC_PI_2);
        assert!(turned.distance(Vec2::new(-1.0, 0.0)) < 1e-6);
        assert_eq!(movement_direction(Vec2::ZERO, 1.0), Vec2::ZERO);
    }
}
