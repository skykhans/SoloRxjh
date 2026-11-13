use super::*;
use crate::{
    data::load_configs,
    gameplay::progress::{Item, Progress, QuestRules, STACK_LIMIT, StoryStage, Trade},
};

fn fixture() -> (GameRules, QuestRules, Progress) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    let (world, _) = load_configs(&root).unwrap();
    let rules = GameRules::load(&root, &world).unwrap();
    let quests = QuestRules::load(&root).unwrap();
    let progress = Progress::new(&rules, &quests);
    (rules, quests, progress)
}

fn armed_progress(rules: &GameRules, quests: &QuestRules) -> Progress {
    let mut progress = Progress::new(rules, quests);
    progress.stage = StoryStage::Completed;
    progress.gain_exp(5000, &rules.player);
    progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
    progress
}

#[test]
fn shipped_equipment_configuration_is_valid_and_rejects_bad_definitions() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    let (world, _) = load_configs(&root).unwrap();
    let rules = GameRules::load(&root, &world).unwrap();
    assert_eq!(rules.equipment.bag_slots, 8);
    assert_eq!(
        rules.equipment.def("fuxian_sword").slot,
        EquipmentSlot::Weapon
    );
    assert_eq!(
        rules.equipment.def("menial_robe").slot,
        EquipmentSlot::Armor
    );
    assert!(rules.equipment.shop().count() >= 3);
    let source = include_str!("../../assets/config/gameplay.ron");
    for invalid in [
        source.replace("bag_slots: 8", "bag_slots: 0"),
        source.replace("max_rank: 3, buy_price: 12", "max_rank: 0, buy_price: 12"),
        source.replace("required_level: 7", "required_level: 11"),
        source.replace(
            "buy_price: 12, sell_price: 4",
            "buy_price: 4, sell_price: 12",
        ),
        source.replace(
            "starter_armor: \"menial_robe\"",
            "starter_armor: \"missing_armor\"",
        ),
        source.replace("id: \"ironwood_blade\"", "id: \"fuxian_sword\""),
    ] {
        assert!(GameRules::parse(&invalid, &world).is_err());
    }
}

#[test]
fn swapping_equipment_keeps_bag_size_and_changes_real_stats() {
    let (rules, quests, _) = fixture();
    let mut progress = armed_progress(&rules, &quests);
    progress
        .add_equipment(Equipment::new("refined_blade"), &rules.equipment)
        .unwrap();
    let before = progress.attack(&rules);
    let (equipment_attack, _) = progress.equipment_bonus(&rules);
    progress.equip_from_bag(0, &rules).unwrap();
    assert_eq!(
        progress.equipped(EquipmentSlot::Weapon).unwrap().id,
        "refined_blade"
    );
    assert_eq!(progress.loadout.bag.len(), 1);
    assert_eq!(progress.loadout.bag[0].id, "fuxian_sword");
    assert_eq!(
        progress.equipment_bonus(&rules).0,
        equipment_attack + rules.equipment.def("refined_blade").attack
    );
    assert_eq!(
        progress.attack(&rules),
        before + rules.equipment.def("refined_blade").attack
    );
    progress.validate_loadout(&rules).unwrap();
}

#[test]
fn equip_rejects_level_requirement_and_unknown_slots_without_changing_state() {
    let (rules, quests, progress) = fixture();
    let mut progress = progress;
    progress
        .add_equipment(Equipment::new("frost_edge"), &rules.equipment)
        .unwrap();
    let before = progress.clone();
    assert!(
        progress
            .equip_from_bag(0, &rules)
            .unwrap_err()
            .contains("需要7级")
    );
    assert_eq!(progress, before);
    assert!(progress.equip_from_bag(5, &rules).is_err());
    assert_eq!(progress, before);
    let mut low_level = Progress::new(&rules, &quests);
    low_level.stage = StoryStage::Gathering;
    low_level
        .add_equipment(Equipment::new("dark_iron_armor"), &rules.equipment)
        .unwrap();
    let before = low_level.clone();
    assert!(
        low_level
            .equip_from_bag(0, &rules)
            .unwrap_err()
            .contains("需要6级")
    );
    assert_eq!(low_level, before);
}

#[test]
fn unequipping_requires_bag_space_and_blocks_combat_without_weapon() {
    let (rules, quests, _) = fixture();
    let mut progress = armed_progress(&rules, &quests);
    assert!(progress.armed());
    for _ in 0..rules.equipment.bag_slots {
        progress
            .add_equipment(Equipment::new("ironwood_blade"), &rules.equipment)
            .unwrap();
    }
    let before = progress.clone();
    assert!(
        progress
            .unequip(EquipmentSlot::Weapon, &rules)
            .unwrap_err()
            .contains("装备行囊已满")
    );
    assert_eq!(progress, before);
    progress
        .trade(Trade::SellEquipment(0), &quests, &rules)
        .unwrap();
    progress.unequip(EquipmentSlot::Weapon, &rules).unwrap();
    assert!(progress.equipped(EquipmentSlot::Weapon).is_none());
    assert!(!progress.armed());
    assert_eq!(
        progress.loadout.bag.len(),
        usize::from(rules.equipment.bag_slots)
    );
    progress.validate_loadout(&rules).unwrap();
}

