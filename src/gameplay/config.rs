use std::{collections::HashSet, fs, path::Path};

use bevy::prelude::*;
use serde::Deserialize;

use crate::data::{ObjectKind, WorldConfig};

#[derive(Resource, Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameRules {
    pub player: PlayerRules,
    pub combo: ComboRules,
    pub sword_energy: EnergyRules,
    pub skills: super::skills::SkillRules,
    pub journey: super::journey::JourneyRules,
    pub sect: super::sect::SectRules,
    pub equipment: super::equipment::EquipmentRules,
    pub dodge: DodgeRules,
    pub potion: PotionRules,
    pub gathering: GatheringRules,
    pub ai: AiRules,
    pub enemies: Vec<EnemyRules>,
    pub spawns: Vec<EnemySpawn>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PlayerRules {
    pub base_hp: u32,
    pub hp_per_level: u32,
    pub base_attack: u32,
    pub attack_per_level: u32,
    pub exp_thresholds: Vec<u32>,
    pub stamina: f32,
    pub stamina_regen: f32,
    pub regen_delay: f32,
}

impl PlayerRules {
    pub fn level(&self, exp: u32) -> u32 {
        1 + self
            .exp_thresholds
            .iter()
            .filter(|&&threshold| exp >= threshold)
            .count() as u32
    }

    pub fn max_hp(&self, exp: u32) -> u32 {
        self.base_hp + (self.level(exp) - 1) * self.hp_per_level
    }

