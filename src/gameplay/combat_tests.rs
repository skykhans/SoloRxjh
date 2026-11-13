use super::*;
use crate::{
    data::{WorldConfig, load_configs},
    gameplay::{
        config::GameRules,
        equipment::{Equipment, EquipmentSlot},
        progress::{INVENTORY_SLOTS, Inventory, QuestAction, STACK_LIMIT, Stack},
    },
};

/// Test setup that mirrors the quest grant of the starter weapon when jumping stages.
fn advance(progress: &mut Progress, stage: StoryStage) {
    progress.stage = stage;
    if stage.sword_owned() && progress.loadout.weapon.is_none() {
        progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
    }
}

fn fixture() -> (WorldConfig, GameRules, QuestRules, GameSession) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    let (world, _) = load_configs(&root).unwrap();
    let rules = GameRules::load(&root, &world).unwrap();
    let quests = QuestRules::load(&root).unwrap();
    let session = GameSession::new(&world, &rules, &quests);
    (world, rules, quests, session)
}

fn steps(session: &mut GameSession, rules: &GameRules, world: &WorldConfig, count: usize) {
    let mut map = collision_map(world, session.progress.stage, &session.bamboo);
    if session.map_dirty {
        map = session.rebuild_map(world, rules);
    }
    for _ in 0..count {
        session.tick(1.0 / 60.0, rules, world, &map, 0.35);
        if session.map_dirty {
            map = session.rebuild_map(world, rules);
        }
    }
}

fn attack(session: &mut GameSession, rules: &GameRules, world: &WorldConfig) {
    let map = collision_map(world, session.progress.stage, &session.bamboo);
    session.request(
        CombatInput {
            attack: true,
            ..default()
        },
        rules,
        &map,
    );
}

#[test]
fn shipped_gameplay_and_references_are_valid_and_bad_timelines_rejected() {
    let (world, _, _, _) = fixture();
    let source = include_str!("../../assets/config/gameplay.ron");
    for invalid in [
        source.replace("hit_at: 0.18", "hit_at: 0.5"),
        source.replace("cost: 30.0", "cost: 101.0"),
        source.replace("kind: \"boar\"", "kind: \"missing\""),
        source.replace("position: (5.0, -20.0)", "position: (0.0, 24.0)"),
        source.replace("immune_end: 0.40", "immune_end: 0.1"),
        source.replace("exp_thresholds: [100, 260,", "exp_thresholds: [260, 100,"),
        source.replace("stamina_regen:", "typo:"),
    ] {
        assert!(GameRules::parse(&invalid, &world).is_err());
    }
}

#[test]
fn combo_hits_once_per_segment_and_buffer_is_consumed_once() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    session.position = Vec2::new(5.0, -18.5);
    session.enemies.truncate(1);
    session.enemies[0].position = Vec2::new(5.0, -20.0);
    session.enemies[0].hp = 1000;
    attack(&mut session, &rules, &world);
    steps(&mut session, &rules, &world, 10);
    assert_eq!(session.enemies[0].hp, 1000);
    steps(&mut session, &rules, &world, 8);
    assert_eq!(session.enemies[0].hp, 982);
    attack(&mut session, &rules, &world);
    attack(&mut session, &rules, &world);
    steps(&mut session, &rules, &world, 24);
    assert_eq!(session.enemies[0].hp, 962); // floor(18 * 1.15)
    attack(&mut session, &rules, &world);
    steps(&mut session, &rules, &world, 35);
    assert_eq!(session.enemies[0].hp, 936); // floor(18 * 1.45)
    assert!(matches!(session.action, PlayerAction::Idle));
    steps(&mut session, &rules, &world, 50);
    attack(&mut session, &rules, &world);
    assert!(matches!(
        session.action,
        PlayerAction::Melee { stage: 0, .. }
    ));
}

#[test]
fn attack_sector_line_of_sight_and_recognition_gate_prevent_false_hits() {
    let (world, rules, _, mut session) = fixture();
    attack(&mut session, &rules, &world);
    assert!(matches!(session.action, PlayerAction::Idle));
    assert!(in_sector(Vec2::ZERO, 0.0, Vec2::new(0.0, -2.2), 2.2, 60.0));
    assert!(!in_sector(Vec2::ZERO, 0.0, Vec2::new(0.0, 1.0), 2.2, 60.0));
    assert!(!in_sector(
        Vec2::ZERO,
        0.0,
        Vec2::new(0.0, -2.201),
        2.2,
        60.0
    ));
    let map = collision_map(&world, StoryStage::Gathering, &session.bamboo);
    assert!(!sight(
        Vec2::new(-12.0, 11.0),
        Vec2::new(-12.0, 1.0),
        &map,
        false
    ));
}

