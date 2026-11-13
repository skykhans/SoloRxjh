use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use super::{
    config::{GameRules, PlayerRules},
    equipment::{Equipment, EquipmentSlot, Loadout},
};

pub const INVENTORY_SLOTS: usize = 12;
pub const STACK_LIMIT: u32 = 99;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Item {
    HealingPotion,
    LinglongBamboo,
    BeastHide,
    WolfFang,
    SpiritOre,
}

impl Item {
    pub fn label(self) -> &'static str {
        match self {
            Self::HealingPotion => "金疮药",
            Self::LinglongBamboo => "玲珑竹材",
            Self::BeastHide => "兽皮",
            Self::WolfFang => "狼牙",
            Self::SpiritOre => "灵铁矿",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Stack {
    pub item: Item,
    pub count: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Inventory {
    pub stacks: Vec<Stack>,
}

impl Inventory {
    pub fn count(&self, item: Item) -> u32 {
        self.stacks
            .iter()
            .filter(|s| s.item == item)
            .map(|s| s.count)
            .sum()
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.stacks.len() > INVENTORY_SLOTS
            || self
                .stacks
                .iter()
                .any(|s| s.count == 0 || s.count > STACK_LIMIT)
            || self.stacks.windows(2).any(|w| w[0].item > w[1].item)
        {
            return Err("背包格数、排序或物品数量非法".into());
        }
        Ok(())
    }

    pub fn add(&mut self, item: Item, mut count: u32) -> Result<(), String> {
        self.validate()?;
        let mut next = self.clone();
        for stack in next.stacks.iter_mut().filter(|s| s.item == item) {
            let take = count.min(STACK_LIMIT - stack.count);
            stack.count += take;
            count -= take;
        }
        while count > 0 {
            if next.stacks.len() == INVENTORY_SLOTS {
                return Err("背包已满，请先使用药品或丢弃竹材".into());
            }
            let take = count.min(STACK_LIMIT);
            next.stacks.push(Stack { item, count: take });
            count -= take;
        }
        next.stacks.sort_by_key(|s| s.item);
        *self = next;
        Ok(())
    }

    pub fn remove(&mut self, item: Item, mut count: u32) -> Result<(), String> {
        if self.count(item) < count {
            return Err(format!("{}数量不足", item.label()));
        }
        for stack in self.stacks.iter_mut().filter(|s| s.item == item) {
            let take = stack.count.min(count);
            stack.count -= take;
            count -= take;
        }
        self.stacks.retain(|s| s.count > 0);
        Ok(())
    }
}

/// A single ordered stage is the source of truth for quest and sword/boss flags.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StoryStage {
    #[default]
    Report,
    TakeSword,
    BindSword,
    Gathering,
    Challenge,
    ReturnToOutpost,
    Completed,
}

impl StoryStage {
    pub fn sword_owned(self) -> bool {
        self >= Self::BindSword
    }
    pub fn sword_bound(self) -> bool {
        self >= Self::Gathering
    }
    pub fn boss_defeated(self) -> bool {
        self >= Self::ReturnToOutpost
    }
    pub fn gate_open(self) -> bool {
        self >= Self::Challenge
    }

    pub fn objective(self) -> &'static str {
        match self {
            Self::Report => "Q001 杂役与残剑：去工棚向曹斌报到",
            Self::TakeSword => "Q001 杂役与残剑：到工具架挑选残剑",
            Self::BindSword => "Q001 杂役与残剑：到东侧偏僻山涧认主",
            Self::Gathering => "Q002 挥剑有所得：砍竹，拾取3份竹材并向曹斌交差",
            Self::Challenge => "Q003 自己的修行路：到西北竹林深处击败凶兽",
            Self::ReturnToOutpost => "Q003 自己的修行路：返回工棚向曹斌复命",
            Self::Completed => "首章完成：可以继续探索、砍竹与修炼",
        }
    }
}

#[derive(Resource, Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct QuestRules {
    pub starting_potions: u32,
    pub bamboo_required: u32,
    pub bamboo_reward_exp: u32,
    pub bamboo_reward_silver: u32,
    pub bamboo_reward_potions: u32,
    pub chapter_reward_silver: u32,
    pub economy: EconomyRules,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EconomyRules {
    pub potion_price: u32,
    pub sell_prices: [u32; 4],
    pub sword_prices: [u32; 3],
    pub armor_prices: [u32; 3],
    pub upgrade_bamboo: [u32; 3],
    pub upgrade_ore: [u32; 3],
    pub commission_goals: [u32; 3],
    pub commission_silver: [u32; 3],
    pub commission_exp: [u32; 3],
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Adventure {
    pub boars_defeated: u32,
    pub wolves_defeated: u32,
    pub bamboo_harvested: u32,
    pub commissions_claimed: [bool; 3],
}

impl Adventure {
    pub fn commission_progress(&self) -> [u32; 3] {
        [
            self.boars_defeated,
            self.wolves_defeated,
            self.bamboo_harvested,
        ]
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Trade {
    BuyPotion,
    Sell(Item),
    UpgradeWeapon,
    UpgradeArmor,
    Commission(usize),
    BuyEquipment(usize),
    SellEquipment(usize),
}

impl QuestRules {
    pub fn load(assets: &std::path::Path) -> Result<Self, String> {
        let path = assets.join("config/quests.ron");
        let source =
            std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let rules: Self = ron::from_str(&source).map_err(|e| format!("{}: {e}", path.display()))?;
        if rules.starting_potions > STACK_LIMIT
            || rules.bamboo_required == 0
            || rules.bamboo_required > STACK_LIMIT
            || rules.bamboo_reward_potions > STACK_LIMIT
            || rules.economy.potion_price == 0
            || rules.economy.sell_prices.contains(&0)
            || rules.economy.sword_prices.contains(&0)
            || rules.economy.armor_prices.contains(&0)
            || rules
                .economy
                .upgrade_bamboo
                .iter()
                .any(|v| *v == 0 || *v > STACK_LIMIT)
            || rules.economy.commission_goals.contains(&0)
            || rules.economy.upgrade_ore.iter().any(|v| *v > STACK_LIMIT)
        {
            return Err(format!("{}: 非法任务数量", path.display()));
        }
        Ok(rules)
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Progress {
    pub total_exp: u32,
    pub hp: u32,
    pub stamina: f32,
    pub silver: u32,
    pub inventory: Inventory,
    pub stage: StoryStage,
    pub adventure: Adventure,
    pub loadout: Loadout,
    pub martial: super::skills::MartialProgress,
    pub journey: super::journey::JourneyProgress,
    pub sect: super::sect::SectProgress,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum QuestAction {
    Report,
    TakeSword,
    BindSword,
    DeliverBamboo,
    ReportVictory,
}

impl Progress {
    pub fn new(rules: &GameRules, quests: &QuestRules) -> Self {
        let mut inventory = Inventory::default();
        inventory
            .add(Item::HealingPotion, quests.starting_potions)
            .expect("validated starting items");
        Self {
            total_exp: 0,
            hp: rules.player.base_hp,
            stamina: rules.player.stamina,
            silver: 0,
            inventory,
            stage: StoryStage::Report,
            adventure: Adventure::default(),
            loadout: Loadout {
                weapon: None,
                armor: Some(Equipment::new(rules.equipment.starter_armor.clone())),
                bag: Vec::new(),
            },
            martial: super::skills::MartialProgress::default(),
            journey: super::journey::JourneyProgress::default(),
            sect: super::sect::SectProgress::default(),
        }
    }

    pub fn trade(
        &mut self,
        action: Trade,
        quests: &QuestRules,
        rules: &GameRules,
    ) -> Result<String, String> {
        if !self.stage.sword_bound() {
            return Err("先完成浮仙剑认主，再使用工棚补给与委托".into());
        }
        let mut next = self.clone();
        let economy = &quests.economy;
        let message = match action {
            Trade::BuyPotion => {
                next.silver = next
                    .silver
                    .checked_sub(economy.potion_price)
                    .ok_or("银两不足")?;
                next.inventory.add(Item::HealingPotion, 1)?;
                "购入1瓶金疮药".into()
            }
            Trade::Sell(item) => {
                let index = match item {
                    Item::LinglongBamboo => 0,
                    Item::BeastHide => 1,
                    Item::WolfFang => 2,
                    Item::SpiritOre => 3,
                    Item::HealingPotion => return Err("药品不能出售".into()),
                };
                if item == Item::LinglongBamboo
                    && next.stage == StoryStage::Gathering
                    && next.inventory.count(item) <= quests.bamboo_required
                {
                    return Err("先保留主线交差所需的3份竹材，只能出售多余材料".into());
                }
                next.inventory.remove(item, 1)?;
                next.silver = next
                    .silver
                    .checked_add(economy.sell_prices[index])
                    .ok_or("银两超出范围")?;
                format!("售出1份{}", item.label())
            }
            Trade::UpgradeWeapon | Trade::UpgradeArmor => {
                let slot = if action == Trade::UpgradeWeapon {
                    EquipmentSlot::Weapon
                } else {
                    EquipmentSlot::Armor
                };
                let item = next
                    .loadout
                    .slot(slot)
                    .clone()
                    .ok_or_else(|| format!("请先装备{}，再强化", slot.label()))?;
                let max_rank = rules.equipment.def(&item.id).max_rank;
                if item.rank >= max_rank {
                    return Err("已强化至本版上限".into());
                }
                let rank = usize::from(item.rank);
                let price = if slot == EquipmentSlot::Weapon {
                    economy.sword_prices[rank]
                } else {
                    economy.armor_prices[rank]
                };
                if next.stage == StoryStage::Gathering
                    && next.inventory.count(Item::LinglongBamboo)
                        < economy.upgrade_bamboo[rank] + quests.bamboo_required
                {
                    return Err("先保留主线交差所需竹材，再进行强化".into());
                }
                next.silver = next.silver.checked_sub(price).ok_or("银两不足")?;
                next.inventory
                    .remove(Item::LinglongBamboo, economy.upgrade_bamboo[rank])?;
                next.inventory
                    .remove(Item::SpiritOre, economy.upgrade_ore[rank])?;
                let item = next
                    .loadout
                    .slot_mut(slot)
                    .as_mut()
                    .expect("equipment checked above");
                item.rank += 1;
                format!(
                    "{}强化至+{}",
                    rules.equipment.def(&item.id).label,
                    item.rank
                )
            }
            Trade::BuyEquipment(index) => {
                let def = rules.equipment.items.get(index).ok_or("未知装备")?;
                if def.buy_price == 0 {
                    return Err(format!("{}不能在工棚购买", def.label));
                }
                next.check_level(def, rules)?;
                if next.loadout.full(&rules.equipment) {
                    return Err("装备行囊已满，先出售或整理".into());
                }
                next.silver = next.silver.checked_sub(def.buy_price).ok_or("银两不足")?;
                next.loadout.bag.push(Equipment::new(def.id.clone()));
                format!("购入{}", def.label)
            }
            Trade::SellEquipment(index) => {
                let item = next
                    .loadout
                    .bag
                    .get(index)
                    .cloned()
                    .ok_or("装备行囊中没有这一格")?;
                let def = rules.equipment.def(&item.id);
                if def.sell_price == 0 {
                    return Err(format!("{}不能出售", def.label));
                }
                next.silver = next
                    .silver
                    .checked_add(def.sell_price)
                    .ok_or("银两超出范围")?;
                next.loadout.bag.remove(index);
                format!("售出{}", def.label)
            }
            Trade::Commission(index) => {
                if index >= 3 {
                    return Err("未知委托".into());
                }
                if next.adventure.commissions_claimed[index] {
                    return Err("这份委托已经领取奖励".into());
                }
                if next.adventure.commission_progress()[index] < economy.commission_goals[index] {
                    return Err("委托目标尚未完成".into());
                }
                next.silver = next
                    .silver
                    .checked_add(economy.commission_silver[index])
                    .ok_or("银两超出范围")?;
                next.gain_exp(economy.commission_exp[index], &rules.player);
                next.adventure.commissions_claimed[index] = true;
                "工棚委托奖励已领取".into()
            }
        };
        *self = next;
        Ok(message)
    }

    pub fn gain_exp(&mut self, amount: u32, rules: &PlayerRules) -> bool {
        let old_level = rules.level(self.total_exp);
        self.total_exp = self
            .total_exp
            .saturating_add(amount)
            .min(*rules.exp_thresholds.last().expect("validated thresholds"));
        let leveled = rules.level(self.total_exp) > old_level;
        if leveled {
            self.hp = rules.max_hp(self.total_exp);
            self.stamina = rules.stamina;
        }
        leveled
    }

    pub fn apply_quest(
        &mut self,
        action: QuestAction,
        quests: &QuestRules,
        rules: &GameRules,
    ) -> Result<(), String> {
        let (required, next) = match action {
            QuestAction::Report => (StoryStage::Report, StoryStage::TakeSword),
            QuestAction::TakeSword => (StoryStage::TakeSword, StoryStage::BindSword),
            QuestAction::BindSword => (StoryStage::BindSword, StoryStage::Gathering),
            QuestAction::DeliverBamboo => (StoryStage::Gathering, StoryStage::Challenge),
            QuestAction::ReportVictory => (StoryStage::ReturnToOutpost, StoryStage::Completed),
        };
        if self.stage != required {
            return Err("任务阶段不符，不能重复领取或越序完成".into());
        }
        let mut transaction = self.clone();
        match action {
            QuestAction::TakeSword => transaction.grant_starter_weapon(&rules.equipment),
            QuestAction::DeliverBamboo => {
                transaction
                    .inventory
                    .remove(Item::LinglongBamboo, quests.bamboo_required)?;
                transaction
                    .inventory
                    .add(Item::HealingPotion, quests.bamboo_reward_potions)?;
                transaction.silver = transaction
                    .silver
                    .checked_add(quests.bamboo_reward_silver)
                    .ok_or("银两超出范围")?;
                transaction.gain_exp(quests.bamboo_reward_exp, &rules.player);
            }
            QuestAction::ReportVictory => {
                transaction.silver = transaction
                    .silver
                    .checked_add(quests.chapter_reward_silver)
                    .ok_or("银两超出范围")?;
            }
            _ => {}
        }
        transaction.stage = next;
        *self = transaction;
        Ok(())
    }
}
