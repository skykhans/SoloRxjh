use super::*;
use crate::{
    gameplay::{
        combat::{EnemyState, GameSession, PlayerAction},
        config::GameRules,
        equipment::Equipment,
        exploration::{CameraRig, Player},
        progress::{Item, StoryStage},
        skills::Skill,
    },
    presentation::ModelLibrary,
    ui::process_action,
};

const PANELS: [(Action, &str); 9] = [
    (Action::Character, "character"),
    (Action::Enhancement, "enhancement"),
    (Action::Npc, "npc"),
    (Action::Trading, "trading"),
    (Action::Sect, "sect"),
    (Action::WorldMap, "map"),
    (Action::Chat, "chat"),
    (Action::Martial, "martial"),
    (Action::Inventory, "inventory"),
];

fn place(world: &mut World, position: Vec2) -> Result<(), String> {
    world.resource_mut::<GameSession>().position = position;
    let mut transform = world
        .query_filtered::<&mut Transform, With<Player>>()
        .single_mut(world)
        .map_err(|e| e.to_string())?;
    transform.translation.x = position.x;
    transform.translation.z = position.y;
    world.resource_mut::<CameraRig>().yaw = 0.0;
    Ok(())
}

pub(super) fn prepare(world: &mut World) -> Result<(), String> {
    let rules = world.resource::<GameRules>().clone();
    let session = &mut *world.resource_mut::<GameSession>();
    session.progress.stage = StoryStage::Completed;
    session.progress.gain_exp(5000, &rules.player);
    session.progress.loadout.weapon = Some(Equipment::with_rank("fuxian_sword", 2));
    session.progress.loadout.armor = Some(Equipment::with_rank("menial_robe", 1));
    session
        .progress
        .add_equipment(Equipment::new("refined_blade"), &rules.equipment)?;
    session.progress.silver = 100;
    session.progress.martial.ranks = [3, 2, 2, 2];
    session.progress.inventory.add(Item::LinglongBamboo, 30)?;
    session.progress.inventory.add(Item::SpiritOre, 10)?;
    session.progress.sect.earned = 20;
    session.progress.sect.contribution = 10;
    session.progress.sect.rank = 1;
    session.quest_changed(&rules);
    session.notify("扩展功能原生验证样本；正式玩法由规则/ECS测试验证。");
    place(world, Vec2::new(4.0, 16.0))?;
    process_action(world, PANELS[0].0);
    Ok(())
}

fn pose(world: &mut World, skill: Skill) {
    process_action(world, Action::Resume);
    world.resource_mut::<CameraRig>().yaw = 1.1;
    let session = &mut *world.resource_mut::<GameSession>();
    session.action = PlayerAction::Idle;
    session.energy_cooldown = 0.0;
    session.skill_cooldowns = [0.0; 3];
    session.progress.stamina = 100.0;
    session.progress.hp = 200;
    process_action(world, Action::Cast(skill));
    world.resource_mut::<Time<Virtual>>().pause();
}

impl Verification {
    pub(super) fn expansion(&mut self, world: &mut World, phase: u8) -> Result<(), String> {
        let phase = usize::from(phase);
        if phase < PANELS.len() {
            if self.capture(world, PANELS[phase].1) {
                return Ok(());
            }
            if phase + 1 < PANELS.len() {
                process_action(world, PANELS[phase + 1].0);
            } else {
                pose(world, Skill::Energy);
            }
        } else if phase < PANELS.len() + 4 {
            let index = phase - PANELS.len();
            let label = ["energy", "piercing", "guard", "mend"][index];
            let clip = ["Energy", "Piercing", "Guard", "Mend"][index];
            let node = world.resource::<ModelLibrary>().model("fang_chen").clips[clip];
            let roots = world
                .query::<(Entity, &crate::presentation::AnimatedModel)>()
                .iter(world)
                .filter(|(_, m)| m.actor == "fang_chen")
                .map(|(e, _)| e)
                .collect::<Vec<_>>();
            let mut children = world.query::<&Children>();
            let children = children.query(world);
            let descendants = roots
                .into_iter()
                .flat_map(|e| children.iter_descendants(e))
                .collect::<Vec<_>>();
            let mut playing = false;
            for entity in descendants {
                if let Some(mut player) = world.get_mut::<AnimationPlayer>(entity)
                    && let Some(active) = player.animation_mut(node)
                {
                    active.seek_to(0.28);
                    playing = true;
                }
            }
            if !playing {
                return Err(format!("Player does not play required skill clip: {clip}"));
            }
            if self.capture(world, label) {
                return Ok(());
            }
            if index < 3 {
                pose(world, Skill::ALL[index + 1]);
            } else {
                world.resource_mut::<Time<Virtual>>().unpause();
                place(world, Vec2::new(5.0, -18.5))?;
                let session = &mut *world.resource_mut::<GameSession>();
                session.action = PlayerAction::Idle;
                session.enemies[0].hp = 1;
                session.enemies[0].position = Vec2::new(5.0, -20.0);
                session.enemies[0].state = EnemyState::Recover(100.0);
                process_action(world, Action::Cast(Skill::Piercing));
            }
        } else if phase == PANELS.len() + 4 {
            if world.resource::<GameSession>().drops.is_empty() {
                if self.frames > 180 {
                    return Err("Native skill did not kill the monster and produce loot".into());
                }
                return Ok(());
            }
            if self.capture(world, "monster-loot") {
                return Ok(());
            }
            world.resource_scope(|world, mut s: Mut<GameSession>| {
                s.pickup(world.resource::<crate::gameplay::collision::CollisionMap>())
            })?;
            if !world.resource::<GameSession>().drops.is_empty() {
                return Err("Native pickup did not remove the loot".into());
            }
            place(world, Vec2::new(120.0, 0.0))?;
        } else if phase == PANELS.len() + 5 {
            if self.frames < 60 {
                return Ok(());
            }
            if self.capture(world, "valley") {
                return Ok(());
            }
            place(world, Vec2::new(0.0, -105.0))?;
        } else {
            if self.frames < 60 {
                return Ok(());
            }
            if self.capture(world, "north") {
                return Ok(());
            }
            self.cycles += 1;
            press(world, Action::Pause)?;
            self.advance(Step::Pause);
            return Ok(());
        }
        self.advance(Step::Expansion((phase + 1) as u8));
        Ok(())
    }
}