#[test]
fn energy_cost_cooldown_and_dodge_immunity_boundaries() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    session.enemies.clear();
    let map = collision_map(&world, session.progress.stage, &session.bamboo);
    session.progress.stamina = 29.0;
    session.request(
        CombatInput {
            energy: true,
            ..default()
        },
        &rules,
        &map,
    );
    assert_eq!(session.progress.stamina, 29.0);
    assert_eq!(session.energy_cooldown, 0.0);
    session.progress.stamina = 30.0;
    session.request(
        CombatInput {
            energy: true,
            ..default()
        },
        &rules,
        &map,
    );
    assert_eq!(session.progress.stamina, 0.0);
    steps(&mut session, &rules, &world, 36);
    session.request(
        CombatInput {
            energy: true,
            ..default()
        },
        &rules,
        &map,
    );
    assert_eq!(session.progress.stamina, 0.0);
    for (elapsed, expected) in [(0.149, false), (0.15, true), (0.399, true), (0.40, false)] {
        assert_eq!(
            PlayerAction::Dodge {
                elapsed,
                direction: Vec2::X
            }
            .immune(&rules),
            expected
        );
    }
    session.action = PlayerAction::Idle;
    session.progress.stamina = 25.0;
    session.position = Vec2::new(-12.0, 11.0);
    session.request(
        CombatInput {
            dodge: true,
            direction: Vec2::NEG_Y,
            ..default()
        },
        &rules,
        &map,
    );
    steps(&mut session, &rules, &world, 36);
    assert!(session.position.y >= 9.85 - 0.001);
    assert!(
        !map.movement
            .iter()
            .any(|b| b.overlaps_circle(session.position, 0.35))
    );
}

#[test]
fn bamboo_requires_valid_melee_hits_produces_one_drop_and_respects_respawn_exclusion() {
    let (world, rules, _, mut session) = fixture();
    session.enemies.clear();
    advance(&mut session.progress, StoryStage::Gathering);
    session.position = Vec2::new(30.0, -18.5);
    for _ in 0..3 {
        attack(&mut session, &rules, &world);
        steps(&mut session, &rules, &world, 25);
    }
    assert_eq!(session.progress.total_exp, 30);
    assert_eq!(session.drops.len(), 1);
    assert_eq!(session.bamboo[0].hits, 3);
    attack(&mut session, &rules, &world);
    steps(&mut session, &rules, &world, 2000);
    assert_eq!(session.drops.len(), 1);
    assert!(session.bamboo[0].remaining > 0.0);
    session
        .pickup(&collision_map(
            &world,
            session.progress.stage,
            &session.bamboo,
        ))
        .unwrap();
    assert_eq!(session.progress.inventory.count(Item::LinglongBamboo), 1);
    assert!(
        session
            .pickup(&collision_map(
                &world,
                session.progress.stage,
                &session.bamboo
            ))
            .is_err()
    );
    session.position = Vec2::new(20.0, -18.5);
    steps(&mut session, &rules, &world, 2);
    assert_eq!(session.bamboo[0].remaining, 0.0);
    assert_eq!(session.bamboo[0].hits, 0);
}

#[test]
fn enemy_death_awards_once_safe_zone_blocks_damage_and_respawn_waits_for_player() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    session.enemies.truncate(1);
    session.position = Vec2::new(5.0, -18.5);
    session.enemies[0].hp = 1;
    attack(&mut session, &rules, &world);
    steps(&mut session, &rules, &world, 60);
    assert_eq!(session.progress.total_exp, 20);
    steps(&mut session, &rules, &world, 1900);
    assert_eq!(session.enemies[0].hp, 0);
    assert_eq!(session.progress.total_exp, 20);
    session.position = Vec2::new(0.0, 24.0);
    let hp = session.progress.hp;
    steps(&mut session, &rules, &world, 2);
    assert_eq!(session.enemies[0].hp, 55);
    session.enemies[0].position = session.position + Vec2::X;
    session.enemies[0].state = EnemyState::Windup {
        elapsed: 0.59,
        heavy: false,
    };
    steps(&mut session, &rules, &world, 2);
    assert_eq!(session.progress.hp, hp);
}

