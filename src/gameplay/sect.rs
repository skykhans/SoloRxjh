use serde::{Deserialize, Serialize};

use super::{
    config::{GameRules, PlayerRules},
    journey::JourneyStage,
    progress::{Item, Progress, QuestRules, StoryStage},
};

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SectProgress {
    pub rank: u8,
    pub contribution: u32,
    pub earned: u32,
    pub commissions_claimed: [u32; 3],
}

impl SectProgress {
    pub fn title(&self) -> &'static str {
        match self.rank {
            0 => "杂役弟子",
            1 => "外门弟子",
            2 => "内门弟子",
            3 => "宗门执事",
            _ => unreachable!("validated sect rank"),
        }
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SectRules {
    pub promotion_costs: [u32; 3],
    pub promotion_levels: [u32; 3],
    pub donation_bamboo: u32,
    pub donation_contribution: u32,
    pub commission_goals: [u32; 3],
    pub commission_contribution: [u32; 3],
    pub potion_cost: u32,
    pub ore_cost: u32,
    pub attack_per_rank: u32,
    pub defense_per_rank: u32,
}

impl SectRules {
    pub fn validate(&self) -> Result<(), String> {
        if self.promotion_costs.contains(&0)
            || self
                .promotion_costs
                .iter()
                .try_fold(0u32, |a, &b| a.checked_add(b))
                .is_none()
            || self
                .promotion_levels
                .iter()
                .any(|&n| !(2..=10).contains(&n))
            || self.promotion_levels.windows(2).any(|w| w[0] >= w[1])
            || self.donation_bamboo == 0
            || self.donation_bamboo > 99
            || self.donation_contribution == 0
            || self.commission_goals.contains(&0)
            || self.commission_contribution.contains(&0)
            || self.potion_cost == 0
            || self.ore_cost == 0
            || self.attack_per_rank > 100
            || self.defense_per_rank > 100
        {
            return Err("门派晋升、贡献或兑换配置非法".into());
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SectAction {
    Donate,
    Promote,
    Potion,
    Ore,
    Commission(usize),
}

impl Progress {
    pub fn sect_action(
        &mut self,
        action: SectAction,
        quests: &QuestRules,
        rules: &GameRules,
    ) -> Result<String, String> {
        if !self.stage.sword_bound() {
            return Err("先完成浮仙剑认主，再办理宗门事务".into());
        }
        let mut next = self.clone();
        let sect = &rules.sect;
        let player = &rules.player;
        let reward = match action {
            SectAction::Donate => {
                let reserve = if next.stage == StoryStage::Gathering {
                    quests.bamboo_required
                } else {
                    0
                };
                if next.inventory.count(Item::LinglongBamboo) < sect.donation_bamboo + reserve {
                    return Err("可捐竹材不足，主线交差所需材料必须保留".into());
                }
                next.inventory
                    .remove(Item::LinglongBamboo, sect.donation_bamboo)?;
                sect.donation_contribution
            }
            SectAction::Commission(index) => {
                if index >= 3 {
                    return Err("未知宗门委托".into());
                }
                let count = next.sect.commissions_claimed[index]
                    .checked_add(1)
                    .ok_or("委托次数超出范围")?;
                if u64::from(next.adventure.commission_progress()[index])
                    < u64::from(count) * u64::from(sect.commission_goals[index])
                {
                    return Err("宗门委托的新一轮目标尚未完成".into());
                }
                next.sect.commissions_claimed[index] = count;
                sect.commission_contribution[index]
            }
            SectAction::Promote => {
                let rank = usize::from(next.sect.rank);
                if rank >= 3 {
                    return Err("已达到宗门晋升上限".into());
                }
                if player.level(next.total_exp) < sect.promotion_levels[rank] {
                    return Err("修为等级不足，尚不能晋升".into());
                }
                let chapter_ready = match rank {
                    0 => next.stage == StoryStage::Completed,
                    1 => next.journey.stage >= JourneyStage::NorthHunt,
                    2 => next.journey.stage == JourneyStage::Completed,
                    _ => unreachable!(),
                };
                if !chapter_ready {
                    return Err("先完成对应主线历练回报".into());
                }
                next.sect.contribution = next
                    .sect
                    .contribution
                    .checked_sub(sect.promotion_costs[rank])
                    .ok_or("宗门贡献不足")?;
                next.sect.rank += 1;
                0
            }
            SectAction::Potion | SectAction::Ore => {
                let (item, price) = if action == SectAction::Potion {
                    (Item::HealingPotion, sect.potion_cost)
                } else {
                    (Item::SpiritOre, sect.ore_cost)
                };
                next.sect.contribution = next
                    .sect
                    .contribution
                    .checked_sub(price)
                    .ok_or("宗门贡献不足")?;
                next.inventory.add(item, 1)?;
                0
            }
        };
        next.sect.contribution = next
            .sect
            .contribution
            .checked_add(reward)
            .ok_or("贡献超出范围")?;
        next.sect.earned = next
            .sect
            .earned
            .checked_add(reward)
            .ok_or("累计贡献超出范围")?;
        let message = match action {
            SectAction::Promote => format!("晋升为{}，攻击和防御已提升", next.sect.title()),
            SectAction::Potion => "已兑换1瓶金疮药".into(),
            SectAction::Ore => "已兑换1份灵铁矿".into(),
            _ => format!("获得{reward}宗门贡献"),
        };
        *self = next;
        Ok(message)
    }

    pub fn validate_sect(&self, rules: &SectRules, player: &PlayerRules) -> Result<(), String> {
        if self.sect.rank > 3 || !self.stage.sword_bound() && self.sect != SectProgress::default() {
            return Err("存档门派身份或认主状态非法".into());
        }
        let rank = usize::from(self.sect.rank);
        let spent: u32 = rules.promotion_costs[..rank].iter().sum();
        if self.sect.earned < spent
            || self.sect.contribution > self.sect.earned - spent
            || rank > 0
                && (player.level(self.total_exp) < rules.promotion_levels[rank - 1]
                    || self.stage != StoryStage::Completed)
            || rank > 1 && self.journey.stage < JourneyStage::NorthHunt
            || rank > 2 && self.journey.stage != JourneyStage::Completed
            || self
                .sect
                .commissions_claimed
                .iter()
                .enumerate()
                .any(|(i, &n)| {
                    u64::from(n) * u64::from(rules.commission_goals[i])
                        > u64::from(self.adventure.commission_progress()[i])
                })
        {
            return Err("存档门派贡献、晋升或委托进度非法".into());
        }
        Ok(())
    }
}
