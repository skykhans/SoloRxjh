use super::*;
use std::collections::{HashMap, HashSet};

#[derive(Component, Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum View {
    Mini,
    World,
}

impl View {
    fn size(self) -> Vec2 {
        match self {
            Self::Mini => Vec2::new(220.0, 160.0),
            Self::World => Vec2::splat(300.0),
        }
    }
    fn half(self, config: &WorldConfig) -> f32 {
        match self {
            Self::Mini => 35.0,
            Self::World => config.map_size * 0.5,
        }
    }
}

#[derive(Component)]
struct Canvas(View);
#[derive(Component)]
struct MapTitle;
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum Key {
    Object(usize),
    Enemy(String),
    Drop(u64),
    Player,
    Objective,
    Waypoint,
}
#[derive(Component)]
pub(super) struct Marker {
    view: View,
    key: Key,
}
struct Point {
    position: Vec2,
    size: Vec2,
    color: Color,
}

fn marker(p: &mut ChildSpawnerCommands, view: View, key: Key) {
    let top = matches!(key, Key::Player | Key::Objective | Key::Waypoint);
    p.spawn((
        Marker { view, key },
        Node {
            position_type: PositionType::Absolute,
            width: px(5),
            height: px(5),
            ..default()
        },
        BackgroundColor(PAPER),
        ZIndex(if top { 3 } else { 1 }),
    ));
}

fn canvas(parent: &mut ChildSpawnerCommands, view: View, config: &WorldConfig, rules: &GameRules) {
    let size = view.size();
    let mut root = parent.spawn((
        Canvas(view),
        Node {
            width: px(size.x),
            height: px(size.y),
            overflow: Overflow::clip(),
            border: UiRect::all(px(1)),
            ..default()
        },
        BorderColor::all(GOLD),
        BackgroundColor(Color::srgb(0.12, 0.20, 0.17)),
    ));
    if view == View::Mini {
        root.insert((Button, Action::WorldMap));
    }
    root.with_children(|p| {
        for i in 0..config.objects.len() {
            marker(p, view, Key::Object(i));
        }
        for enemy in &rules.spawns {
            marker(p, view, Key::Enemy(enemy.id.clone()));
        }
        marker(p, view, Key::Objective);
        marker(p, view, Key::Waypoint);
        marker(p, view, Key::Player);
    });
}

pub(super) fn build_mini(
    p: &mut ChildSpawnerCommands,
    font: &Handle<Font>,
    config: &WorldConfig,
    rules: &GameRules,
) {
    p.spawn((MapTitle, label("千竹岭 · 北 ↑", 17.0, GOLD, font)));
    canvas(p, View::Mini, config, rules);
}

pub(super) fn build_world(
    p: &mut ChildSpawnerCommands,
    font: &Handle<Font>,
    config: &WorldConfig,
    rules: &GameRules,
) {
    canvas(p, View::World, config, rules);
    p.spawn(Node {
        column_gap: px(8),
        ..default()
    })
    .with_children(|p| {
        for (i, region) in rules.journey.regions.iter().enumerate() {
            button(
                p,
                &format!("{} Lv.{}", region.label, region.recommended_level),
                Action::TrackRegion(i),
                font,
            );
        }
    });
    button(p, "清除路标", Action::ClearWaypoint, font);
}