#[test]
fn death_cancels_action_return_preserves_progress_and_boss_completion() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::ReturnToOutpost);
    session.progress.total_exp = 120;
    session.progress.silver = 3;
    session.progress.hp = 1;
    session.position = Vec2::new(5.0, -18.5);
    session.enemies.truncate(1);
    session.enemies[0].state = EnemyState::Windup {
        elapsed: 0.59,
        heavy: false,
    };
    session.action = PlayerAction::Energy {
        elapsed: 0.0,
        hit: false,
    };
    steps(&mut session, &rules, &world, 2);
    assert_eq!(session.progress.hp, 0);
    assert!(matches!(session.action, PlayerAction::Dead));
    let exp = session.progress.total_exp;
    steps(&mut session, &rules, &world, 60);
    assert_eq!(session.progress.total_exp, exp);
    session.return_to_outpost(&world, &rules);
    assert_eq!(session.progress.hp, 150);
    assert_eq!(session.progress.silver, 3);
    assert_eq!(session.progress.stage, StoryStage::ReturnToOutpost);
    assert!(!session.enemies.iter().any(Enemy::boss));
}

#[test]
fn quest_transaction_handles_full_bag_without_partial_rewards_or_duplicate_delivery() {
    let (_, rules, quests, session) = fixture();
    let mut p = session.progress;
    assert!(
        p.apply_quest(QuestAction::TakeSword, &quests, &rules)
            .is_err()
    );
    for action in [
        QuestAction::Report,
        QuestAction::TakeSword,
        QuestAction::BindSword,
    ] {
        p.apply_quest(action, &quests, &rules).unwrap();
    }
    let before = p.clone();
    assert!(
        p.apply_quest(QuestAction::DeliverBamboo, &quests, &rules)
            .is_err()
    );
    assert_eq!(p, before);
    p.inventory = Inventory {
        stacks: vec![
            Stack {
                item: Item::LinglongBamboo,
                count: STACK_LIMIT
            };
            12
        ],
    };
    let before = p.clone();
    assert!(
        p.apply_quest(QuestAction::DeliverBamboo, &quests, &rules)
            .is_err()
    );
    assert_eq!(p, before);
    p.inventory.stacks.pop();
    p.apply_quest(QuestAction::DeliverBamboo, &quests, &rules)
        .unwrap();
    assert_eq!(p.silver, 3);
    assert_eq!(p.total_exp, 80);
    assert_eq!(p.inventory.count(Item::HealingPotion), 2);
    let before = p.clone();
    assert!(
        p.apply_quest(QuestAction::DeliverBamboo, &quests, &rules)
            .is_err()
    );
    assert_eq!(p, before);
}

#[test]
fn potions_and_experience_respect_limits_and_invalid_use_does_not_consume() {
    let (_, rules, _, mut session) = fixture();
    session.use_potion(&rules);
    assert_eq!(session.progress.inventory.count(Item::HealingPotion), 3);
    session.progress.hp = 30;
    session.use_potion(&rules);
    assert_eq!(session.progress.hp, 90);
    session.use_potion(&rules);
    assert_eq!(session.progress.inventory.count(Item::HealingPotion), 2);
    assert!(session.progress.gain_exp(300, &rules.player));
    assert_eq!(session.progress.total_exp, 300);
    assert_eq!(session.progress.hp, 180);
    assert_eq!(session.progress.stamina, 100.0);
    assert!(!session.progress.gain_exp(100, &rules.player));
    assert_eq!(session.progress.total_exp, 400);
    assert!(session.progress.gain_exp(u32::MAX, &rules.player));
    assert_eq!(session.progress.total_exp, 5000);
    assert_eq!(rules.player.level(session.progress.total_exp), 10);
    assert!(!session.progress.gain_exp(1, &rules.player));
}

#[test]
fn north_chapter_and_repeatable_hunts_preserve_transactions_and_saved_counts() {
    use crate::gameplay::journey::JourneyStage;
    let (_, rules, _, mut session) = fixture();
    let p = &mut session.progress;
    assert!(p.claim_hunt(0, &rules).is_err());
    advance(p, StoryStage::Completed);
    for _ in 0..5 {
        p.journey_kill("valley_boar", &rules.journey);
    }
    p.journey_kill("valley_guardian", &rules.journey);
    p.report_journey(&rules).unwrap();
    p.claim_hunt(0, &rules).unwrap();
    let before = p.clone();
    assert!(p.claim_hunt(0, &rules).is_err());
    assert!(p.claim_hunt(2, &rules).is_err());
    assert_eq!(*p, before);
    for _ in 0..5 {
        p.journey_kill("frost_wolf", &rules.journey);
    }
    assert_eq!(p.journey.stage, JourneyStage::NorthBoss);
    p.journey_kill("frost_guardian", &rules.journey);
    assert!(p.claim_hunt(1, &rules).is_err());
    p.report_journey(&rules).unwrap();
    p.claim_hunt(1, &rules).unwrap();
    p.validate_journey(&rules.journey).unwrap();
    assert_eq!(p.journey.repeat_claimed, [1, 1]);
    for _ in 0..5 {
        p.journey_kill("valley_boar", &rules.journey);
    }
    p.claim_hunt(0, &rules).unwrap();
    assert_eq!(p.journey.repeat_claimed, [2, 1]);
    let restored: Progress = serde_json::from_str(&serde_json::to_string(p).unwrap()).unwrap();
    assert_eq!(&restored, p);
    p.journey.repeat_claimed[0] = u32::MAX;
    assert!(p.validate_journey(&rules.journey).is_err());
}