#[test]
fn buying_and_selling_equipment_commit_once_and_respect_limits() {
    let (rules, quests, _) = fixture();
    let mut progress = armed_progress(&rules, &quests);
    let index = |id: &str| {
        rules
            .equipment
            .items
            .iter()
            .position(|item| item.id == id)
            .unwrap()
    };
    let (quest_weapon, blade) = (index("fuxian_sword"), index("refined_blade"));
    progress.silver = 500;
    let before = progress.clone();
    assert!(
        progress
            .trade(Trade::BuyEquipment(quest_weapon), &quests, &rules)
            .is_err()
    );
    assert_eq!(progress, before);
    assert!(
        progress
            .trade(Trade::BuyEquipment(quest_weapon), &quests, &rules)
            .is_err()
    );
    assert_eq!(progress, before);
    let def = rules.equipment.def("refined_blade");
    progress
        .trade(Trade::BuyEquipment(blade), &quests, &rules)
        .unwrap();
    assert_eq!(progress.silver, 500 - def.buy_price);
    assert_eq!(progress.loadout.bag.len(), 1);
    progress
        .trade(Trade::SellEquipment(0), &quests, &rules)
        .unwrap();
    assert_eq!(progress.silver, 500 - def.buy_price + def.sell_price);
    assert!(progress.loadout.bag.is_empty());
    progress.silver = def.buy_price - 1;
    let before = progress.clone();
    assert!(
        progress
            .trade(Trade::BuyEquipment(blade), &quests, &rules)
            .is_err()
    );
    assert_eq!(progress, before);
    progress.silver = 1000;
    for _ in 0..rules.equipment.bag_slots {
        progress
            .trade(Trade::BuyEquipment(blade), &quests, &rules)
            .unwrap();
    }
    let before = progress.clone();
    assert!(
        progress
            .trade(Trade::BuyEquipment(blade), &quests, &rules)
            .is_err()
    );
    assert_eq!(progress, before);
}

#[test]
fn enhancement_targets_the_equipped_item_and_stops_at_its_limit() {
    let (rules, quests, _) = fixture();
    let mut progress = Progress::new(&rules, &quests);
    progress.stage = StoryStage::Completed;
    progress.silver = 1000;
    progress
        .inventory
        .add(Item::LinglongBamboo, STACK_LIMIT)
        .unwrap();
    progress.inventory.add(Item::SpiritOre, 10).unwrap();
    assert!(
        progress
            .trade(Trade::UpgradeWeapon, &quests, &rules)
            .is_err()
    );
    progress.loadout.weapon = Some(Equipment::new("ironwood_blade"));
    progress
        .trade(Trade::UpgradeWeapon, &quests, &rules)
        .unwrap();
    assert_eq!(progress.equipped(EquipmentSlot::Weapon).unwrap().rank, 1);
    progress
        .trade(Trade::UpgradeWeapon, &quests, &rules)
        .unwrap();
    progress
        .trade(Trade::UpgradeWeapon, &quests, &rules)
        .unwrap();
    let def = rules.equipment.def("ironwood_blade");
    assert_eq!(
        progress.equipped(EquipmentSlot::Weapon).unwrap().rank,
        def.max_rank
    );
    let before = progress.clone();
    assert!(
        progress
            .trade(Trade::UpgradeWeapon, &quests, &rules)
            .is_err()
    );
    assert_eq!(progress, before);
    assert_eq!(
        progress.equipment_bonus(&rules).0,
        def.attack + u32::from(def.max_rank) * def.attack_per_rank
    );
}

#[test]
fn invalid_loadouts_are_rejected_instead_of_repaired() {
    let (rules, quests, _) = fixture();
    let valid = armed_progress(&rules, &quests);
    valid.validate_loadout(&rules).unwrap();
    let mut too_high = valid.clone();
    too_high.loadout.bag = vec![Equipment::with_rank("ironwood_blade", 4)];
    let mut wrong_slot = valid.clone();
    wrong_slot.loadout.weapon = Some(Equipment::new("menial_robe"));
    let mut unknown = valid.clone();
    unknown.loadout.bag = vec![Equipment::new("unknown_blade")];
    let mut overflow = valid.clone();
    overflow.loadout.bag = vec![Equipment::new("ironwood_blade"); 9];
    let mut before_pickup = valid.clone();
    before_pickup.stage = StoryStage::Report;
    let mut locked_item = valid.clone();
    locked_item.total_exp = 0;
    locked_item.loadout.weapon = Some(Equipment::new("frost_edge"));
    for case in [
        too_high,
        wrong_slot,
        unknown,
        overflow,
        before_pickup,
        locked_item,
    ] {
        assert!(case.validate_loadout(&rules).is_err());
    }
}