    pub fn attack(&self, exp: u32) -> u32 {
        self.base_attack + (self.level(exp) - 1) * self.attack_per_level
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ComboRules {
    pub duration: f32,
    pub hit_at: f32,
    pub buffer: f32,
    pub reset_after: f32,
    pub range: f32,
    pub half_angle: f32,
    pub multipliers: [f32; 3],
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnergyRules {
    pub duration: f32,
    pub hit_at: f32,
    pub range: f32,
    pub cost: f32,
    pub cooldown: f32,
    pub base_damage: u32,
    pub damage_per_level: u32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DodgeRules {
    pub duration: f32,
    pub distance: f32,
    pub cost: f32,
    pub immune_start: f32,
    pub immune_end: f32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PotionRules {
    pub healing: u32,
    pub cooldown: f32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GatheringRules {
    pub hits: u8,
    pub exp_per_hit: u32,
    pub respawn: f32,
    pub exclusion_distance: f32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AiRules {
    pub sense: f32,
    pub leash: f32,
    pub range: f32,
    pub windup: f32,
    pub recovery: f32,
    pub respawn: f32,
    pub exclusion_distance: f32,
    pub radius: f32,
    pub heavy_interval: f32,
    pub heavy_windup: f32,
    pub heavy_range: f32,
    pub heavy_damage: u32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnemyRules {
    pub id: String,
    pub level: u32,
    pub label: String,
    pub model: String,
    pub scale: f32,
    pub boss: bool,
    pub hp: u32,
    pub damage: u32,
    pub speed: f32,
    pub exp: u32,
    pub loot: Vec<super::progress::Stack>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnemySpawn {
    pub id: String,
    pub kind: String,
    pub position: [f32; 2],
    pub required_stage: Option<super::journey::JourneyStage>,
}

impl GameRules {
    pub fn load(assets: &Path, world: &WorldConfig) -> Result<Self, String> {
        let path = assets.join("config/gameplay.ron");
        let source =
            fs::read_to_string(&path).map_err(|error| format!("{}: {error}", path.display()))?;
        Self::parse(&source, world).map_err(|error| format!("{}: {error}", path.display()))
    }

    pub fn parse(source: &str, world: &WorldConfig) -> Result<Self, String> {
        let rules: Self = ron::from_str(source).map_err(|error| error.to_string())?;
        rules.validate(world)?;
        Ok(rules)
    }

    pub fn enemy(&self, id: &str) -> &EnemyRules {
        self.enemies
            .iter()
            .find(|rule| rule.id == id)
            .expect("validated enemy reference")
    }

    fn validate(&self, world: &WorldConfig) -> Result<(), String> {
        self.skills.validate(self)?;
        self.journey.validate(world, self)?;
        self.sect.validate()?;
        self.equipment
            .validate(self.player.exp_thresholds.len() as u32 + 1)?;
        let p = &self.player;
        let c = &self.combo;
        let s = &self.sword_energy;
        let d = &self.dodge;
        let a = &self.ai;
        let g = &self.gathering;
        let positive = [
            p.stamina,
            p.stamina_regen,
            p.regen_delay,
            c.duration,
            c.hit_at,
            c.buffer,
            c.reset_after,
            c.range,
            c.half_angle,
            s.duration,
            s.hit_at,
            s.range,
            s.cost,
            s.cooldown,
            d.duration,
            d.distance,
            d.cost,
            d.immune_start,
            d.immune_end,
            self.potion.cooldown,
            a.sense,
            a.leash,
            a.range,
            a.windup,
            a.recovery,
            a.respawn,
            a.exclusion_distance,
            a.radius,
            a.heavy_interval,
            a.heavy_windup,
            a.heavy_range,
            g.respawn,
            g.exclusion_distance,
        ];
        if positive
            .iter()
            .chain(c.multipliers.iter())
            .any(|x| !x.is_finite() || *x <= 0.0)
            || p.base_hp == 0
            || p.base_attack == 0
            || p.exp_thresholds.is_empty()
            || p.exp_thresholds[0] == 0
            || p.exp_thresholds.windows(2).any(|w| w[0] >= w[1])
            || p.exp_thresholds.len() > 20
            || p.hp_per_level
                .checked_mul(p.exp_thresholds.len() as u32)
                .and_then(|x| x.checked_add(p.base_hp))
                .is_none()
            || p.attack_per_level
                .checked_mul(p.exp_thresholds.len() as u32)
                .and_then(|x| x.checked_add(p.base_attack))
                .is_none()
            || c.hit_at >= c.duration
            || c.buffer > c.duration
            || c.half_angle > 180.0
            || s.hit_at >= s.duration
            || s.cost > p.stamina
            || d.cost > p.stamina
            || d.immune_start >= d.immune_end
            || d.immune_end > d.duration
            || s.base_damage == 0
            || self.potion.healing == 0
            || a.heavy_damage == 0
            || g.hits == 0
        {
            return Err("Invalid growth, action timeline, cost or gathering configuration".into());
        }
        let mut ids = HashSet::new();
        for enemy in &self.enemies {
            if !matches!(
                enemy.id.as_str(),
                "boar"
                    | "mountain_wolf"
                    | "bamboo_beast"
                    | "valley_boar"
                    | "valley_guardian"
                    | "frost_wolf"
                    | "frost_guardian"
            ) || !ids.insert(enemy.id.as_str())
                || enemy.label.trim().is_empty()
                || enemy.level == 0
                || enemy.level as usize > p.exp_thresholds.len() + 1
                || !matches!(
                    enemy.model.as_str(),
                    "boar" | "mountain_wolf" | "bamboo_beast"
                )
                || enemy.boss != (enemy.model == "bamboo_beast")
                || !enemy.scale.is_finite()
                || !(0.5..=2.0).contains(&enemy.scale)
                || enemy.hp == 0
                || enemy.damage == 0
                || !enemy.speed.is_finite()
                || enemy.speed <= 0.0
                || enemy.exp == 0
                || enemy.loot.is_empty()
                || enemy
                    .loot
                    .iter()
                    .any(|drop| drop.count == 0 || drop.count > super::progress::STACK_LIMIT)
            {
                return Err(format!("Invalid enemy type: {}", enemy.id));
            }
        }
        if ids.len() != 7 {
            return Err("All seven enemy types are required".into());
        }
        let mut spawn_ids = HashSet::new();
        for spawn in &self.spawns {
            let point = Vec2::from_array(spawn.position);
            let required = match spawn.kind.as_str() {
                "valley_guardian" => Some(super::journey::JourneyStage::ValleyBoss),
                "frost_guardian" => Some(super::journey::JourneyStage::NorthBoss),
                _ => None,
            };
            if spawn.id.is_empty()
                || !spawn_ids.insert(&spawn.id)
                || !ids.contains(spawn.kind.as_str())
                || spawn.required_stage != required
                || !point.is_finite()
                || point.abs().max_element() + a.radius >= world.map_size * 0.5
                || point.distance(world.safe_zone.center.into())
                    <= world.safe_zone.radius + a.radius
                || world.objects.iter().any(|object| {
                    object.kind.blocks_movement()
                        && object.bounds().overlaps_circle(point, a.radius)
                })
            {
                return Err(format!("Invalid or blocked enemy spawn: {}", spawn.id));
            }
        }
        if self.spawns.iter().filter(|s| s.kind == "boar").count() != 4
            || self
                .spawns
                .iter()
                .filter(|s| s.kind == "mountain_wolf")
                .count()
                != 4
            || self
                .spawns
                .iter()
                .filter(|s| s.kind == "bamboo_beast")
                .count()
                != 1
            || world
                .objects
                .iter()
                .filter(|o| o.kind == ObjectKind::Bamboo && o.id.starts_with("bamboo_"))
                .count()
                != 6
        {
            return Err("Expected 4 boars, 4 wolves, 1 boss and 6 gathering nodes".into());
        }
        Ok(())
    }
}
