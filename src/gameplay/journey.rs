use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use super::{
    config::GameRules,
    progress::{Item, Progress, StoryStage},
};
use crate::data::WorldConfig;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JourneyStage {
    #[default]
    ValleyHunt,
    ValleyBoss,
    ValleyReport,
    NorthHunt,
    NorthBoss,
    NorthReport,
    Completed,
}

impl JourneyStage {
    pub fn objective(self) -> &'static str {
        match self {
            Self::ValleyHunt => "Q004 云溪谷：清剿岩背野猪",
            Self::ValleyBoss => "Q004 云溪谷：击败溪谷兽王",
            Self::ValleyReport => "Q004 云溪谷：返回工棚向曹斌回报",
            Self::NorthHunt => "Q005 寒石古道：清剿霜牙山狼",
            Self::NorthBoss => "Q005 寒石古道：击败寒石巨兽",
            Self::NorthReport => "Q005 寒石古道：返回工棚向曹斌回报",
            Self::Completed => "江湖历练完成：可继续修炼、强化与接受狩猎委托",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JourneyProgress {
    pub stage: JourneyStage,
    pub kills: [u32; 2],
    pub repeat_claimed: [u32; 2],
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Region {
    pub id: String,
    pub label: String,
    pub center: [f32; 2],
    pub half_size: [f32; 2],
    pub entry: [f32; 2],
    pub recommended_level: u32,
}

impl Region {
    pub fn contains(&self, point: Vec2) -> bool {
        (point - Vec2::from_array(self.center))
            .abs()
            .cmple(self.half_size.into())
            .all()
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct JourneyRules {
    pub regions: [Region; 3],
    pub hunt_goals: [u32; 2],
    pub reward_silver: [u32; 2],
    pub reward_exp: [u32; 2],
    pub reward_potions: [u32; 2],
    pub repeat_goals: [u32; 2],
    pub repeat_silver: [u32; 2],
    pub repeat_exp: [u32; 2],
}

impl JourneyRules {
    pub fn validate(&self, world: &WorldConfig, rules: &GameRules) -> Result<(), String> {
        if self.hunt_goals.contains(&0)
            || self.repeat_goals.contains(&0)
            || self.repeat_silver.contains(&0)
            || self.repeat_exp.contains(&0)
            || self.reward_silver.contains(&0)
            || self.reward_exp.contains(&0)
            || self
                .reward_potions
                .iter()
                .any(|&n| n == 0 || n > super::progress::STACK_LIMIT)
        {
            return Err("历练目标或奖励非法".into());
        }
        let mut ids = std::collections::HashSet::new();
        for region in &self.regions {
            let center = Vec2::from_array(region.center);
            let half = Vec2::from_array(region.half_size);
            let entry = Vec2::from_array(region.entry);
            if region.id.is_empty()
                || !ids.insert(&region.id)
                || region.label.trim().is_empty()
                || !center.is_finite()
                || !half.is_finite()
                || half.min_element() <= 0.0
                || (center.abs() + half).max_element() >= world.map_size * 0.5
                || !entry.is_finite()
                || !region.contains(entry)
                || region.recommended_level == 0
                || region.recommended_level as usize > rules.player.exp_thresholds.len() + 1
                || world
                    .objects
                    .iter()
                    .any(|o| o.kind.blocks_movement() && o.bounds().overlaps_circle(entry, 0.5))
            {
                return Err(format!("区域位置、入口或等级非法：{}", region.id));
            }
        }
        for (i, a) in self.regions.iter().enumerate() {
            for b in &self.regions[i + 1..] {
                if (Vec2::from_array(a.center) - Vec2::from_array(b.center))
                    .abs()
                    .cmplt(Vec2::from_array(a.half_size) + Vec2::from_array(b.half_size))
                    .all()
                {
                    return Err("区域边界不能重叠".into());
                }
            }
        }
        Ok(())
    }
}

impl Progress {
    pub fn claim_hunt(&mut self, index: usize, rules: &GameRules) -> Result<String, String> {
        if index >= 2 {
            return Err("未知狩猎委托".into());
        }
        let required = [JourneyStage::NorthHunt, JourneyStage::Completed][index];
        if self.stage != StoryStage::Completed || self.journey.stage < required {
            return Err("先完成对应区域历练回报".into());
        }
        let next_count = self.journey.repeat_claimed[index]
            .checked_add(1)
            .ok_or("委托次数超出范围")?;
        if u64::from(self.journey.kills[index])
            < u64::from(next_count) * u64::from(rules.journey.repeat_goals[index])
        {
            return Err("新一轮狩猎数量不足".into());
        }
        let silver = self
            .silver
            .checked_add(rules.journey.repeat_silver[index])
            .ok_or("银两超出范围")?;
        self.silver = silver;
        self.gain_exp(rules.journey.repeat_exp[index], &rules.player);
        self.journey.repeat_claimed[index] = next_count;
        Ok(format!(
            "第{next_count}轮狩猎奖励：{}两、{}经验",
            rules.journey.repeat_silver[index], rules.journey.repeat_exp[index]
        ))
    }

    pub fn journey_kill(&mut self, kind: &str, rules: &JourneyRules) -> bool {
        if self.stage != StoryStage::Completed {
            return false;
        }
        let old = self.journey.stage;
        match kind {
            "valley_boar" => {
                self.journey.kills[0] = self.journey.kills[0].saturating_add(1);
                if old == JourneyStage::ValleyHunt && self.journey.kills[0] >= rules.hunt_goals[0] {
                    self.journey.stage = JourneyStage::ValleyBoss;
                }
            }
            "frost_wolf" => {
                self.journey.kills[1] = self.journey.kills[1].saturating_add(1);
                if old == JourneyStage::NorthHunt && self.journey.kills[1] >= rules.hunt_goals[1] {
                    self.journey.stage = JourneyStage::NorthBoss;
                }
            }
            "valley_guardian" if old == JourneyStage::ValleyBoss => {
                self.journey.stage = JourneyStage::ValleyReport
            }
            "frost_guardian" if old == JourneyStage::NorthBoss => {
                self.journey.stage = JourneyStage::NorthReport
            }
            _ => {}
        }
        old != self.journey.stage
    }

    pub fn report_journey(&mut self, rules: &GameRules) -> Result<String, String> {
        if self.stage != StoryStage::Completed {
            return Err("先完成千竹岭首章".into());
        }
        let (index, stage) = match self.journey.stage {
            JourneyStage::ValleyReport => (
                0,
                if self.journey.kills[1] >= rules.journey.hunt_goals[1] {
                    JourneyStage::NorthBoss
                } else {
                    JourneyStage::NorthHunt
                },
            ),
            JourneyStage::NorthReport => (1, JourneyStage::Completed),
            _ => return Err("当前历练尚未完成，不能回报或重复领奖".into()),
        };
        let mut next = self.clone();
        next.silver = next
            .silver
            .checked_add(rules.journey.reward_silver[index])
            .ok_or("银两超出范围")?;
        next.inventory
            .add(Item::HealingPotion, rules.journey.reward_potions[index])?;
        next.gain_exp(rules.journey.reward_exp[index], &rules.player);
        next.journey.stage = stage;
        *self = next;
        Ok(format!(
            "历练回报：{}两、{}经验、{}瓶金疮药",
            rules.journey.reward_silver[index],
            rules.journey.reward_exp[index],
            rules.journey.reward_potions[index]
        ))
    }

    pub fn validate_journey(&self, rules: &JourneyRules) -> Result<(), String> {
        let stage = self.journey.stage;
        if self
            .journey
            .repeat_claimed
            .iter()
            .enumerate()
            .any(|(i, &count)| {
                u64::from(count) * u64::from(rules.repeat_goals[i])
                    > u64::from(self.journey.kills[i])
                    || count > 0 && stage < [JourneyStage::NorthHunt, JourneyStage::Completed][i]
            })
            || self.stage != StoryStage::Completed && self.journey != JourneyProgress::default()
            || stage >= JourneyStage::ValleyBoss && self.journey.kills[0] < rules.hunt_goals[0]
            || stage >= JourneyStage::NorthBoss && self.journey.kills[1] < rules.hunt_goals[1]
            || stage == JourneyStage::ValleyHunt && self.journey.kills[0] >= rules.hunt_goals[0]
            || stage == JourneyStage::NorthHunt && self.journey.kills[1] >= rules.hunt_goals[1]
        {
            return Err("存档历练阶段与击败进度不一致".into());
        }
        Ok(())
    }
}