#[test]
fn region_kills_unlock_one_boss_and_reports_cannot_duplicate_rewards() {
    use crate::gameplay::journey::JourneyStage;
    let (world, rules, _, mut session) = fixture();
    assert!(session.enemies.iter().all(|e| !e.boss()));
    advance(&mut session.progress, StoryStage::Completed);
    session.position = Vec2::new(120.0, 0.0);
    let map = collision_map(&world, session.progress.stage, &session.bamboo);
    for _ in 0..rules.journey.hunt_goals[0] {
        let enemy = session
            .enemies
            .iter_mut()
            .find(|e| e.kind == "valley_boar")
            .unwrap();
        enemy.position = session.position - Vec2::Y;
        enemy.hp = 1;
        enemy.state = EnemyState::Recover(100.0);
        session.player_hit(None, 0, &rules, &map);
    }
    assert_eq!(session.progress.journey.stage, JourneyStage::ValleyBoss);
    assert_eq!(
        session
            .enemies
            .iter()
            .filter(|e| e.kind == "valley_guardian")
            .count(),
        1
    );
    session.quest_changed(&rules);
    assert_eq!(
        session
            .enemies
            .iter()
            .filter(|e| e.kind == "valley_guardian")
            .count(),
        1
    );
    let boss = session
        .enemies
        .iter_mut()
        .find(|e| e.kind == "valley_guardian")
        .unwrap();
    boss.position = session.position - Vec2::Y;
    boss.hp = 1;
    session.player_hit(None, 0, &rules, &map);
    assert_eq!(session.progress.journey.stage, JourneyStage::ValleyReport);
    let kills = session.progress.journey.kills;
    session.player_hit(None, 0, &rules, &map);
    assert_eq!(session.progress.journey.kills, kills);
    let before = session.progress.clone();
    session.progress.inventory.stacks = vec![
        Stack {
            item: Item::LinglongBamboo,
            count: 99
        };
        INVENTORY_SLOTS
    ];
    let full = session.progress.clone();
    assert!(session.progress.report_journey(&rules).is_err());
    assert_eq!(session.progress, full);
    session.progress = before;
    session.progress.report_journey(&rules).unwrap();
    let rewarded = session.progress.clone();
    assert!(session.progress.report_journey(&rules).is_err());
    assert_eq!(session.progress, rewarded);
    assert_eq!(session.progress.journey.stage, JourneyStage::NorthHunt);
    session.return_to_outpost(&world, &rules);
    assert!(!session.enemies.iter().any(|e| e.kind == "valley_guardian"));
}

