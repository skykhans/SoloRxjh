use std::collections::VecDeque;

use bevy::{input::InputSystems, prelude::*, window::PrimaryWindow};

use super::{
    collision::{Aabb, CollisionMap, move_circle, segment_hit},
    combat::GameSession,
    exploration::{MovementIntent, MovementSet, Player},
    navigation::NavGrid,
};
use crate::{
    app::{AppState, SessionState},
    data::{ExplorationConfig, ObjectKind, WorldConfig},
};

#[derive(Resource, Default)]
pub struct ClickMove {
    pub destination: Option<Vec2>,
    route: VecDeque<Vec2>,
    grid: Option<NavGrid>,
    pub(crate) attack: Option<(Vec2, Option<String>)>,
}

impl ClickMove {
    pub fn cancel(&mut self) {
        self.destination = None;
        self.route.clear();
    }

    pub fn request(&mut self, from: Vec2, to: Vec2, map: &CollisionMap, radius: f32) -> bool {
        let grid = self
            .grid
            .get_or_insert_with(|| NavGrid::new(map, None, radius));
        self.route = grid.path(from, to, map).into();
        self.destination = (!self.route.is_empty()).then_some(to);
        self.destination.is_some()
    }
}

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) struct PointerInputSet;

pub struct ClickMovePlugin;

impl Plugin for ClickMovePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<ClickMove>()
            .add_systems(OnEnter(AppState::InGame), reset)
            .add_systems(OnExit(AppState::InGame), reset)
            .add_systems(OnEnter(SessionState::Paused), reset)
            .add_systems(
                PreUpdate,
                pointer_input
                    .in_set(PointerInputSet)
                    .after(InputSystems)
                    .after(crate::ui::UiInputSet)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            )
            .add_systems(
                FixedUpdate,
                follow_route
                    .in_set(MovementSet)
                    .after(super::exploration::move_player)
                    .run_if(in_state(AppState::InGame))
                    .run_if(in_state(SessionState::Playing)),
            );
        if app.is_plugin_added::<bevy::gizmos::GizmoPlugin>() {
            app.add_systems(Update, draw_destination.run_if(in_state(AppState::InGame)));
        }
    }
}

fn reset(mut movement: ResMut<ClickMove>) {
    *movement = ClickMove::default();
}

// The nearest visible solid/enemy wins; a wall cannot be clicked through to attack.
pub(crate) fn pick(
    ray: Ray3d,
    session: &GameSession,
    world: &WorldConfig,
    map: &CollisionMap,
) -> Option<(Vec2, Option<Option<String>>)> {
    let distance = ray.intersect_plane(Vec3::ZERO, InfinitePlane3d::new(Vec3::Y))?;
    let end = ray.get_point(distance);
    let mut hit = None;
    let mut nearest = 1.0;
    for enemy in session.enemies.iter().filter(|e| e.hp > 0) {
        let height = if enemy.boss() { 2.3 } else { 1.1 };
        let bounds = Aabb::from_center_size(
            Vec3::new(enemy.position.x, height * 0.5, enemy.position.y),
            Vec3::new(height, height, height),
        );
        if let Some(t) = segment_hit(ray.origin, end, bounds, 0.0)
            && t < nearest
        {
            nearest = t;
            hit = Some((enemy.position, Some(Some(enemy.id.clone()))));
        }
    }
    for object in world
        .objects
        .iter()
        .filter(|o| o.kind == ObjectKind::Bamboo && o.id.starts_with("bamboo_"))
    {
        if session
            .bamboo
            .iter()
            .any(|n| n.id == object.id && n.remaining > 0.0)
        {
            continue;
        }
        if let Some(t) = segment_hit(ray.origin, end, object.bounds(), 0.0)
            && t < nearest
        {
            nearest = t;
            hit = Some((Vec3::from_array(object.center).xz(), Some(None)));
        }
    }
    let nearest_solid = map
        .camera
        .iter()
        .filter_map(|b| segment_hit(ray.origin, end, *b, 0.0))
        .min_by(f32::total_cmp);
    if nearest_solid.is_some_and(|t| t + 1e-4 < nearest) {
        return None;
    }
    hit.or(Some((end.xz(), None)))
}

