use super::*;
use crate::gameplay::{equipment::EquipmentSlot, progress::Progress, sect::SectAction};

pub(super) fn build(
    p: &mut ChildSpawnerCommands,
    font: &Handle<Font>,
    panel: &Panel,
    progress: &Progress,
    rules: &GameRules,
    quests: &QuestRules,
    near: bool,
) {
    let e = &quests.economy;
    match panel {
        Panel::Character => {
            let level = rules.player.level(progress.total_exp);
            let (equipment_attack, equipment_defense) = progress.equipment_bonus(rules);
            for text in [
                format!("方尘 · 琉璃剑宗 · {} · 等级{level}", progress.sect.title()),
                format!(
                    "生命 {}/{}   体力 {:.0}/{}",
                    progress.hp,
                    rules.player.max_hp(progress.total_exp),
                    progress.stamina,
                    rules.player.stamina
                ),
                format!(
                    "攻击 {}（基础{} / 装备{} / 门派{}）",
                    progress.attack(rules),
                    rules.player.attack(progress.total_exp),
                    equipment_attack,
                    u32::from(progress.sect.rank) * rules.sect.attack_per_rank
                ),
                format!(
                    "防御 {}（装备{} / 门派{}）",
                    progress.defense(rules),
                    equipment_defense,
                    u32::from(progress.sect.rank) * rules.sect.defense_per_rank
                ),
                format!(
                    "修行点 {}   银两 {}   宗门贡献 {}",
                    level - 1 - progress.martial.spent(),
                    progress.silver,
                    progress.sect.contribution
                ),
            ] {
                p.spawn(label(text, 20.0, PAPER, font));
            }
            for slot in EquipmentSlot::ALL {
                let (text, action) = match progress.equipped(slot) {
                    Some(item) => (
                        format!(
                            "{}：{}（攻击+{} / 防御+{}）",
                            slot.label(),
                            item.display(&rules.equipment),
                            rules.equipment.def(&item.id).attack
                                + u32::from(item.rank)
                                    * rules.equipment.def(&item.id).attack_per_rank,
                            rules.equipment.def(&item.id).defense
                                + u32::from(item.rank)
                                    * rules.equipment.def(&item.id).defense_per_rank
                        ),
                        Some(Action::Unequip(slot)),
                    ),
                    None => (format!("{}：未装备", slot.label()), None),
                };
                p.spawn(label(text, 19.0, GOLD, font));
                if let Some(action) = action {
                    button(p, &format!("卸下{}", slot.label()), action, font);
                }
            }
            let bag = progress
                .loadout
                .bag
                .iter()
                .enumerate()
                .map(|(index, item)| {
                    let def = rules.equipment.def(&item.id);
                    (
                        format!(
                            "装备 {} · Lv{} 攻+{} 防+{}",
                            item.display(&rules.equipment),
                            def.required_level,
                            def.attack + u32::from(item.rank) * def.attack_per_rank,
                            def.defense + u32::from(item.rank) * def.defense_per_rank
                        ),
                        Action::Equip(index),
                    )
                })
                .collect::<Vec<_>>();
            grid(
                p,
                &format!(
                    "装备行囊 {}/{}",
                    progress.loadout.bag.len(),
                    rules.equipment.bag_slots
                ),
                bag,
                font,
            );
            button(p, "装备强化", Action::Enhancement, font);
            button(p, "武学修行", Action::Martial, font);
        }
        Panel::Npc => {
            p.spawn(label(
                if progress.stage == StoryStage::Completed {
                    progress.journey.stage.objective()
                } else {
                    progress.stage.objective()
                },
                19.0,
                GOLD,
                font,
            ));
            if progress.stage == StoryStage::Completed
                && matches!(
                    progress.journey.stage,
                    JourneyStage::ValleyReport | JourneyStage::NorthReport
                )
            {
                button(p, "回报区域历练", Action::ReportJourney, font);
            }
            button(p, "交易 · 买药与出售材料", Action::Trading, font);
            button(p, "强化 · 武器与防具", Action::Enhancement, font);
            button(p, "委托 · 工棚与区域狩猎", Action::Commissions, font);
            button(p, "门派 · 贡献、晋升与兑换", Action::Sect, font);
        }
        Panel::Trading => {
            p.spawn(label(
                format!("银两 {} · 商人：曹斌", progress.silver),
                20.0,
                GOLD,
                font,
            ));
            let mut supplies = vec![(
                format!(
                    "买入金疮药 · {}两（存{}）",
                    e.potion_price,
                    progress.inventory.count(Item::HealingPotion)
                ),
                Action::Trade(Trade::BuyPotion),
            )];
            for (item, price) in [
                Item::LinglongBamboo,
                Item::BeastHide,
                Item::WolfFang,
                Item::SpiritOre,
            ]
            .into_iter()
            .zip(e.sell_prices)
            {
                supplies.push((
                    format!(
                        "卖{} · {price}两（存{}）",
                        item.label(),
                        progress.inventory.count(item)
                    ),
                    Action::Trade(Trade::Sell(item)),
                ));
            }
            grid(p, "补给与材料", supplies, font);
            let shop = rules
                .equipment
                .shop()
                .map(|(index, def)| {
                    (
                        format!(
                            "{} · {}两 · Lv{} 攻+{} 防+{}",
                            def.label, def.buy_price, def.required_level, def.attack, def.defense
                        ),
                        Action::Trade(Trade::BuyEquipment(index)),
                    )
                })
                .collect::<Vec<_>>();
            grid(p, "购买装备", shop, font);
            let sellable = progress
                .loadout
                .bag
                .iter()
                .enumerate()
                .map(|(index, item)| {
                    (
                        format!(
                            "卖{} · {}两",
                            item.display(&rules.equipment),
                            rules.equipment.def(&item.id).sell_price
                        ),
                        Action::Trade(Trade::SellEquipment(index)),
                    )
                })
                .collect::<Vec<_>>();
            grid(p, "出售装备（行囊）", sellable, font);
        }
        Panel::Enhancement => {
            p.spawn(label(
                format!(
                    "银两 {}   竹材 {}   灵铁矿 {}",
                    progress.silver,
                    progress.inventory.count(Item::LinglongBamboo),
                    progress.inventory.count(Item::SpiritOre)
                ),
                20.0,
                GOLD,
                font,
            ));
            for (slot, prices, action) in [
                (EquipmentSlot::Weapon, e.sword_prices, Trade::UpgradeWeapon),
                (EquipmentSlot::Armor, e.armor_prices, Trade::UpgradeArmor),
            ] {
                let Some(item) = progress.equipped(slot) else {
                    p.spawn(label(
                        format!("{}：未装备，先到角色面板装备", slot.label()),
                        19.0,
                        PAPER,
                        font,
                    ));
                    continue;
                };
                let def = rules.equipment.def(&item.id);
                let text = if item.rank >= def.max_rank {
                    format!(
                        "{} · 已满级+{}",
                        item.display(&rules.equipment),
                        def.max_rank
                    )
                } else {
                    let i = usize::from(item.rank);
                    format!(
                        "{} → +{}（攻击+{} / 防御+{}）\n{}两 / 竹材{} / 灵铁矿{}",
                        item.display(&rules.equipment),
                        item.rank + 1,
                        def.attack_per_rank,
                        def.defense_per_rank,
                        prices[i],
                        e.upgrade_bamboo[i],
                        e.upgrade_ore[i]
                    )
                };
                button(p, &text, Action::Trade(action), font);
            }
        }
        Panel::Sect => {
            let s = &rules.sect;
            p.spawn(label(
                format!(
                    "身份：{}   可用贡献{} / 累计{}",
                    progress.sect.title(),
                    progress.sect.contribution,
                    progress.sect.earned
                ),
                20.0,
                GOLD,
                font,
            ));
            let rank = usize::from(progress.sect.rank);
            let promote = if rank == 3 {
                "晋升 · 已至上限".into()
            } else {
                format!(
                    "晋升 · 等级{} / 贡献{} / 对应章节回报",
                    s.promotion_levels[rank], s.promotion_costs[rank]
                )
            };
            p.spawn(Node {
                width: percent(100),
                display: Display::Grid,
                grid_template_columns: RepeatedGridTrack::flex(2, 1.0),
                column_gap: px(8),
                ..default()
            })
            .with_children(|p| {
                button(p, &promote, Action::SectAction(SectAction::Promote), font);
                button(
                    p,
                    &format!(
                        "捐献竹材{} → 贡献{}",
                        s.donation_bamboo, s.donation_contribution
                    ),
                    Action::SectAction(SectAction::Donate),
                    font,
                );
            });
            p.spawn(Node {
                display: Display::Grid,
                grid_template_columns: RepeatedGridTrack::flex(2, 1.0),
                column_gap: px(8),
                ..default()
            })
            .with_children(|p| {
                button(
                    p,
                    &format!("金疮药 · 贡献{}", s.potion_cost),
                    Action::SectAction(SectAction::Potion),
                    font,
                );
                button(
                    p,
                    &format!("灵铁矿 · 贡献{}", s.ore_cost),
                    Action::SectAction(SectAction::Ore),
                    font,
                );
            });
            let counts = progress.adventure.commission_progress();
            for (i, title) in ["野猪清剿", "山狼清剿", "竹林采伐"].iter().enumerate() {
                let used = u64::from(progress.sect.commissions_claimed[i])
                    * u64::from(s.commission_goals[i]);
                button(
                    p,
                    &format!(
                        "{title} · 新进度{}/{} → 贡献{}",
                        u64::from(counts[i]) - used,
                        s.commission_goals[i],
                        s.commission_contribution[i]
                    ),
                    Action::SectAction(SectAction::Commission(i)),
                    font,
                );
            }
        }
        _ => unreachable!("only service and character panels"),
    }
    if !near && *panel != Panel::Character {
        p.spawn(label(
            "请到曹斌身边办理交易、强化或宗门事务",
            17.0,
            GOLD,
            font,
        ));
    }
    p.spawn(Node {
        width: percent(100),
        justify_content: JustifyContent::Center,
        column_gap: px(8),
        ..default()
    })
    .with_children(|p| {
        if near && *panel != Panel::Npc {
            button(p, "返回曹斌", Action::Npc, font);
        }
        button(p, "关闭", Action::Resume, font);
    });
}

fn grid(
    p: &mut ChildSpawnerCommands,
    title: &str,
    entries: Vec<(String, Action)>,
    font: &Handle<Font>,
) {
    p.spawn(label(title, 18.0, JADE, font));
    if entries.is_empty() {
        p.spawn(label("（无）", 18.0, JADE, font));
        return;
    }
    p.spawn(Node {
        width: percent(100),
        display: Display::Grid,
        grid_template_columns: RepeatedGridTrack::flex(2, 1.0),
        row_gap: px(6),
        column_gap: px(8),
        ..default()
    })
    .with_children(|p| {
        for (text, action) in entries {
            button(p, &text, action, font);
        }
    });
}
