use serde::{Deserialize, Serialize};

use super::{
    config::{EnergyRules, GameRules},
    progress::Progress,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Skill {
    Energy,
    Piercing,
    Guard,
    Mend,
}

impl Skill {
    pub const ALL: [Self; 4] = [Self::Energy, Self::Piercing, Self::Guard, Self::Mend];

    pub fn index(self) -> usize {
        self as usize
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Energy => "剑气",
            Self::Piercing => "穿云刺",
            Self::Guard => "护体诀",
            Self::Mend => "回春诀",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Energy => "Q",
            Self::Piercing => "R",
            Self::Guard => "G",
            Self::Mend => "V",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MartialProgress {
    pub ranks: [u8; 4],
}

impl Default for MartialProgress {
    fn default() -> Self {
        Self {
            ranks: [1, 0, 0, 0],
        }
    }
}

impl MartialProgress {
    pub fn spent(&self) -> u32 {
        self.ranks.iter().map(|&rank| u32::from(rank)).sum::<u32>() - 1
    }

    pub fn validate(&self, level: u32, rules: &SkillRules) -> Result<(), String> {
        if self.ranks[0] == 0 || self.ranks.iter().any(|&rank| rank > 3) {
            return Err("存档武学等级非法".into());
        }
        if self.spent() >= level
            || self.ranks[1..]
                .iter()
                .zip(rules.unlock_levels)
                .any(|(&rank, required)| rank > 0 && level < required)
        {
            return Err("存档武学超过等级或修行点限制".into());
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SupportRules {
    pub duration: f32,
    pub hit_at: f32,
    pub cost: f32,
    pub cooldown: f32,
    pub power: u32,
    pub power_per_rank: u32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SkillRules {
    pub unlock_levels: [u32; 3],
    pub training_prices: [u32; 3],
    pub energy_rank_damage: u32,
    pub piercing: EnergyRules,
    pub piercing_half_angle: f32,
    pub guard: SupportRules,
    pub guard_duration: f32,
    pub mend: SupportRules,
}

impl SkillRules {
    pub fn validate(&self, rules: &GameRules) -> Result<(), String> {
        let p = &self.piercing;
        if [
            p.duration,
            p.hit_at,
            p.range,
            p.cost,
            p.cooldown,
            self.piercing_half_angle,
            self.guard_duration,
        ]
        .iter()
        .any(|v| !v.is_finite() || *v <= 0.0)
            || p.hit_at >= p.duration
            || p.cost > rules.player.stamina
            || p.base_damage == 0
            || self.piercing_half_angle > 180.0
            || self.training_prices.contains(&0)
            || self
                .unlock_levels
                .iter()
                .any(|&level| level < 2 || level as usize > rules.player.exp_thresholds.len() + 1)
            || self.energy_rank_damage == 0
            || self.guard.power > 99
            || self.guard.power_per_rank > 49
            || self.guard.power + 2 * self.guard.power_per_rank >= 100
        {
            return Err("武学解锁、消耗或数值配置非法".into());
        }
        for support in [&self.guard, &self.mend] {
            if [
                support.duration,
                support.hit_at,
                support.cost,
                support.cooldown,
            ]
            .iter()
            .any(|v| !v.is_finite() || *v <= 0.0)
                || support.hit_at >= support.duration
                || support.cost > rules.player.stamina
                || support.power == 0
                || support.power > 10000
                || support.power_per_rank > 10000
            {
                return Err("辅助武学时间轴或数值非法".into());
            }
        }
        Ok(())
    }
}

impl Progress {
    pub fn learn_skill(&mut self, skill: Skill, rules: &GameRules) -> Result<String, String> {
        if !self.stage.sword_bound() {
            return Err("先完成浮仙剑认主".into());
        }
        let level = rules.player.level(self.total_exp);
        self.martial.validate(level, &rules.skills)?;
        let index = skill.index();
        let rank = self.martial.ranks[index];
        if rank == 3 {
            return Err("武学已满级".into());
        }
        if index > 0 && level < rules.skills.unlock_levels[index - 1] {
            return Err(format!(
                "{}需要等级{}",
                skill.label(),
                rules.skills.unlock_levels[index - 1]
            ));
        }
        if self.martial.spent() + 1 >= level {
            return Err("修行点不足，提升角色等级可获得修行点".into());
        }
        let silver = self
            .silver
            .checked_sub(rules.skills.training_prices[rank as usize])
            .ok_or("银两不足")?;
        self.silver = silver;
        self.martial.ranks[index] += 1;
        Ok(format!("{}提升至{}级", skill.label(), rank + 1))
    }
}
