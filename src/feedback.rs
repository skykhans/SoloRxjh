use std::collections::HashMap;

use bevy::prelude::*;

use crate::{
    app::{AppState, WorldEntity},
    data::WorldConfig,
    gameplay::{
        combat::{EffectKind, GameSession},
        config::GameRules,
    },
    ui::{UiFont, objective_target},
};

pub struct FeedbackPlugin;

#[derive(Component, Clone, PartialEq, Eq, Hash)]
enum Feedback {
    Effect(u64),
    Objective,
    Drop(u64),
    Enemy(String),
}

impl Plugin for FeedbackPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, update_feedback.run_if(in_state(AppState::InGame)));
    }
}

fn update_feedback(world: &mut World) {
    let Some((camera, transform)) = world
        .query_filtered::<(&Camera, &GlobalTransform), With<Camera3d>>()
        .iter(world)
        .next()
        .map(|(c, t)| (c.clone(), *t))
    else {
        return;
    };
    let Some(size) = camera.logical_viewport_size() else {
        return;
    };
    let session = world.resource::<GameSession>();
    let mut items = vec![];
    let rules = world.resource::<GameRules>();
    let map = world.resource::<crate::gameplay::collision::CollisionMap>();
    for enemy in &session.enemies {
        if enemy.hp > 0
            && enemy.position.distance(session.position) <= 18.0
            && crate::gameplay::combat::sight(session.position, enemy.position, map, false)
        {
            let rule = rules.enemy(&enemy.kind);
            items.push((
                Feedback::Enemy(enemy.id.clone()),
                format!(
                    "{}{} Lv.{}\n{}/{}",
                    if enemy.boss() { "首领 · " } else { "" },
                    rule.label,
                    rule.level,
                    enemy.hp,
                    rule.hp
                ),
                Color::srgb(1.0, 0.8, 0.65),
                Vec3::new(
                    enemy.position.x,
                    (if enemy.boss() { 3.0 } else { 1.5 }) * rule.scale,
                    enemy.position.y,
                ),
            ));
        }
    }
    for effect in &session.effects {
        let (text, color) = match effect.kind {
            EffectKind::Damage => (format!("−{}", effect.amount), Color::srgb(1.0, 0.78, 0.3)),
            EffectKind::Hurt => (format!("−{}", effect.amount), Color::srgb(1.0, 0.25, 0.2)),
            EffectKind::Heal => (
                format!("+{} 生命", effect.amount),
                Color::srgb(0.4, 1.0, 0.5),
            ),
            EffectKind::Gather => (
                format!("+{} 修为", effect.amount),
                Color::srgb(0.5, 1.0, 0.8),
            ),
            EffectKind::LevelUp => (
                format!("修为提升 · 等级{}", effect.amount),
                Color::srgb(1.0, 0.9, 0.4),
            ),
            _ => continue,
        };
        items.push((
            Feedback::Effect(effect.id),
            text,
            color,
            Vec3::new(
                effect.position.x,
                1.8 + (0.8 - effect.remaining) * 1.7,
                effect.position.y,
            ),
        ));
    }
    if let Some((label, position)) = objective_target(
        session,
        world.resource::<WorldConfig>(),
        world.resource::<GameRules>(),
    ) && position.distance(session.position) < 18.0
    {
        items.push((
            Feedback::Objective,
            format!("◆ {label}"),
            Color::srgb(1.0, 0.88, 0.4),
            Vec3::new(position.x, 2.5, position.y),
        ));
    }
    for (i, drop) in session.drops.iter().enumerate() {
        if drop.position.distance(session.position) < 5.0 {
            let row = session.drops[..i]
                .iter()
                .filter(|other| other.position.distance(drop.position) < 0.5)
                .count();
            items.push((
                Feedback::Drop(drop.id),
                format!("F {} ×{}", drop.item.label(), drop.count),
                Color::srgb(0.65, 1.0, 0.7),
                Vec3::new(drop.position.x, 0.8 + row as f32 * 0.4, drop.position.y),
            ));
        }
    }
    let font = world.resource::<UiFont>().0.clone();
    let mut existing = world
        .query::<(Entity, &Feedback)>()
        .iter(world)
        .map(|(e, k)| (k.clone(), e))
        .collect::<HashMap<_, _>>();
    for (key, text, color, position) in items {
        let Ok(point) = camera.world_to_viewport(&transform, position) else {
            continue;
        };
        if point.x < 0.0 || point.x > size.x || point.y < 0.0 || point.y > size.y {
            continue;
        }
        let enemy_label = matches!(key, Feedback::Enemy(_));
        let node = Node {
            position_type: PositionType::Absolute,
            left: px(point.x - if enemy_label { 100.0 } else { 60.0 }),
            top: px(point.y - 24.0),
            width: px(if enemy_label { 200.0 } else { 240.0 }),
            ..default()
        };
        if let Some(entity) = existing.remove(&key) {
            world
                .entity_mut(entity)
                .insert((node, Text::new(text), TextColor(color)));
        } else {
            world.spawn((
                WorldEntity,
                key,
                node,
                GlobalZIndex(1),
                Text::new(text),
                TextLayout::new_with_justify(Justify::Center),
                TextFont {
                    font: font.clone(),
                    font_size: if enemy_label { 16.0 } else { 20.0 },
                    ..default()
                },
                TextColor(color),
            ));
        }
    }
    for entity in existing.into_values() {
        world.despawn(entity);
    }
}
