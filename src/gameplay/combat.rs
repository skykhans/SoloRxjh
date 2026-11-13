use std::collections::VecDeque;

use bevy::prelude::*;

use super::{
    collision::{CollisionMap, move_circle, segment_hit},
    config::GameRules,
    navigation::{NavGrid, crosses_safe_zone},
    progress::{Item, Progress, QuestRules, StoryStage},
    skills::Skill,
};
use crate::data::{ObjectKind, WorldConfig};

#[derive(Clone, Debug, Default)]
pub enum PlayerAction {
    #[default]
    Idle,
    Melee {
        stage: usize,
        elapsed: f32,
        hit: bool,
        queued: bool,
    },
    Energy {
        elapsed: f32,
        hit: bool,
    },
    Skill {
        skill: Skill,
        elapsed: f32,
        hit: bool,
    },
    Dodge {
        elapsed: f32,
        direction: Vec2,
    },
    Dead,
}

impl PlayerAction {
    pub fn allows_movement(&self) -> bool {
        matches!(self, Self::Idle)
    }

    pub fn immune(&self, rules: &GameRules) -> bool {
        matches!(self, Self::Dodge { elapsed, .. }
            if *elapsed >= rules.dodge.immune_start && *elapsed < rules.dodge.immune_end)
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct CombatInput {
    pub attack: bool,
    pub energy: bool,
    pub skill: Option<Skill>,
    pub dodge: bool,
    pub potion: bool,
    pub lock: bool,
    pub direction: Vec2,
}

#[derive(Clone, Debug)]
pub enum EnemyState {
    Idle,
    Patrol,
    Chase,
    Windup { elapsed: f32, heavy: bool },
    Recover(f32),
    Return,
    Dead(f32),
}

#[derive(Clone, Debug)]
pub struct Enemy {
    pub id: String,
    pub kind: String,
    pub home: Vec2,
    pub position: Vec2,
    pub hp: u32,
    pub state: EnemyState,
    pub heavy_timer: f32,
    pub is_boss: bool,
    path: VecDeque<Vec2>,
    path_timer: f32,
    path_target: Vec2,
    patrol_clock: f32,
}

impl Enemy {
    pub fn boss(&self) -> bool {
        self.is_boss
    }
}

#[derive(Clone, Debug)]
pub struct BambooNode {
    pub id: String,
    pub position: Vec2,
    pub hits: u8,
    pub remaining: f32,
}

#[derive(Clone, Debug)]
pub struct Drop {
    pub id: u64,
    pub position: Vec2,
    pub item: Item,
    pub count: u32,
}

#[derive(Clone, Copy, Debug)]
pub enum EffectKind {
    Swing,
    Energy,
    Dodge,
    Damage,
    Heal,
    Gather,
    LevelUp,
    Hurt,
    Windup,
    Pickup,
}

#[derive(Clone, Debug)]
pub struct Effect {
    pub id: u64,
    pub position: Vec2,
    pub kind: EffectKind,
    pub amount: u32,
    pub remaining: f32,
}

#[derive(Resource)]
pub struct GameSession {
    pub progress: Progress,
    pub position: Vec2,
    pub yaw: f32,
    pub action: PlayerAction,
    pub movement_blocked: bool,
    pub movement_speed: f32,
    pub energy_cooldown: f32,
    pub skill_cooldowns: [f32; 3],
    pub guard_remaining: f32,
    pub potion_cooldown: f32,
    pub enemies: Vec<Enemy>,
    pub bamboo: Vec<BambooNode>,
    pub drops: Vec<Drop>,
    pub effects: Vec<Effect>,
    pub messages: VecDeque<super::messages::ChatMessage>,
    pub waypoint: Option<(String, Vec2)>,
    pub locked: Option<String>,
    pub notice: String,
    pub notice_remaining: f32,
    pub dirty: bool,
    pub auto_save: bool,
    pub map_dirty: bool,
    combo_next: usize,
    combo_idle: f32,
    regen_wait: f32,
    lock_obstructed: f32,
    next_drop: u64,
    next_effect: u64,
    nav: NavGrid,
}

pub fn collision_map(
    world: &WorldConfig,
    stage: StoryStage,
    bamboo: &[BambooNode],
) -> CollisionMap {
    let include = |object: &&crate::data::WorldObject| {
        !(object.kind == ObjectKind::Gate && stage.gate_open()
            || bamboo
                .iter()
                .any(|node| node.id == object.id && node.remaining > 0.0))
    };
    CollisionMap {
        half_size: world.map_size * 0.5,
        movement: world
            .objects
            .iter()
            .filter(include)
            .filter(|o| o.kind.blocks_movement())
            .map(|o| o.bounds())
            .collect(),
        camera: world
            .objects
            .iter()
            .filter(include)
            .filter(|o| o.kind.blocks_camera())
            .map(|o| o.bounds())
            .collect(),
    }
}

pub fn sight(from: Vec2, to: Vec2, map: &CollisionMap, ignore_target: bool) -> bool {
    let start = Vec3::new(from.x, 1.0, from.y);
    let end = Vec3::new(to.x, 1.0, to.y);
    !map.camera.iter().any(|bounds| {
        if ignore_target && to.cmpge(bounds.min.xz()).all() && to.cmple(bounds.max.xz()).all() {
            return false;
        }
        segment_hit(start, end, *bounds, 0.0).is_some()
    })
}

pub fn in_sector(from: Vec2, yaw: f32, to: Vec2, range: f32, half_angle: f32) -> bool {
    let delta = to - from;
    let forward = Vec2::new(-yaw.sin(), -yaw.cos());
    delta.length() <= range + 1e-5
        && (delta.length_squared() < 1e-8
            || forward.dot(delta.normalize()) + 1e-6 >= half_angle.to_radians().cos())
}

impl GameSession {
    pub fn new(world: &WorldConfig, rules: &GameRules, quests: &QuestRules) -> Self {
        let bamboo = world
            .objects
            .iter()
            .filter(|o| o.kind == ObjectKind::Bamboo && o.id.starts_with("bamboo_"))
            .map(|o| BambooNode {
                id: o.id.clone(),
                position: Vec3::from_array(o.center).xz(),
                hits: 0,
                remaining: 0.0,
            })
            .collect::<Vec<_>>();
        let map = collision_map(world, StoryStage::Report, &bamboo);
        let nav = NavGrid::new(&map, Some(&world.safe_zone), rules.ai.radius);
        let mut session = Self {
            progress: Progress::new(rules, quests),
            position: Vec3::from_array(world.spawn).xz(),
            yaw: 0.0,
            action: PlayerAction::Idle,
            movement_blocked: false,
            movement_speed: 0.0,
            energy_cooldown: 0.0,
            skill_cooldowns: [0.0; 3],
            guard_remaining: 0.0,
            potion_cooldown: 0.0,
            enemies: vec![],
            bamboo,
            drops: vec![],
            effects: vec![],
            messages: super::messages::initial_messages(),
            waypoint: None,
            locked: None,
            notice: "没有灵根，难道就只能一直做杂役？先去千竹岭，把差事做完。".into(),
            notice_remaining: 8.0,
            dirty: true,
            auto_save: true,
            map_dirty: false,
            combo_next: 0,
            combo_idle: 0.0,
            regen_wait: 0.0,
            lock_obstructed: 0.0,
            next_drop: 1,
            next_effect: 1,
            nav,
        };
        session.reset_enemies(rules);
        session
    }

    fn reset_enemies(&mut self, rules: &GameRules) {
        self.enemies = rules
            .spawns
            .iter()
            .filter(|s| self.spawn_unlocked(s))
            .map(|spawn| Enemy {
                id: spawn.id.clone(),
                kind: spawn.kind.clone(),
                home: spawn.position.into(),
                position: spawn.position.into(),
                hp: rules.enemy(&spawn.kind).hp,
                state: EnemyState::Idle,
                heavy_timer: rules.ai.heavy_interval,
                is_boss: rules.enemy(&spawn.kind).boss,
                path: VecDeque::new(),
                path_timer: 0.0,
                path_target: spawn.position.into(),
                patrol_clock: 0.0,
            })
            .collect();
        self.enemies.sort_by(|a, b| a.id.cmp(&b.id));
    }

    fn spawn_unlocked(&self, spawn: &super::config::EnemySpawn) -> bool {
        if spawn.kind == "bamboo_beast" {
            return self.progress.stage == StoryStage::Challenge;
        }
        spawn.required_stage.is_none_or(|stage| {
            self.progress.stage == StoryStage::Completed && self.progress.journey.stage == stage
        })
    }

    fn sync_unlocked_enemies(&mut self, rules: &GameRules) {
        for spawn in &rules.spawns {
            if self.spawn_unlocked(spawn) && !self.enemies.iter().any(|e| e.id == spawn.id) {
                self.enemies.push(Enemy {
                    id: spawn.id.clone(),
                    kind: spawn.kind.clone(),
                    home: spawn.position.into(),
                    position: spawn.position.into(),
                    hp: rules.enemy(&spawn.kind).hp,
                    state: EnemyState::Idle,
                    heavy_timer: rules.ai.heavy_interval,
                    is_boss: rules.enemy(&spawn.kind).boss,
                    path: VecDeque::new(),
                    path_timer: 0.0,
                    path_target: spawn.position.into(),
                    patrol_clock: 0.0,
                });
            }
        }
        self.enemies.sort_by(|a, b| a.id.cmp(&b.id));
    }

    pub fn rebuild_map(&mut self, world: &WorldConfig, rules: &GameRules) -> CollisionMap {
        let map = collision_map(world, self.progress.stage, &self.bamboo);
        self.nav = NavGrid::new(&map, Some(&world.safe_zone), rules.ai.radius);
        for enemy in &mut self.enemies {
            enemy.path.clear();
            enemy.path_timer = 0.0;
        }
        self.map_dirty = false;
        map
    }

    pub fn notify(&mut self, message: impl Into<String>) {
        self.notice = message.into();
        self.log(super::messages::Channel::System, self.notice.clone());
        self.notice_remaining = 4.0;
    }

    fn effect(&mut self, position: Vec2, kind: EffectKind, amount: u32) {
        self.effects.push(Effect {
            id: self.next_effect,
            position,
            kind,
            amount,
            remaining: 0.8,
        });
        self.next_effect += 1;
    }

    fn experience(&mut self, amount: u32, rules: &GameRules) {
        if self.progress.gain_exp(amount, &rules.player) {
            self.effect(
                self.position,
                EffectKind::LevelUp,
                rules.player.level(self.progress.total_exp),
            );
            self.notify("修为提升！生命和体力已恢复");
            self.auto_save = true;
        }
        self.dirty = true;
    }

    fn face_lock(&mut self) {
        if let Some(enemy) = self
            .enemies
            .iter()
            .find(|e| self.locked.as_ref() == Some(&e.id) && e.hp > 0)
        {
            let delta = enemy.position - self.position;
            self.yaw = (-delta.x).atan2(-delta.y);
        }
    }

    fn begin_melee(&mut self, stage: usize) {
        self.face_lock();
        self.action = PlayerAction::Melee {
            stage,
            elapsed: 0.0,
            hit: false,
            queued: false,
        };
        self.effect(self.position, EffectKind::Swing, stage as u32 + 1);
    }

    pub fn request(&mut self, input: CombatInput, rules: &GameRules, map: &CollisionMap) {
        if self.progress.hp == 0 {
            return;
        }
        if input.lock {
            self.cycle_lock(map);
        }
        if input.potion {
            self.use_potion(rules);
        }
        if input.attack && self.progress.armed() {
            match &mut self.action {
                PlayerAction::Idle => {
                    self.begin_melee(if self.combo_idle <= rules.combo.reset_after {
                        self.combo_next
                    } else {
                        0
                    })
                }
                PlayerAction::Melee {
                    elapsed, queued, ..
                } if *elapsed >= rules.combo.duration - rules.combo.buffer => *queued = true,
                _ => {}
            }
        } else if (input.attack || input.energy || input.skill.is_some()) && !self.progress.armed()
        {
            self.notify(if self.progress.stage.sword_bound() {
                "未装备武器，按C打开角色面板装备武器"
            } else {
                "浮仙剑尚未认主，先完成杂役与残剑任务"
            });
        }
        if !matches!(self.action, PlayerAction::Idle) {
            return;
        }
        if let Some(skill) = input.skill {
            self.cast_skill(skill, rules, map);
            return;
        }
        if input.energy && self.progress.armed() {
            if self.energy_cooldown > 1e-5 {
                self.notify("剑气尚在冷却");
            } else if self.progress.stamina + 1e-5 < rules.sword_energy.cost {
                self.notify("体力不足，剑气需要30体力");
            } else {
                self.face_lock();
                self.progress.stamina -= rules.sword_energy.cost;
                self.regen_wait = rules.player.regen_delay;
                self.energy_cooldown = rules.sword_energy.cooldown;
                self.action = PlayerAction::Energy {
                    elapsed: 0.0,
                    hit: false,
                };
                self.effect(self.position, EffectKind::Energy, 0);
                self.dirty = true;
            }
        } else if input.dodge {
            if self.progress.stamina + 1e-5 < rules.dodge.cost {
                self.notify("体力不足，闪避需要25体力");
            } else {
                let direction = if input.direction.length_squared() > 0.0 {
                    input.direction.normalize()
                } else {
                    Vec2::new(-self.yaw.sin(), -self.yaw.cos())
                };
                self.progress.stamina -= rules.dodge.cost;
                self.regen_wait = rules.player.regen_delay;
                self.action = PlayerAction::Dodge {
                    elapsed: 0.0,
                    direction,
                };
                self.effect(self.position, EffectKind::Dodge, 0);
                self.dirty = true;
            }
        }
    }

    fn cast_skill(&mut self, skill: Skill, rules: &GameRules, map: &CollisionMap) {
        if skill == Skill::Energy {
            self.request(
                CombatInput {
                    energy: true,
                    ..default()
                },
                rules,
                map,
            );
            return;
        }
        if self.progress.hp == 0 || !matches!(self.action, PlayerAction::Idle) {
            return;
        }
        if !self.progress.stage.sword_bound() {
            self.notify("浮仙剑尚未认主，先完成杂役与残剑任务");
            return;
        }
        if !self.progress.armed() {
            self.notify("未装备武器，按C打开角色面板装备武器");
            return;
        }
        if self.progress.martial.ranks[skill.index()] == 0 {
            self.notify(format!("{}尚未学习，按K查看武学", skill.label()));
            return;
        }
        let index = skill.index() - 1;
        let (cost, cooldown) = match skill {
            Skill::Piercing => (rules.skills.piercing.cost, rules.skills.piercing.cooldown),
            Skill::Guard => (rules.skills.guard.cost, rules.skills.guard.cooldown),
            Skill::Mend => (rules.skills.mend.cost, rules.skills.mend.cooldown),
            Skill::Energy => unreachable!(),
        };
        if self.skill_cooldowns[index] > 1e-5 {
            self.notify(format!("{}尚在冷却", skill.label()));
        } else if self.progress.stamina + 1e-5 < cost {
            self.notify(format!("体力不足，{}需要{cost:.0}体力", skill.label()));
        } else if skill == Skill::Mend
            && self.progress.hp == rules.player.max_hp(self.progress.total_exp)
        {
            self.notify("生命已满，无需回春");
        } else {
            self.face_lock();
            self.progress.stamina -= cost;
            self.regen_wait = rules.player.regen_delay;
            self.skill_cooldowns[index] = cooldown;
            self.action = PlayerAction::Skill {
                skill,
                elapsed: 0.0,
                hit: false,
            };
            self.effect(self.position, EffectKind::Energy, 0);
            self.dirty = true;
        }
    }

    pub fn use_potion(&mut self, rules: &GameRules) {
        let error = if self.progress.hp == 0 {
            Some("死亡时不能用药")
        } else if !matches!(self.action, PlayerAction::Idle) {
            Some("动作期间不能用药")
        } else if self.progress.hp == rules.player.max_hp(self.progress.total_exp) {
            Some("生命已满")
        } else if self.potion_cooldown > 1e-5 {
            Some("药品尚在冷却")
        } else if self.progress.inventory.count(Item::HealingPotion) == 0 {
            Some("没有金疮药")
        } else {
            None
        };
        if let Some(error) = error {
            self.notify(error);
            return;
        }
        self.progress
            .inventory
            .remove(Item::HealingPotion, 1)
            .expect("checked potion count");
        let old = self.progress.hp;
        self.progress.hp = self
            .progress
            .hp
            .saturating_add(rules.potion.healing)
            .min(rules.player.max_hp(self.progress.total_exp));
        self.potion_cooldown = rules.potion.cooldown;
        self.effect(self.position, EffectKind::Heal, self.progress.hp - old);
        self.dirty = true;
    }

    fn cycle_lock(&mut self, map: &CollisionMap) {
        let mut candidates = self
            .enemies
            .iter()
            .filter(|e| {
                e.hp > 0
                    && e.position.distance(self.position) <= 12.0
                    && sight(self.position, e.position, map, false)
            })
            .collect::<Vec<_>>();
        candidates.sort_by(|a, b| {
            a.position
                .distance_squared(self.position)
                .total_cmp(&b.position.distance_squared(self.position))
                .then_with(|| a.id.cmp(&b.id))
        });
        self.locked = if candidates.is_empty() {
            None
        } else {
            let next = candidates
                .iter()
                .position(|e| self.locked.as_ref() == Some(&e.id))
                .map_or(0, |i| (i + 1) % candidates.len());
            Some(candidates[next].id.clone())
        };
        self.lock_obstructed = 0.0;
    }

    fn player_hit(
        &mut self,
        skill: Option<Skill>,
        stage: usize,
        rules: &GameRules,
        map: &CollisionMap,
    ) {
        let (range, half_angle, damage) = if let Some(skill) = skill {
            let cast = if skill == Skill::Energy {
                &rules.sword_energy
            } else {
                &rules.skills.piercing
            };
            (
                cast.range,
                if skill == Skill::Energy {
                    180.0
                } else {
                    rules.skills.piercing_half_angle
                },
                cast.base_damage
                    + cast.damage_per_level * (rules.player.level(self.progress.total_exp) - 1)
                    + rules.skills.energy_rank_damage
                        * u32::from(self.progress.martial.ranks[skill.index()] - 1),
            )
        } else {
            (
                rules.combo.range,
                rules.combo.half_angle,
                (self.progress.attack(rules) as f32 * rules.combo.multipliers[stage]).floor()
                    as u32,
            )
        };
        let candidates = self
            .enemies
            .iter()
            .enumerate()
            .filter(|(_, e)| {
                e.hp > 0
                    && in_sector(self.position, self.yaw, e.position, range, half_angle)
                    && sight(self.position, e.position, map, false)
            })
            .map(|(i, _)| i)
            .collect::<Vec<_>>();
        let has_enemy = !candidates.is_empty();
        let mut journey_changed = false;
        for i in candidates {
            let (position, dead, boss, exp, dealt) = {
                let enemy = &mut self.enemies[i];
                let dealt = damage.min(enemy.hp);
                enemy.hp = enemy.hp.saturating_sub(damage);
                if enemy.hp == 0 {
                    enemy.state = EnemyState::Dead(rules.ai.respawn);
                }
                (
                    enemy.position,
                    enemy.hp == 0,
                    enemy.kind == "bamboo_beast",
                    rules.enemy(&enemy.kind).exp,
                    dealt,
                )
            };
            self.effect(position, EffectKind::Damage, dealt);
            self.log(
                super::messages::Channel::Combat,
                format!(
                    "命中{}，造成{dealt}伤害",
                    rules.enemy(&self.enemies[i].kind).label
                ),
            );
            if dead {
                self.experience(exp, rules);
                let kind = self.enemies[i].kind.clone();
                if self.progress.journey_kill(&kind, &rules.journey) {
                    journey_changed = true;
                    self.auto_save = true;
                    self.notify(self.progress.journey.stage.objective());
                }
                match kind.as_str() {
                    "boar" => {
                        self.progress.adventure.boars_defeated =
                            self.progress.adventure.boars_defeated.saturating_add(1);
                    }
                    "mountain_wolf" => {
                        self.progress.adventure.wolves_defeated =
                            self.progress.adventure.wolves_defeated.saturating_add(1);
                    }
                    _ => {}
                }
                for loot in &rules.enemy(&kind).loot {
                    self.drops.push(Drop {
                        id: self.next_drop,
                        position,
                        item: loot.item,
                        count: loot.count,
                    });
                    self.next_drop += 1;
                }
                if boss && self.progress.stage == StoryStage::Challenge {
                    self.progress.stage = StoryStage::ReturnToOutpost;
                    self.auto_save = true;
                    self.notify("竹林凶兽已被击败，回工棚向曹斌复命");
                }
            }
        }
        if journey_changed {
            self.sync_unlocked_enemies(rules);
        }
        if skill.is_none() && !has_enemy && self.progress.armed() {
            let node = self
                .bamboo
                .iter()
                .enumerate()
                .filter(|(_, n)| {
                    n.remaining == 0.0
                        && in_sector(
                            self.position,
                            self.yaw,
                            n.position,
                            range,
                            rules.combo.half_angle,
                        )
                        && sight(self.position, n.position, map, true)
                })
                .min_by(|(_, a), (_, b)| {
                    a.position
                        .distance_squared(self.position)
                        .total_cmp(&b.position.distance_squared(self.position))
                        .then_with(|| a.id.cmp(&b.id))
                })
                .map(|(i, _)| i);
            if let Some(i) = node {
                let node = &mut self.bamboo[i];
                node.hits += 1;
                let position = node.position;
                if node.hits == rules.gathering.hits {
                    self.progress.adventure.bamboo_harvested =
                        self.progress.adventure.bamboo_harvested.saturating_add(1);
                    node.remaining = rules.gathering.respawn;
                    self.drops.push(Drop {
                        id: self.next_drop,
                        position,
                        item: Item::LinglongBamboo,
                        count: 1,
                    });
                    self.next_drop += 1;
                    self.map_dirty = true;
                }
                self.effect(position, EffectKind::Gather, rules.gathering.exp_per_hit);
                self.experience(rules.gathering.exp_per_hit, rules);
                self.notify("剑中气流涌入……挥剑，真的能让我变强。+10经验");
            }
        }
    }

    pub fn tick(
        &mut self,
        dt: f32,
        rules: &GameRules,
        world: &WorldConfig,
        map: &CollisionMap,
        player_radius: f32,
    ) {
        assert!(
            dt > 0.0 && dt <= 0.034,
            "combat requires a bounded fixed step"
        );
        self.notice_remaining = (self.notice_remaining - dt).max(0.0);
        self.effects
            .iter_mut()
            .for_each(|effect| effect.remaining -= dt);
        self.effects.retain(|effect| effect.remaining > 0.0);
        if self.progress.hp == 0 {
            self.action = PlayerAction::Dead;
            self.movement_blocked = true;
            return;
        }
        self.movement_blocked = !self.action.allows_movement();
        self.energy_cooldown = (self.energy_cooldown - dt).max(0.0);
        for cooldown in &mut self.skill_cooldowns {
            *cooldown = (*cooldown - dt).max(0.0);
        }
        self.guard_remaining = (self.guard_remaining - dt).max(0.0);
        self.potion_cooldown = (self.potion_cooldown - dt).max(0.0);
        let wait = self.regen_wait;
        self.regen_wait = (wait - dt).max(0.0);
        let regeneration_time = (dt - wait).clamp(0.0, dt);
        let old_stamina = self.progress.stamina;
        self.progress.stamina = (self.progress.stamina
            + regeneration_time * rules.player.stamina_regen)
            .min(rules.player.stamina);
        if self.progress.stamina != old_stamina {
            self.dirty = true;
        }
        let mut hit = None;
        self.action = match self.action.clone() {
            PlayerAction::Idle => {
                self.combo_idle += dt;
                PlayerAction::Idle
            }
            PlayerAction::Melee {
                stage,
                elapsed,
                hit: did_hit,
                queued,
            } => {
                let next = elapsed + dt;
                let hit_now = !did_hit && next + 1e-6 >= rules.combo.hit_at;
                if hit_now {
                    hit = Some((None, stage));
                }
                if next + 1e-6 >= rules.combo.duration {
                    self.combo_next = (stage + 1) % 3;
                    self.combo_idle = 0.0;
                    if queued {
                        self.face_lock();
                        self.effect(self.position, EffectKind::Swing, self.combo_next as u32 + 1);
                        PlayerAction::Melee {
                            stage: self.combo_next,
                            elapsed: (next - rules.combo.duration).max(0.0),
                            hit: false,
                            queued: false,
                        }
                    } else {
                        PlayerAction::Idle
                    }
                } else {
                    PlayerAction::Melee {
                        stage,
                        elapsed: next,
                        hit: did_hit || hit_now,
                        queued,
                    }
                }
            }
            PlayerAction::Energy {
                elapsed,
                hit: did_hit,
            } => {
                let next = elapsed + dt;
                let hit_now = !did_hit && next + 1e-6 >= rules.sword_energy.hit_at;
                if hit_now {
                    hit = Some((Some(Skill::Energy), 0));
                }
                if next + 1e-6 >= rules.sword_energy.duration {
                    PlayerAction::Idle
                } else {
                    PlayerAction::Energy {
                        elapsed: next,
                        hit: did_hit || hit_now,
                    }
                }
            }
            PlayerAction::Skill {
                skill,
                elapsed,
                hit: did_hit,
            } => {
                let (duration, hit_at) = match skill {
                    Skill::Piercing => {
                        (rules.skills.piercing.duration, rules.skills.piercing.hit_at)
                    }
                    Skill::Guard => (rules.skills.guard.duration, rules.skills.guard.hit_at),
                    Skill::Mend => (rules.skills.mend.duration, rules.skills.mend.hit_at),
                    Skill::Energy => unreachable!("energy has its own action"),
                };
                let next = elapsed + dt;
                let hit_now = !did_hit && next + 1e-6 >= hit_at;
                if hit_now {
                    let rank = u32::from(self.progress.martial.ranks[skill.index()] - 1);
                    match skill {
                        Skill::Piercing => hit = Some((Some(skill), 0)),
                        Skill::Guard => {
                            self.guard_remaining = rules.skills.guard_duration;
                            self.effect(self.position, EffectKind::Energy, 0);
                        }
                        Skill::Mend => {
                            let old = self.progress.hp;
                            self.progress.hp = (old
                                + rules.skills.mend.power
                                + rules.skills.mend.power_per_rank * rank)
                                .min(rules.player.max_hp(self.progress.total_exp));
                            self.effect(self.position, EffectKind::Heal, self.progress.hp - old);
                            self.dirty = true;
                        }
                        Skill::Energy => unreachable!(),
                    }
                }
                if next + 1e-6 >= duration {
                    PlayerAction::Idle
                } else {
                    PlayerAction::Skill {
                        skill,
                        elapsed: next,
                        hit: did_hit || hit_now,
                    }
                }
            }
            PlayerAction::Dodge { elapsed, direction } => {
                let step = dt.min(rules.dodge.duration - elapsed).max(0.0);
                self.position = move_circle(
                    self.position,
                    direction * rules.dodge.distance * step / rules.dodge.duration,
                    player_radius,
                    map,
                );
                if elapsed + dt + 1e-6 >= rules.dodge.duration {
                    PlayerAction::Idle
                } else {
                    PlayerAction::Dodge {
                        elapsed: elapsed + dt,
                        direction,
                    }
                }
            }
            PlayerAction::Dead => PlayerAction::Dead,
        };
        if let Some((energy, stage)) = hit {
            self.player_hit(energy, stage, rules, map);
        }
        self.tick_enemies(dt, rules, world, map);
        for node in &mut self.bamboo {
            if node.remaining > 0.0 {
                node.remaining = (node.remaining - dt).max(0.0);
                if node.remaining == 0.0 {
                    if self.position.distance(node.position) < rules.gathering.exclusion_distance {
                        node.remaining = dt;
                    } else {
                        node.hits = 0;
                        self.map_dirty = true;
                    }
                }
            }
        }
        if let Some(enemy) = self
            .enemies
            .iter()
            .find(|e| self.locked.as_ref() == Some(&e.id))
        {
            if sight(self.position, enemy.position, map, false) {
                self.lock_obstructed = 0.0;
            } else {
                self.lock_obstructed += dt;
            }
            if enemy.hp == 0
                || enemy.position.distance(self.position) > 15.0
                || self.lock_obstructed > 1.0
            {
                self.locked = None;
            }
        }
    }

    fn tick_enemies(
        &mut self,
        dt: f32,
        rules: &GameRules,
        world: &WorldConfig,
        map: &CollisionMap,
    ) {
        let safe = self.position.distance(world.safe_zone.center.into()) <= world.safe_zone.radius;
        let mut hits = Vec::new();
        let mut windups = Vec::new();
        for enemy in &mut self.enemies {
            let rule = rules.enemy(&enemy.kind);
            let distance = enemy.position.distance(self.position);
            enemy.heavy_timer = (enemy.heavy_timer - dt).max(0.0);
            enemy.path_timer = (enemy.path_timer - dt).max(0.0);
            if let EnemyState::Dead(remaining) = enemy.state {
                let next = (remaining - dt).max(0.0);
                if !enemy.boss()
                    && next == 0.0
                    && enemy.home.distance(self.position) >= rules.ai.exclusion_distance
                {
                    enemy.position = enemy.home;
                    enemy.hp = rule.hp;
                    enemy.state = EnemyState::Idle;
                    enemy.path.clear();
                } else {
                    enemy.state = EnemyState::Dead(next);
                }
                continue;
            }
            if self.progress.hp == 0
                || safe
                || enemy.position.distance(enemy.home) > rules.ai.leash
                || enemy.boss() && self.position.distance(enemy.home) > rules.ai.leash
            {
                enemy.state = EnemyState::Return;
            }
            let mut target = None;
            enemy.state = match enemy.state {
                EnemyState::Idle | EnemyState::Patrol => {
                    if !safe
                        && distance <= rules.ai.sense
                        && sight(enemy.position, self.position, map, false)
                    {
                        EnemyState::Chase
                    } else {
                        enemy.patrol_clock += dt * 0.4;
                        let patrol = enemy.home
                            + Vec2::new(enemy.patrol_clock.sin(), enemy.patrol_clock.cos()) * 2.0;
                        if !safe {
                            target = Some(patrol);
                        }
                        EnemyState::Patrol
                    }
                }
                EnemyState::Chase => {
                    let heavy_ready = enemy.boss() && enemy.heavy_timer == 0.0;
                    if distance
                        <= if heavy_ready {
                            rules.ai.heavy_range
                        } else {
                            rules.ai.range
                        }
                        && sight(enemy.position, self.position, map, false)
                    {
                        let heavy = heavy_ready;
                        if heavy {
                            enemy.heavy_timer = rules.ai.heavy_interval;
                        }
                        windups.push(enemy.position);
                        EnemyState::Windup {
                            elapsed: 0.0,
                            heavy,
                        }
                    } else {
                        target = Some(self.position);
                        EnemyState::Chase
                    }
                }
                EnemyState::Windup { elapsed, heavy } => {
                    let duration = if heavy {
                        rules.ai.heavy_windup
                    } else {
                        rules.ai.windup
                    };
                    if elapsed + dt + 1e-6 >= duration {
                        let range = if heavy {
                            rules.ai.heavy_range
                        } else {
                            rules.ai.range
                        };
                        if !safe
                            && self.progress.hp > 0
                            && distance <= range
                            && sight(enemy.position, self.position, map, false)
                        {
                            hits.push(if heavy {
                                rules.ai.heavy_damage.max(rule.damage + rule.damage / 2)
                            } else {
                                rule.damage
                            });
                        }
                        EnemyState::Recover(rules.ai.recovery)
                    } else {
                        EnemyState::Windup {
                            elapsed: elapsed + dt,
                            heavy,
                        }
                    }
                }
                EnemyState::Recover(remaining) => {
                    if remaining <= dt {
                        EnemyState::Chase
                    } else {
                        EnemyState::Recover(remaining - dt)
                    }
                }
                EnemyState::Return => {
                    if enemy.position.distance(enemy.home) < 0.2 {
                        enemy.position = enemy.home;
                        enemy.hp = rule.hp;
                        EnemyState::Idle
                    } else {
                        target = Some(enemy.home);
                        EnemyState::Return
                    }
                }
                EnemyState::Dead(remaining) => EnemyState::Dead(remaining),
            };
            if let Some(target) = target {
                if enemy.path_timer == 0.0 || enemy.path_target.distance_squared(target) >= 4.0 {
                    enemy.path = self.nav.path(enemy.position, target, map).into();
                    enemy.path_timer = 0.75;
                    enemy.path_target = target;
                }
                while enemy
                    .path
                    .front()
                    .is_some_and(|p| p.distance(enemy.position) < 0.1)
                {
                    enemy.path.pop_front();
                }
                if let Some(&point) = enemy.path.front() {
                    let speed = if matches!(enemy.state, EnemyState::Patrol) {
                        rule.speed * 0.4
                    } else {
                        rule.speed
                    };
                    let delta = (point - enemy.position).clamp_length_max(speed * dt);
                    let next = move_circle(enemy.position, delta, rules.ai.radius, map);
                    if !crosses_safe_zone(enemy.position, next, &world.safe_zone, rules.ai.radius) {
                        enemy.position = next;
                    }
                }
            }
        }
        for position in windups {
            self.effect(position, EffectKind::Windup, 0);
        }
        for damage in hits {
            if self.progress.hp == 0 {
                break;
            }
            if self.action.immune(rules) {
                continue;
            }
            let damage = damage.saturating_sub(self.progress.defense(rules)).max(1);
            let damage = if self.guard_remaining > 0.0 {
                let reduction = rules.skills.guard.power
                    + rules.skills.guard.power_per_rank
                        * u32::from(self.progress.martial.ranks[Skill::Guard.index()] - 1);
                (u64::from(damage) * u64::from(100 - reduction) / 100).max(1) as u32
            } else {
                damage
            };
            let damage = damage.min(self.progress.hp);
            self.progress.hp -= damage;
            self.effect(self.position, EffectKind::Hurt, damage);
            self.log(
                super::messages::Channel::Combat,
                format!(
                    "受到{damage}伤害，生命{}/{}",
                    self.progress.hp,
                    rules.player.max_hp(self.progress.total_exp)
                ),
            );
            self.dirty = true;
            if self.progress.hp == 0 {
                self.action = PlayerAction::Dead;
                self.locked = None;
                self.notify("你倒下了。返回工棚可保留任务、背包与修为。");
            }
        }
    }

    pub fn pickup(&mut self, map: &CollisionMap) -> Result<(), String> {
        if self.progress.hp == 0 {
            return Err("倒下时不能拾取".into());
        }
        let Some((index, _)) = self
            .drops
            .iter()
            .enumerate()
            .filter(|(_, d)| {
                d.position.distance(self.position) <= 2.0
                    && sight(self.position, d.position, map, false)
            })
            .min_by(|(_, a), (_, b)| {
                a.position
                    .distance_squared(self.position)
                    .total_cmp(&b.position.distance_squared(self.position))
                    .then(a.id.cmp(&b.id))
            })
        else {
            return Err("附近没有可拾取的掉落物".into());
        };
        let drop = &self.drops[index];
        let item = drop.item;
        let count = drop.count;
        self.progress.inventory.add(drop.item, drop.count)?;
        self.drops.remove(index);
        self.effect(self.position, EffectKind::Pickup, 1);
        self.dirty = true;
        self.auto_save = true;
        self.notify(format!("已拾取{} ×{}", item.label(), count));
        Ok(())
    }

    pub fn quest_changed(&mut self, rules: &GameRules) {
        self.map_dirty = true;
        self.dirty = true;
        self.auto_save = true;
        self.sync_unlocked_enemies(rules);
    }

    pub fn restore_scene(&mut self, rules: &GameRules) {
        self.reset_enemies(rules);
        self.auto_save = false;
        self.dirty = false;
        self.map_dirty = true;
        self.notice = "存档已恢复；普通敌人、竹与短期冷却已重置".into();
    }

    pub fn return_to_outpost(&mut self, world: &WorldConfig, rules: &GameRules) {
        self.progress.hp = rules.player.max_hp(self.progress.total_exp);
        self.progress.stamina = rules.player.stamina;
        self.position = Vec3::from_array(world.spawn).xz();
        self.yaw = 0.0;
        self.action = PlayerAction::Idle;
        self.movement_blocked = false;
        self.energy_cooldown = 0.0;
        self.skill_cooldowns = [0.0; 3];
        self.guard_remaining = 0.0;
        self.potion_cooldown = 0.0;
        self.combo_next = 0;
        self.combo_idle = 0.0;
        self.regen_wait = 0.0;
        self.locked = None;
        self.lock_obstructed = 0.0;
        self.drops.clear();
        self.effects.clear();
        for node in &mut self.bamboo {
            node.hits = 0;
            node.remaining = 0.0;
        }
        self.reset_enemies(rules);
        self.map_dirty = true;
        self.dirty = true;
        self.auto_save = true;
        self.notify("已返回工棚，任务和修为已保留");
    }
}

#[cfg(test)]
#[path = "combat_tests.rs"]
mod tests;
