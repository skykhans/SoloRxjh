use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use super::{config::GameRules, progress::Progress};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EquipmentSlot {
    Weapon,
    Armor,
}

impl EquipmentSlot {
    pub const ALL: [Self; 2] = [Self::Weapon, Self::Armor];

    pub fn label(self) -> &'static str {
        match self {
            Self::Weapon => "武器",
            Self::Armor => "护甲",
        }
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EquipmentDef {
    pub id: String,
    pub label: String,
    pub slot: EquipmentSlot,
    pub required_level: u32,
    pub attack: u32,
    pub defense: u32,
    pub attack_per_rank: u32,
    pub defense_per_rank: u32,
    pub max_rank: u8,
    pub buy_price: u32,
    pub sell_price: u32,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EquipmentRules {
    pub bag_slots: u8,
    pub starter_weapon: String,
    pub starter_armor: String,
    pub items: Vec<EquipmentDef>,
}

impl EquipmentRules {
    pub fn get(&self, id: &str) -> Option<&EquipmentDef> {
        self.items.iter().find(|item| item.id == id)
    }

    pub fn def(&self, id: &str) -> &EquipmentDef {
        self.get(id).expect("validated equipment reference")
    }

    pub fn shop(&self) -> impl Iterator<Item = (usize, &EquipmentDef)> {
        self.items
            .iter()
            .enumerate()
            .filter(|(_, item)| item.buy_price > 0)
    }

    pub fn validate(&self, max_level: u32) -> Result<(), String> {
        let mut ids = HashSet::new();
        if self.bag_slots == 0
            || self.items.len() < 4
            || self.items.iter().any(|item| {
                item.id.is_empty()
                    || !item
                        .id
                        .bytes()
                        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == b'_')
                    || !ids.insert(&item.id)
                    || item.label.trim().is_empty()
                    || item.required_level == 0
                    || item.required_level > max_level
                    || item.max_rank == 0
                    || item.max_rank > 3
                    || item.attack == 0
                        && item.defense == 0
                        && item.attack_per_rank == 0
                        && item.defense_per_rank == 0
                    || item.buy_price > 0 && item.sell_price > item.buy_price
            })
            || !self
                .items
                .iter()
                .any(|item| item.slot == EquipmentSlot::Weapon && item.buy_price > 0)
            || !self
                .items
                .iter()
                .any(|item| item.slot == EquipmentSlot::Armor && item.buy_price > 0)
        {
            return Err("装备定义、槽位、等级或价格非法".into());
        }
        for (id, slot) in [
            (&self.starter_weapon, EquipmentSlot::Weapon),
            (&self.starter_armor, EquipmentSlot::Armor),
        ] {
            let def = self
                .get(id)
                .ok_or_else(|| format!("初始装备不存在：{id}"))?;
            if def.slot != slot || def.required_level != 1 {
                return Err(format!("初始装备槽位或等级非法：{id}"));
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Equipment {
    pub id: String,
    pub rank: u8,
}

impl Equipment {
    pub fn new(id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            rank: 0,
        }
    }

    pub fn with_rank(id: impl Into<String>, rank: u8) -> Self {
        Self {
            id: id.into(),
            rank,
        }
    }

    pub fn display(&self, rules: &EquipmentRules) -> String {
        format!("{} +{}", rules.def(&self.id).label, self.rank)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Loadout {
    pub weapon: Option<Equipment>,
    pub armor: Option<Equipment>,
    pub bag: Vec<Equipment>,
}

impl Loadout {
    pub fn slot(&self, slot: EquipmentSlot) -> &Option<Equipment> {
        match slot {
            EquipmentSlot::Weapon => &self.weapon,
            EquipmentSlot::Armor => &self.armor,
        }
    }

    pub fn slot_mut(&mut self, slot: EquipmentSlot) -> &mut Option<Equipment> {
        match slot {
            EquipmentSlot::Weapon => &mut self.weapon,
            EquipmentSlot::Armor => &mut self.armor,
        }
    }

    pub fn full(&self, rules: &EquipmentRules) -> bool {
        self.bag.len() >= usize::from(rules.bag_slots)
    }
}

impl Progress {
    pub fn equipped(&self, slot: EquipmentSlot) -> Option<&Equipment> {
        self.loadout.slot(slot).as_ref()
    }

    pub fn armed(&self) -> bool {
        self.stage.sword_bound() && self.loadout.weapon.is_some()
    }

    pub fn equipment_bonus(&self, rules: &GameRules) -> (u32, u32) {
        let mut attack = 0;
        let mut defense = 0;
        for slot in EquipmentSlot::ALL {
            let Some(item) = self.loadout.slot(slot) else {
                continue;
            };
            let def = rules.equipment.def(&item.id);
            let rank = u32::from(item.rank);
            attack += def.attack + rank * def.attack_per_rank;
            defense += def.defense + rank * def.defense_per_rank;
        }
        (attack, defense)
    }

    pub fn attack(&self, rules: &GameRules) -> u32 {
        let (equipment, _) = self.equipment_bonus(rules);
        rules.player.attack(self.total_exp)
            + equipment
            + u32::from(self.sect.rank) * rules.sect.attack_per_rank
    }

    pub fn defense(&self, rules: &GameRules) -> u32 {
        let (_, equipment) = self.equipment_bonus(rules);
        equipment + u32::from(self.sect.rank) * rules.sect.defense_per_rank
    }

    pub fn grant_starter_weapon(&mut self, rules: &EquipmentRules) {
        self.loadout.weapon = Some(Equipment::new(rules.starter_weapon.clone()));
    }

    pub fn equip_from_bag(&mut self, index: usize, rules: &GameRules) -> Result<String, String> {
        let item = self
            .loadout
            .bag
            .get(index)
            .cloned()
            .ok_or("装备行囊中没有这一格")?;
        let def = rules
            .equipment
            .get(&item.id)
            .ok_or_else(|| format!("未知装备：{}", item.id))?;
        self.check_level(def, rules)?;
        let label = def.label.clone();
        let slot = def.slot;
        let mut next = self.clone();
        let previous = next.loadout.slot_mut(slot).replace(item);
        next.loadout.bag.remove(index);
        if let Some(previous) = previous {
            next.loadout.bag.insert(index, previous);
        }
        *self = next;
        Ok(format!("已装备{label}"))
    }

    pub fn unequip(&mut self, slot: EquipmentSlot, rules: &GameRules) -> Result<String, String> {
        let Some(item) = self.loadout.slot(slot).clone() else {
            return Err(format!("{}槽位没有装备", slot.label()));
        };
        if self.loadout.full(&rules.equipment) {
            return Err("装备行囊已满，先出售或整理".into());
        }
        let label = rules.equipment.def(&item.id).label.clone();
        let mut next = self.clone();
        *next.loadout.slot_mut(slot) = None;
        next.loadout.bag.push(item);
        *self = next;
        Ok(format!("已卸下{label}"))
    }

    pub fn add_equipment(&mut self, item: Equipment, rules: &EquipmentRules) -> Result<(), String> {
        rules
            .get(&item.id)
            .ok_or_else(|| format!("未知装备：{}", item.id))?;
        if self.loadout.full(rules) {
            return Err("装备行囊已满".into());
        }
        self.loadout.bag.push(item);
        Ok(())
    }

    pub fn validate_loadout(&self, rules: &GameRules) -> Result<(), String> {
        if self.loadout.bag.len() > usize::from(rules.equipment.bag_slots) {
            return Err("存档装备行囊超出格数".into());
        }
        for item in &self.loadout.bag {
            let def = rules
                .equipment
                .get(&item.id)
                .ok_or_else(|| format!("存档装备定义不存在：{}", item.id))?;
            if item.rank > def.max_rank {
                return Err("存档装备强化等级非法".into());
            }
        }
        for slot in EquipmentSlot::ALL {
            let Some(item) = self.loadout.slot(slot) else {
                continue;
            };
            let def = rules
                .equipment
                .get(&item.id)
                .ok_or_else(|| format!("存档装备定义不存在：{}", item.id))?;
            if def.slot != slot || item.rank > def.max_rank {
                return Err("存档装备槽位或强化等级非法".into());
            }
            self.check_level(def, rules)?;
        }
        if !self.stage.sword_owned()
            && (self.loadout.weapon.is_some() || !self.loadout.bag.is_empty())
        {
            return Err("尚未取剑的存档不能拥有其他装备".into());
        }
        Ok(())
    }

    pub(crate) fn check_level(&self, def: &EquipmentDef, rules: &GameRules) -> Result<(), String> {
        let level = rules.player.level(self.total_exp);
        if def.required_level > level {
            return Err(format!("{}需要{}级", def.label, def.required_level));
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "equipment_tests.rs"]
mod tests;