#[test]
fn skill_training_checks_unlock_points_money_and_commits_once() {
    let (_, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .learn_skill(Skill::Piercing, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session.progress.gain_exp(500, &rules.player);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .learn_skill(Skill::Piercing, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session.progress.silver = 30;
    for skill in [Skill::Piercing, Skill::Guard, Skill::Mend] {
        session.progress.learn_skill(skill, &rules).unwrap();
    }
    assert_eq!(session.progress.martial.ranks, [1, 1, 1, 1]);
    assert_eq!(session.progress.silver, 24);
    let before = session.progress.clone();
    assert!(session.progress.learn_skill(Skill::Energy, &rules).is_err());
    assert_eq!(session.progress, before);
    session.progress.gain_exp(800, &rules.player);
    session.progress.learn_skill(Skill::Energy, &rules).unwrap();
    session.progress.learn_skill(Skill::Energy, &rules).unwrap();
    let before = session.progress.clone();
    assert!(session.progress.learn_skill(Skill::Energy, &rules).is_err());
    assert_eq!(session.progress, before);
}

#[test]
fn piercing_respects_direction_range_walls_single_hit_and_cooldown() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    session.progress.gain_exp(500, &rules.player);
    session.progress.silver = 5;
    session
        .progress
        .learn_skill(Skill::Piercing, &rules)
        .unwrap();
    session.position = Vec2::new(0.0, 45.0);
    session.enemies.truncate(3);
    for (enemy, point) in session
        .enemies
        .iter_mut()
        .zip([[0.0, 40.0], [3.0, 41.0], [0.0, 38.0]])
    {
        enemy.position = point.into();
        enemy.home = enemy.position;
        enemy.hp = 200;
        enemy.state = EnemyState::Recover(100.0);
    }
    let mut map = collision_map(&world, session.progress.stage, &session.bamboo);
    map.camera
        .push(super::super::collision::Aabb::from_center_size(
            Vec3::new(0.0, 1.0, 42.0),
            Vec3::new(2.0, 2.0, 0.5),
        ));
    session.request(
        CombatInput {
            skill: Some(Skill::Piercing),
            ..default()
        },
        &rules,
        &map,
    );
    for _ in 0..40 {
        session.tick(1.0 / 60.0, &rules, &world, &map, 0.35);
    }
    assert!(session.enemies.iter().all(|e| e.hp == 200));
    session.skill_cooldowns[0] = 0.0;
    session.progress.stamina = 100.0;
    let map = collision_map(&world, session.progress.stage, &session.bamboo);
    session.request(
        CombatInput {
            skill: Some(Skill::Piercing),
            ..default()
        },
        &rules,
        &map,
    );
    for _ in 0..40 {
        session.tick(1.0 / 60.0, &rules, &world, &map, 0.35);
    }
    assert_eq!(session.enemies[0].hp, 122);
    assert_eq!(session.enemies[1].hp, 200);
    assert_eq!(session.enemies[2].hp, 200);
    let stamina = session.progress.stamina;
    session.request(
        CombatInput {
            skill: Some(Skill::Piercing),
            ..default()
        },
        &rules,
        &map,
    );
    assert_eq!(session.progress.stamina, stamina);
    assert!(matches!(session.action, PlayerAction::Idle));
}

#[test]
fn guard_reduces_actual_enemy_damage_and_mend_rejects_full_health() {
    let (world, rules, _, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Gathering);
    session.progress.gain_exp(500, &rules.player);
    session.progress.silver = 5;
    session.progress.learn_skill(Skill::Guard, &rules).unwrap();
    session.progress.learn_skill(Skill::Mend, &rules).unwrap();
    session.position = Vec2::new(0.0, 45.0);
    session.enemies.truncate(1);
    session.enemies[0].state = EnemyState::Recover(100.0);
    let map = collision_map(&world, session.progress.stage, &session.bamboo);
    session.request(
        CombatInput {
            skill: Some(Skill::Guard),
            ..default()
        },
        &rules,
        &map,
    );
    steps(&mut session, &rules, &world, 32);
    assert!(session.guard_remaining > 5.5);
    let enemy = &mut session.enemies[0];
    enemy.position = Vec2::new(0.0, 43.5);
    enemy.home = enemy.position;
    enemy.state = EnemyState::Windup {
        elapsed: rules.ai.windup,
        heavy: false,
    };
    let hp = session.progress.hp;
    steps(&mut session, &rules, &world, 1);
    assert_eq!(session.progress.hp, hp - 4);
    session.progress.hp = hp;
    let stamina = session.progress.stamina;
    session.request(
        CombatInput {
            skill: Some(Skill::Mend),
            ..default()
        },
        &rules,
        &map,
    );
    assert_eq!(session.progress.stamina, stamina);
    assert_eq!(session.skill_cooldowns[2], 0.0);
    session.progress.hp = 30;
    session.request(
        CombatInput {
            skill: Some(Skill::Mend),
            ..default()
        },
        &rules,
        &map,
    );
    steps(&mut session, &rules, &world, 45);
    assert_eq!(session.progress.hp, 70);
    assert!(session.skill_cooldowns[2] > 11.0);
    session.progress.hp = 0;
    session.return_to_outpost(&world, &rules);
    assert_eq!(session.skill_cooldowns, [0.0; 3]);
    assert_eq!(session.guard_remaining, 0.0);
}

#[test]
fn astar_routes_around_obstacles_and_never_crosses_safe_zone() {
    let (world, rules, _, session) = fixture();
    let map = collision_map(&world, StoryStage::Report, &session.bamboo);
    let nav = NavGrid::new(&map, Some(&world.safe_zone), rules.ai.radius);
    let start = Vec2::new(-25.0, 12.0);
    let goal = Vec2::new(25.0, 12.0);
    let path = nav.path(start, goal, &map);
    assert!(!path.is_empty());
    let mut from = start;
    for to in path {
        assert!(!crosses_safe_zone(
            from,
            to,
            &world.safe_zone,
            rules.ai.radius
        ));
        assert!(move_circle(from, to - from, rules.ai.radius, &map).distance(to) < 0.001);
        from = to;
    }
    assert!(from.distance(goal) < 0.01);
}

#[test]
fn each_monster_drops_its_table_once_and_reports_actual_damage() {
    for rule in fixture().1.enemies {
        let (world, rules, _, mut session) = fixture();
        advance(&mut session.progress, StoryStage::Gathering);
        session.position = Vec2::new(0.0, 45.0);
        session.enemies.truncate(1);
        let enemy = &mut session.enemies[0];
        enemy.kind = rule.id.clone();
        enemy.position = session.position - Vec2::Y;
        enemy.hp = 1;
        let map = collision_map(&world, session.progress.stage, &session.bamboo);
        session.player_hit(None, 0, &rules, &map);
        assert_eq!(
            session
                .drops
                .iter()
                .map(|d| Stack {
                    item: d.item,
                    count: d.count
                })
                .collect::<Vec<_>>(),
            rule.loot
        );
        assert!(
            session
                .effects
                .iter()
                .any(|e| matches!(e.kind, EffectKind::Damage) && e.amount == 1)
        );
        let exp = session.progress.total_exp;
        let drops = session.drops.len();
        session.player_hit(None, 0, &rules, &map);
        assert_eq!(session.drops.len(), drops);
        assert_eq!(session.progress.total_exp, exp);
    }
}

#[test]
fn pickup_rejects_full_bag_walls_distance_and_death_without_losing_loot() {
    use crate::gameplay::collision::Aabb;
    let (world, _, _, mut session) = fixture();
    session.position = Vec2::new(0.0, 45.0);
    let mut map = collision_map(&world, session.progress.stage, &session.bamboo);
    session.drops.push(Drop {
        id: 1,
        position: session.position - Vec2::Y,
        item: Item::SpiritOre,
        count: 3,
    });
    session.progress.inventory.stacks = vec![
        Stack {
            item: Item::SpiritOre,
            count: 99
        };
        INVENTORY_SLOTS
    ];
    session.progress.inventory.stacks[0].count = 98; // one free unit cannot accept a whole drop
    let before = session.progress.clone();
    assert!(session.pickup(&map).is_err());
    assert_eq!(session.progress, before);
    assert_eq!(session.drops.len(), 1);
    session.progress.inventory = Inventory::default();
    map.camera.push(Aabb::from_center_size(
        Vec3::new(0.0, 1.0, 44.5),
        Vec3::new(1.0, 2.0, 0.1),
    ));
    assert!(session.pickup(&map).is_err());
    map.camera.pop();
    session.position.y += 2.0;
    assert!(session.pickup(&map).is_err());
    session.position.y -= 2.0;
    session.progress.hp = 0;
    assert!(session.pickup(&map).is_err());
    session.progress.hp = 1;
    session.pickup(&map).unwrap();
    assert_eq!(session.progress.inventory.count(Item::SpiritOre), 3);
    assert!(session.drops.is_empty());
    assert!(session.auto_save && session.dirty);
    assert!(session.pickup(&map).is_err());
    assert_eq!(session.progress.inventory.count(Item::SpiritOre), 3);
}

#[test]
fn sect_transactions_protect_story_materials_deduplicate_and_apply_rank_bonuses() {
    use crate::gameplay::sect::SectAction;
    let (_, rules, quests, mut session) = fixture();
    let p = &mut session.progress;
    advance(p, StoryStage::Gathering);
    p.inventory.add(Item::LinglongBamboo, 5).unwrap();
    let before = p.clone();
    assert!(p.sect_action(SectAction::Donate, &quests, &rules).is_err());
    assert_eq!(*p, before);
    p.inventory.add(Item::LinglongBamboo, 1).unwrap();
    p.sect_action(SectAction::Donate, &quests, &rules).unwrap();
    assert_eq!(p.inventory.count(Item::LinglongBamboo), 3);
    p.adventure.boars_defeated = rules.sect.commission_goals[0];
    p.sect_action(SectAction::Commission(0), &quests, &rules)
        .unwrap();
    let before = p.clone();
    assert!(
        p.sect_action(SectAction::Commission(0), &quests, &rules)
            .is_err()
    );
    assert_eq!(*p, before);
    assert!(p.sect_action(SectAction::Promote, &quests, &rules).is_err());
    advance(p, StoryStage::Completed);
    p.gain_exp(5000, &rules.player);
    p.inventory.add(Item::LinglongBamboo, 99).unwrap();
    while p.sect.contribution < rules.sect.promotion_costs[0] {
        p.sect_action(SectAction::Donate, &quests, &rules).unwrap();
    }
    let attack = p.attack(&rules);
    p.sect_action(SectAction::Promote, &quests, &rules).unwrap();
    assert_eq!(p.sect.rank, 1);
    assert_eq!(p.attack(&rules), attack + rules.sect.attack_per_rank);
    assert_eq!(p.defense(&rules), rules.sect.defense_per_rank);
    p.validate_sect(&rules.sect, &rules.player).unwrap();
    while p.sect.contribution < rules.sect.ore_cost {
        p.sect_action(SectAction::Donate, &quests, &rules).unwrap();
    }
    let available = p.sect.contribution;
    p.inventory.stacks = vec![
        Stack {
            item: Item::LinglongBamboo,
            count: 99
        };
        INVENTORY_SLOTS
    ];
    let before = p.clone();
    assert!(p.sect_action(SectAction::Ore, &quests, &rules).is_err());
    assert_eq!(*p, before);
    p.inventory.stacks.clear();
    p.sect_action(SectAction::Ore, &quests, &rules).unwrap();
    assert_eq!(p.sect.contribution, available - rules.sect.ore_cost);
    assert_eq!(p.inventory.count(Item::SpiritOre), 1);
    let before = p.clone();
    assert!(p.sect_action(SectAction::Promote, &quests, &rules).is_err()); // valley report required
    assert_eq!(*p, before);
}

#[test]
fn enhancement_requires_ore_and_commits_all_costs_together() {
    use crate::gameplay::progress::Trade;
    let (_, rules, quests, mut session) = fixture();
    let p = &mut session.progress;
    p.silver = 100;
    advance(p, StoryStage::Gathering);
    p.inventory.add(Item::LinglongBamboo, 3).unwrap();
    let before = p.clone();
    assert!(p.trade(Trade::UpgradeWeapon, &quests, &rules).is_err());
    assert_eq!(*p, before);
    p.inventory.remove(Item::LinglongBamboo, 3).unwrap();
    advance(p, StoryStage::Completed);
    p.inventory.add(Item::LinglongBamboo, 20).unwrap();
    p.trade(Trade::UpgradeWeapon, &quests, &rules).unwrap();
    let before = p.clone();
    assert!(p.trade(Trade::UpgradeWeapon, &quests, &rules).is_err());
    assert_eq!(*p, before);
    p.inventory.add(Item::SpiritOre, 3).unwrap();
    p.trade(Trade::UpgradeWeapon, &quests, &rules).unwrap();
    p.trade(Trade::UpgradeWeapon, &quests, &rules).unwrap();
    assert_eq!(
        p.equipped(EquipmentSlot::Weapon).map(|item| item.rank),
        Some(3)
    );
    assert_eq!(p.inventory.count(Item::SpiritOre), 0);
    assert_eq!(p.silver, 72);
    let before = p.clone();
    assert!(p.trade(Trade::UpgradeWeapon, &quests, &rules).is_err());
    assert_eq!(*p, before);
}

#[test]
fn full_sect_promotion_chain_respects_chapters_and_changes_real_combat() {
    use crate::gameplay::{journey::JourneyStage, sect::SectAction};
    let (world, rules, quests, mut session) = fixture();
    advance(&mut session.progress, StoryStage::Completed);
    session
        .progress
        .inventory
        .add(Item::LinglongBamboo, 135)
        .unwrap();
    for _ in 0..45 {
        session
            .progress
            .sect_action(SectAction::Donate, &quests, &rules)
            .unwrap();
    }
    assert_eq!(session.progress.sect.earned, 90);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .sect_action(SectAction::Promote, &quests, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session.progress.gain_exp(500, &rules.player);
    session
        .progress
        .sect_action(SectAction::Promote, &quests, &rules)
        .unwrap();
    assert_eq!(session.progress.sect.rank, 1);
    for _ in 0..5 {
        session.progress.journey_kill("valley_boar", &rules.journey);
    }
    session
        .progress
        .journey_kill("valley_guardian", &rules.journey);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .sect_action(SectAction::Promote, &quests, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session.progress.report_journey(&rules).unwrap();
    assert_eq!(session.progress.journey.stage, JourneyStage::NorthHunt);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .sect_action(SectAction::Promote, &quests, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before); // Lv4 still below the second promotion
    session.progress.gain_exp(100, &rules.player);
    session
        .progress
        .sect_action(SectAction::Promote, &quests, &rules)
        .unwrap();
    assert_eq!(session.progress.sect.rank, 2);
    for _ in 0..5 {
        session.progress.journey_kill("frost_wolf", &rules.journey);
    }
    session
        .progress
        .journey_kill("frost_guardian", &rules.journey);
    session.progress.gain_exp(1850, &rules.player);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .sect_action(SectAction::Promote, &quests, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session.progress.report_journey(&rules).unwrap();
    session
        .progress
        .sect_action(SectAction::Promote, &quests, &rules)
        .unwrap();
    assert_eq!(session.progress.sect.rank, 3);
    assert_eq!(session.progress.sect.contribution, 5);
    let before = session.progress.clone();
    assert!(
        session
            .progress
            .sect_action(SectAction::Promote, &quests, &rules)
            .is_err()
    );
    assert_eq!(session.progress, before);
    session
        .progress
        .validate_sect(&rules.sect, &rules.player)
        .unwrap();
    session.progress.loadout.weapon = Some(Equipment::with_rank("fuxian_sword", 2));
    session.progress.loadout.armor = Some(Equipment::with_rank("menial_robe", 2));
    session.position = Vec2::new(0.0, 45.0);
    session.enemies.truncate(1);
    session.enemies[0].position = session.position - Vec2::Y;
    session.enemies[0].home = session.enemies[0].position;
    session.enemies[0].hp = 200;
    session.enemies[0].state = EnemyState::Windup {
        elapsed: rules.ai.windup,
        heavy: false,
    };
    let expected = rules.player.attack(session.progress.total_exp) + 8 + 6;
    let map = collision_map(&world, session.progress.stage, &session.bamboo);
    session.player_hit(None, 0, &rules, &map);
    assert_eq!(session.enemies[0].hp, 200 - expected);
    let hp = session.progress.hp;
    steps(&mut session, &rules, &world, 1);
    assert_eq!(session.progress.hp, hp - 1); // 8 - armor(4) - sect(3)
    let snapshot = crate::save::Snapshot::capture(
        &session,
        &crate::save::GameSettings {
            volume: 0.7,
            camera_distance: 7.0,
        },
    );
    let restored = crate::save::Snapshot::decode(&serde_json::to_vec(&snapshot).unwrap()).unwrap();
    let assets = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    let (_, exploration) = load_configs(&assets).unwrap();
    restored.validate(&rules, &world, &exploration).unwrap();
    assert_eq!(restored, snapshot);
}

#[test]
fn every_material_sale_and_purchase_preserve_resources_on_failure() {
    use crate::gameplay::progress::Trade;
    let (_, rules, quests, mut session) = fixture();
    let p = &mut session.progress;
    advance(p, StoryStage::Gathering);
    p.inventory.add(Item::LinglongBamboo, 3).unwrap();
    let before = p.clone();
    assert!(
        p.trade(Trade::Sell(Item::LinglongBamboo), &quests, &rules)
            .is_err()
    );
    assert_eq!(*p, before);
    advance(p, StoryStage::Completed);
    for (item, price) in [
        Item::LinglongBamboo,
        Item::BeastHide,
        Item::WolfFang,
        Item::SpiritOre,
    ]
    .into_iter()
    .zip(quests.economy.sell_prices)
    {
        p.inventory.add(item, 1).unwrap();
        let silver = p.silver;
        let count = p.inventory.count(item);
        p.trade(Trade::Sell(item), &quests, &rules).unwrap();
        assert_eq!(p.silver, silver + price);
        assert_eq!(p.inventory.count(item), count - 1);
    }
    p.inventory.stacks = vec![
        Stack {
            item: Item::SpiritOre,
            count: 99
        };
        INVENTORY_SLOTS
    ];
    let before = p.clone();
    assert!(p.trade(Trade::BuyPotion, &quests, &rules).is_err());
    assert_eq!(*p, before);
    p.inventory = Inventory::default();
    p.inventory.add(Item::SpiritOre, 1).unwrap();
    p.silver = u32::MAX;
    let before = p.clone();
    assert!(
        p.trade(Trade::Sell(Item::SpiritOre), &quests, &rules)
            .is_err()
    );
    assert_eq!(*p, before);
    p.silver = quests.economy.potion_price;
    p.trade(Trade::BuyPotion, &quests, &rules).unwrap();
    assert_eq!(p.silver, 0);
    assert_eq!(p.inventory.count(Item::HealingPotion), 1);
    let before = p.clone();
    assert!(p.trade(Trade::BuyPotion, &quests, &rules).is_err());
    assert!(
        p.trade(Trade::Sell(Item::HealingPotion), &quests, &rules)
            .is_err()
    );
    assert_eq!(*p, before);
}