fn pointer_input(world: &mut World) {
    world.resource_mut::<ClickMove>().attack = None;
    let keys = world.resource::<ButtonInput<KeyCode>>();
    if [
        KeyCode::KeyW,
        KeyCode::KeyA,
        KeyCode::KeyS,
        KeyCode::KeyD,
        KeyCode::KeyJ,
        KeyCode::KeyQ,
        KeyCode::KeyR,
        KeyCode::KeyG,
        KeyCode::KeyV,
        KeyCode::Space,
    ]
    .iter()
    .any(|k| keys.pressed(*k))
    {
        world.resource_mut::<ClickMove>().cancel();
        return;
    }
    if world.is_resource_changed::<CollisionMap>() {
        let mut movement = world.resource_mut::<ClickMove>();
        movement.grid = None;
        movement.cancel();
    }
    if !world
        .resource::<ButtonInput<MouseButton>>()
        .just_pressed(MouseButton::Left)
        || world
            .query::<&Interaction>()
            .iter(world)
            .any(|i| *i != Interaction::None)
    {
        return;
    }
    let Some(cursor) = world
        .query_filtered::<&Window, With<PrimaryWindow>>()
        .iter(world)
        .next()
        .and_then(Window::cursor_position)
    else {
        return;
    };
    let Some(ray) = world
        .query_filtered::<(&Camera, &GlobalTransform), With<Camera3d>>()
        .iter(world)
        .next()
        .and_then(|(camera, transform)| camera.viewport_to_world(transform, cursor).ok())
    else {
        return;
    };
    let Some(session) = world.get_resource::<GameSession>() else {
        return;
    };
    let result = pick(
        ray,
        session,
        world.resource::<WorldConfig>(),
        world.resource::<CollisionMap>(),
    );
    let position = session.position;
    match result {
        Some((target, Some(enemy))) => {
            let mut movement = world.resource_mut::<ClickMove>();
            movement.cancel();
            movement.attack = Some((target, enemy));
        }
        Some((target, None)) => {
            let radius = world.resource::<ExplorationConfig>().player_radius;
            let success = world.resource_scope(|world, mut movement: Mut<ClickMove>| {
                movement.request(position, target, world.resource::<CollisionMap>(), radius)
            });
            if !success {
                world.resource_mut::<GameSession>().notify("该位置不可到达");
            }
        }
        None => {
            world.resource_mut::<ClickMove>().cancel();
        }
    }
}

fn follow_route(
    mut movement: ResMut<ClickMove>,
    intent: Res<MovementIntent>,
    config: Res<ExplorationConfig>,
    map: Res<CollisionMap>,
    session: Option<Res<GameSession>>,
    mut players: Query<&mut Transform, With<Player>>,
    time: Res<Time<Fixed>>,
) {
    if intent.direction != Vec2::ZERO {
        movement.cancel();
        return;
    }
    if session.is_some_and(|s| s.movement_blocked) {
        return;
    }
    let speed = if intent.running {
        config.run_speed
    } else {
        config.walk_speed
    };
    let Ok(mut player) = players.single_mut() else {
        return;
    };
    let mut distance = speed * time.delta_secs();
    while distance > 0.0001 {
        let Some(target) = movement.route.front().copied() else {
            movement.destination = None;
            break;
        };
        let from = player.translation.xz();
        let delta = target - from;
        if delta.length() < 0.001 {
            movement.route.pop_front();
            continue;
        }
        let step = delta.normalize() * distance.min(delta.length());
        let to = move_circle(from, step, config.player_radius, &map);
        if to.distance(from + step) > 0.001 {
            movement.cancel();
            break;
        }
        player.translation.x = to.x;
        player.translation.z = to.y;
        player.rotation = Quat::from_rotation_y((-delta.x).atan2(-delta.y));
        distance -= step.length();
        if to.distance(target) < 0.001 {
            movement.route.pop_front();
        }
    }
    if movement.route.is_empty() {
        movement.destination = None;
    }
}

fn draw_destination(movement: Res<ClickMove>, mut gizmos: Gizmos) {
    if let Some(point) = movement.destination {
        gizmos.circle(
            Isometry3d::new(
                Vec3::new(point.x, 0.08, point.y),
                Quat::from_rotation_x(std::f32::consts::FRAC_PI_2),
            ),
            0.35,
            Color::srgb(0.95, 0.8, 0.3),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pointer_ray_picks_ground_and_enemy_and_does_not_attack_through_walls() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (world, _) = crate::data::load_configs(&root).unwrap();
        let rules = super::super::config::GameRules::load(&root, &world).unwrap();
        let quests = super::super::progress::QuestRules::load(&root).unwrap();
        let mut session = GameSession::new(&world, &rules, &quests);
        let mut map = session.rebuild_map(&world, &rules);
        let ray = Ray3d::new(Vec3::new(0.0, 10.0, 24.0), Dir3::NEG_Y);
        let target = pick(ray, &session, &world, &map).unwrap();
        assert!(target.0.distance(Vec2::new(0.0, 24.0)) < 0.001 && target.1.is_none());
        let enemy = &session.enemies[0];
        let origin = Vec3::new(enemy.position.x, 10.0, enemy.position.y);
        let ray = Ray3d::new(origin, Dir3::NEG_Y);
        assert_eq!(
            pick(ray, &session, &world, &map).unwrap().1,
            Some(Some(enemy.id.clone()))
        );
        map.camera
            .push(Aabb::from_center_size(origin - Vec3::Y, Vec3::ONE));
        assert!(pick(ray, &session, &world, &map).is_none());
    }
}