pub(super) fn refresh(world: &mut World) {
    let session = world.resource::<GameSession>();
    let player_position = session.position;
    let config = world.resource::<WorldConfig>().clone();
    let mut points = HashMap::new();
    for (i, object) in config.objects.iter().enumerate() {
        let color = match object.kind {
            crate::data::ObjectKind::Npc => Color::srgb(0.3, 1.0, 0.5),
            crate::data::ObjectKind::Water => Color::srgb(0.15, 0.45, 0.7),
            crate::data::ObjectKind::ValleyGround => Color::srgb(0.35, 0.36, 0.18),
            crate::data::ObjectKind::SnowGround => Color::srgb(0.55, 0.65, 0.68),
            crate::data::ObjectKind::Path | crate::data::ObjectKind::Bridge => {
                Color::srgb(0.55, 0.5, 0.32)
            }
            _ => Color::srgb(0.25, 0.32, 0.26),
        };
        points.insert(
            Key::Object(i),
            Point {
                position: Vec3::from_array(object.center).xz(),
                size: Vec2::new(object.size[0], object.size[2]),
                color,
            },
        );
    }
    for enemy in &session.enemies {
        if enemy.hp > 0 {
            points.insert(
                Key::Enemy(enemy.id.clone()),
                Point {
                    position: enemy.position,
                    size: Vec2::ZERO,
                    color: Color::srgb(1.0, 0.25, 0.2),
                },
            );
        }
    }
    for drop in &session.drops {
        points.insert(
            Key::Drop(drop.id),
            Point {
                position: drop.position,
                size: Vec2::ZERO,
                color: GOLD,
            },
        );
    }
    if let Some((_, position)) = objective_target(session, &config, world.resource::<GameRules>()) {
        points.insert(
            Key::Objective,
            Point {
                position,
                size: Vec2::ZERO,
                color: Color::srgb(1.0, 1.0, 0.6),
            },
        );
    }
    if let Some((_, position)) = &session.waypoint {
        points.insert(
            Key::Waypoint,
            Point {
                position: *position,
                size: Vec2::ZERO,
                color: Color::srgb(0.8, 0.5, 1.0),
            },
        );
    }
    points.insert(
        Key::Player,
        Point {
            position: player_position,
            size: Vec2::ZERO,
            color: Color::srgb(0.3, 0.8, 1.0),
        },
    );
    let rules = world.resource::<GameRules>();
    let region = rules
        .journey
        .regions
        .iter()
        .find(|r| r.contains(player_position))
        .map(|r| r.label.as_str())
        .unwrap_or("山间道路");
    let title = format!(
        "{region} · 北 ↑\n坐标 {:.0}, {:.0}",
        player_position.x, player_position.y
    );
    let drops = session.drops.iter().map(|d| d.id).collect::<Vec<_>>();
    let existing = world
        .query::<&Marker>()
        .iter(world)
        .map(|m| (m.view, m.key.clone()))
        .collect::<HashSet<_>>();
    let canvases = world
        .query::<(Entity, &Canvas)>()
        .iter(world)
        .map(|(e, c)| (e, c.0))
        .collect::<Vec<_>>();
    for (entity, view) in canvases {
        world.commands().entity(entity).with_children(|p| {
            for &id in &drops {
                if !existing.contains(&(view, Key::Drop(id))) {
                    marker(p, view, Key::Drop(id));
                }
            }
        });
    }
    let expired = world
        .query::<(Entity, &Marker)>()
        .iter(world)
        .filter(|(_, m)| matches!(m.key, Key::Drop(_)) && !points.contains_key(&m.key))
        .map(|(e, _)| e)
        .collect::<Vec<_>>();
    for entity in expired {
        world.despawn(entity);
    }
    for (marker, mut node, mut color) in world
        .query::<(&Marker, &mut Node, &mut BackgroundColor)>()
        .iter_mut(world)
    {
        let Some(point) = points.get(&marker.key) else {
            node.display = Display::None;
            continue;
        };
        let half = marker.view.half(&config);
        let center = if marker.view == View::Mini {
            player_position
        } else {
            Vec2::ZERO
        };
        let delta = (point.position - center) / (2.0 * half) + Vec2::splat(0.5);
        let size = marker.view.size();
        let dimensions = if point.size == Vec2::ZERO {
            Vec2::splat(
                if matches!(marker.key, Key::Player | Key::Objective | Key::Waypoint) {
                    7.0
                } else {
                    5.0
                },
            )
        } else {
            (point.size / (2.0 * half) * size).max(Vec2::splat(2.0))
        };
        node.display = if delta.cmplt(Vec2::ZERO).any() || delta.cmpgt(Vec2::ONE).any() {
            Display::None
        } else {
            Display::Flex
        };
        node.left = px(delta.x * size.x - dimensions.x * 0.5);
        node.top = px(delta.y * size.y - dimensions.y * 0.5);
        node.width = px(dimensions.x);
        node.height = px(dimensions.y);
        color.0 = point.color;
    }
    for mut text in world
        .query_filtered::<&mut Text, With<MapTitle>>()
        .iter_mut(world)
    {
        if text.0 != title {
            text.0.clone_from(&title);
        }
    }
}
