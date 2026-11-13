use super::*;
use crate::gameplay::skills::Skill;

#[derive(Component)]
pub(super) struct Slot(Skill);

pub(super) fn build(parent: &mut ChildSpawnerCommands, font: &Handle<Font>) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                bottom: px(16),
                left: px(0),
                width: percent(100),
                justify_content: JustifyContent::Center,
                column_gap: px(6),
                ..default()
            },
            ZIndex(2),
        ))
        .with_children(|p| {
            for skill in Skill::ALL {
                p.spawn((
                    Button,
                    Action::Cast(skill),
                    Node {
                        width: px(100),
                        height: px(64),
                        align_items: AlignItems::Center,
                        justify_content: JustifyContent::Center,
                        padding: UiRect::all(px(6)),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(INK),
                    BorderColor::all(GOLD),
                ))
                .with_children(|p| {
                    p.spawn((
                        Slot(skill),
                        label(
                            format!("{} {}", skill.key(), skill.label()),
                            16.0,
                            PAPER,
                            font,
                        ),
                    ));
                });
            }
        });
}

pub(super) fn refresh(session: Res<GameSession>, mut slots: Query<(&Slot, &mut Text)>) {
    for (Slot(skill), mut text) in &mut slots {
        let rank = session.progress.martial.ranks[skill.index()];
        let cooldown = if *skill == Skill::Energy {
            session.energy_cooldown
        } else {
            session.skill_cooldowns[skill.index() - 1]
        };
        let status = if !session.progress.stage.sword_bound() {
            "未认主".into()
        } else if rank == 0 {
            "未学习".into()
        } else if cooldown > 0.05 {
            format!("{cooldown:.1}s")
        } else {
            format!("{rank}级 · 就绪")
        };
        let value = format!("{} {}\n{status}", skill.key(), skill.label());
        if text.0 != value {
            text.0 = value;
        }
    }
}
