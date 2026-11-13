use super::*;
use crate::{
    app::LifecyclePlugin,
    data::load_configs,
    gameplay::{
        collision::CollisionMap, equipment::Equipment, exploration::ExplorationPlugin,
        runtime::GameplayPlugin,
    },
    save::{SavePlugin, TestSaveDirectory},
    world::WorldPlugin,
};
use bevy::{
    input::{
        ButtonState, InputPlugin,
        keyboard::{Key, KeyboardInput},
    },
    state::app::StatesPlugin,
    time::TimeUpdateStrategy,
};
use std::time::Duration;

fn game() -> (App, TestSaveDirectory) {
    let directory = TestSaveDirectory::new();
    let assets = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
    let (world, exploration) = load_configs(&assets).unwrap();
    let rules = GameRules::load(&assets, &world).unwrap();
    let quests = QuestRules::load(&assets).unwrap();
    let mut app = App::new();
    app.add_plugins((MinimalPlugins, InputPlugin, StatesPlugin))
        .insert_resource(Time::<Fixed>::from_hz(60.0))
        .insert_resource(TimeUpdateStrategy::ManualDuration(Duration::from_secs_f64(
            1.0 / 60.0,
        )))
        .init_resource::<Assets<Mesh>>()
        .init_resource::<Assets<StandardMaterial>>()
        .insert_resource(world)
        .insert_resource(exploration)
        .insert_resource(rules)
        .insert_resource(quests)
        .insert_resource(SaveStore::new(directory.0.clone()))
        .add_plugins((
            LifecyclePlugin,
            WorldPlugin,
            ExplorationPlugin,
            GameplayPlugin,
            UiPlugin,
            SavePlugin,
        ));
    app.update();
    app.world_mut()
        .resource_mut::<NextState<AppState>>()
        .set(AppState::MainMenu);
    app.update();
    app.update();
    (app, directory)
}

fn click(app: &mut App, action: Action) {
    let world = app.world_mut();
    let entity = world
        .query::<(Entity, &Action)>()
        .iter(world)
        .find(|(_, a)| **a == action)
        .map(|(e, _)| e)
        .expect("requested button must be present");
    *world.get_mut::<Interaction>(entity).unwrap() = Interaction::Pressed;
    app.update();
    if let Some(mut interaction) = app.world_mut().get_mut::<Interaction>(entity) {
        *interaction = Interaction::None;
    }
    app.update();
    app.update();
}

fn tap(app: &mut App, code: KeyCode) {
    for state in [ButtonState::Pressed, ButtonState::Released] {
        app.world_mut().write_message(KeyboardInput {
            key_code: code,
            logical_key: Key::Unidentified(bevy::input::keyboard::NativeKey::Unidentified),
            state,
            text: None,
            repeat: false,
            window: Entity::PLACEHOLDER,
        });
        app.update();
    }
    app.update();
}

#[test]
fn journal_toggles_and_manual_save_preserves_game_and_rejects_unsafe_position() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    tap(&mut app, KeyCode::KeyT);
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Journal)
    );
    tap(&mut app, KeyCode::KeyT);
    assert_eq!(app.world().resource::<UiState>().panel, None);

    app.world_mut()
        .resource_mut::<GameSession>()
        .progress
        .silver = 42;
    click(&mut app, Action::Pause);
    click(&mut app, Action::Save);
    assert_eq!(
        *app.world().resource::<State<AppState>>().get(),
        AppState::InGame
    );
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Info("进度已保存".into()))
    );
    let store = app.world().resource::<SaveStore>();
    let saved = store.snapshot.clone().unwrap();
    assert_eq!(saved.progress.silver, 42);
    assert_eq!(
        crate::save::Snapshot::decode(&std::fs::read(&store.path).unwrap()).unwrap(),
        saved
    );

    click(&mut app, Action::Resume);
    click(&mut app, Action::Pause);
    {
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.position = Vec2::new(30.0, -20.0);
        session.progress.silver = 99;
    }
    click(&mut app, Action::Save);
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Info("只有工棚安全区内可以保存".into()))
    );
    let store = app.world().resource::<SaveStore>();
    assert_eq!(store.snapshot.as_ref(), Some(&saved));
    assert_eq!(
        crate::save::Snapshot::decode(&std::fs::read(&store.path).unwrap()).unwrap(),
        saved
    );
}

#[test]
fn martial_buttons_train_save_and_pause_freezes_all_skill_timers() {
    use crate::gameplay::skills::Skill;
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    {
        let rules = app.world().resource::<GameRules>().clone();
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.progress.stage = StoryStage::Gathering;
        session.progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
        session.progress.gain_exp(500, &rules.player);
        session.progress.silver = 10;
        session.skill_cooldowns = [4.0, 8.0, 10.0];
        session.guard_remaining = 3.0;
    }
    tap(&mut app, KeyCode::KeyK);
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Martial)
    );
    click(&mut app, Action::Train(Skill::Piercing));
    assert_eq!(
        app.world().resource::<GameSession>().progress.martial.ranks,
        [1, 1, 0, 0]
    );
    assert_eq!(
        app.world()
            .resource::<SaveStore>()
            .snapshot
            .as_ref()
            .unwrap()
            .progress
            .martial
            .ranks,
        [1, 1, 0, 0]
    );
    let cooldowns = app.world().resource::<GameSession>().skill_cooldowns;
    let guard = app.world().resource::<GameSession>().guard_remaining;
    for _ in 0..120 {
        app.update();
    }
    assert_eq!(
        app.world().resource::<GameSession>().skill_cooldowns,
        cooldowns
    );
    assert_eq!(app.world().resource::<GameSession>().guard_remaining, guard);
    tap(&mut app, KeyCode::KeyK);
    assert_eq!(app.world().resource::<UiState>().panel, None);
}

#[test]
fn npc_services_and_commissions_apply_transactions_once() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    {
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.progress.stage = StoryStage::Gathering;
        session.progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
        session.progress.silver = 100;
        session
            .progress
            .inventory
            .add(Item::LinglongBamboo, 10)
            .unwrap();
        session.progress.adventure.boars_defeated = 3;
    }
    process_action(app.world_mut(), Action::Enhancement);
    app.update();
    let before = app.world().resource::<GameSession>().progress.clone();
    click(&mut app, Action::Trade(Trade::UpgradeWeapon));
    assert_eq!(app.world().resource::<GameSession>().progress, before);
    click(&mut app, Action::Resume);
    route(&mut app, &[(0.0, 16.0), (4.0, 16.0)]);
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::Npc);
    assert_eq!(app.world().resource::<UiState>().panel, Some(Panel::Npc));
    click(&mut app, Action::Enhancement);
    click(&mut app, Action::Trade(Trade::UpgradeWeapon));
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .loadout
            .weapon
            .as_ref()
            .map(|item| item.rank),
        Some(1)
    );
    click(&mut app, Action::Npc);
    click(&mut app, Action::Trading);
    let silver = app.world().resource::<GameSession>().progress.silver;
    let potions = app
        .world()
        .resource::<GameSession>()
        .progress
        .inventory
        .count(Item::HealingPotion);
    click(&mut app, Action::Trade(Trade::BuyPotion));
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .inventory
            .count(Item::HealingPotion),
        potions + 1
    );
    assert_eq!(
        app.world().resource::<GameSession>().progress.silver,
        silver - app.world().resource::<QuestRules>().economy.potion_price
    );
    click(&mut app, Action::Npc);
    click(&mut app, Action::Sect);
    click(
        &mut app,
        Action::SectAction(crate::gameplay::sect::SectAction::Donate),
    );
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .sect
            .contribution,
        2
    );
    click(&mut app, Action::Npc);
    click(&mut app, Action::Commissions);
    click(&mut app, Action::Trade(Trade::Commission(0)));
    let progress = app.world().resource::<GameSession>().progress.clone();
    assert!(progress.adventure.commissions_claimed[0]);
    click(&mut app, Action::Trade(Trade::Commission(0)));
    assert_eq!(app.world().resource::<GameSession>().progress, progress);
    assert!(matches!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Info(_))
    ));
}

#[test]
fn action_final_step_blocks_walking_and_reports_actual_fixed_step_speed() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    let before = position(&mut app);
    let duration = app.world().resource::<GameRules>().combo.duration;
    {
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.action = crate::gameplay::combat::PlayerAction::Melee {
            stage: 0,
            elapsed: duration - 1.0 / 120.0,
            hit: true,
            queued: false,
        };
    }
    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .press(KeyCode::KeyW);
    app.update();
    assert!(matches!(
        app.world().resource::<GameSession>().action,
        crate::gameplay::combat::PlayerAction::Idle
    ));
    assert_eq!(
        position(&mut app),
        before,
        "last attack step must not include normal walking"
    );
    assert_eq!(app.world().resource::<GameSession>().movement_speed, 0.0);
    app.update();
    assert!((position(&mut app).distance(before) - 4.0 / 60.0).abs() < 1e-4);
    assert!((app.world().resource::<GameSession>().movement_speed - 4.0).abs() < 1e-3);
}

fn position(app: &mut App) -> Vec2 {
    let world = app.world_mut();
    world
        .query_filtered::<&Transform, With<Player>>()
        .single(world)
        .unwrap()
        .translation
        .xz()
}

#[test]
fn mouse_destination_walks_around_buildings_stops_exactly_and_keyboard_or_pause_cancels() {
    use crate::gameplay::click_move::ClickMove;
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    let destination = Vec2::new(-12.0, -2.0); // beyond shed_01; straight line intersects its corner
    let start = position(&mut app);
    let request = |app: &mut App, from: Vec2, to: Vec2| {
        app.world_mut()
            .resource_scope(|world, mut movement: Mut<ClickMove>| {
                movement.request(from, to, world.resource::<CollisionMap>(), 0.35)
            })
    };
    assert!(request(&mut app, start, destination));
    for _ in 0..900 {
        app.update();
        let p = position(&mut app);
        assert!(
            !app.world()
                .resource::<CollisionMap>()
                .movement
                .iter()
                .any(|b| b.overlaps_circle(p, 0.349))
        );
        if app.world().resource::<ClickMove>().destination.is_none() {
            break;
        }
    }
    assert!(position(&mut app).distance(destination) < 0.002);
    assert!(request(&mut app, destination, Vec2::new(0.0, 24.0)));
    tap(&mut app, KeyCode::KeyD);
    assert!(app.world().resource::<ClickMove>().destination.is_none());
    let current = position(&mut app);
    assert!(
        !request(&mut app, current, Vec2::new(-12.0, 6.0)),
        "solid building must reject destination"
    );
    assert!(request(&mut app, current, Vec2::new(0.0, 24.0)));
    tap(&mut app, KeyCode::Escape);
    assert!(app.world().resource::<ClickMove>().destination.is_none());
    let paused = position(&mut app);
    for _ in 0..30 {
        app.update();
    }
    assert_eq!(position(&mut app), paused);
    tap(&mut app, KeyCode::Escape);
    for _ in 0..10 {
        app.update();
    }
    assert_eq!(
        position(&mut app),
        paused,
        "closing panel must not resume an old route"
    );
}

fn walk(app: &mut App, destination: Vec2) {
    for _ in 0..2000 {
        let delta = destination - position(app);
        if delta.length() < 0.12 {
            app.world_mut()
                .resource_mut::<ButtonInput<KeyCode>>()
                .reset_all();
            app.update();
            return;
        }
        let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
        keys.reset_all();
        if delta.x.abs() > 0.05 {
            keys.press(if delta.x > 0.0 {
                KeyCode::KeyD
            } else {
                KeyCode::KeyA
            });
        }
        if delta.y.abs() > 0.05 {
            keys.press(if delta.y > 0.0 {
                KeyCode::KeyS
            } else {
                KeyCode::KeyW
            });
        }
        app.update();
        assert!(
            app.world().resource::<GameSession>().progress.hp > 0,
            "died while walking"
        );
        let p = position(app);
        assert!(
            !app.world()
                .resource::<CollisionMap>()
                .movement
                .iter()
                .any(|b| b.overlaps_circle(p, 0.35))
        );
    }
    panic!(
        "route stuck at {:?}, destination {destination:?}",
        position(app)
    );
}

fn route(app: &mut App, points: &[(f32, f32)]) {
    for &(x, y) in points {
        walk(app, Vec2::new(x, y));
    }
}

#[test]
fn production_systems_complete_story_without_teleport_or_progress_cheats_and_restore_save() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::Report
    );
    route(&mut app, &[(0.0, 16.0), (4.0, 16.0)]);
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::ConfirmQuest);
    route(&mut app, &[(0.0, 16.0), (-8.0, 16.0)]);
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::ConfirmQuest);
    route(
        &mut app,
        &[
            (0.0, 16.0),
            (0.0, 8.0),
            (22.0, 8.0),
            (27.0, 8.0),
            (27.0, -8.0),
        ],
    );
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::Resume);
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::BindSword
    );
    tap(&mut app, KeyCode::KeyJ);
    assert!(matches!(
        app.world().resource::<GameSession>().action,
        crate::gameplay::combat::PlayerAction::Idle
    ));
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::ConfirmQuest);
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::Gathering
    );
    for points in [
        &[(27.0, -16.0), (30.0, -18.5)][..],
        &[(34.0, -18.5), (36.0, -22.5)][..],
        &[(40.0, -22.5), (40.0, -27.0), (30.0, -27.0), (30.0, -28.5)][..],
    ] {
        route(&mut app, points);
        tap(&mut app, KeyCode::KeyW); // Face the bamboo using movement input.
        for _ in 0..3 {
            tap(&mut app, KeyCode::KeyJ);
            for _ in 0..25 {
                app.update();
            }
        }
        tap(&mut app, KeyCode::KeyF);
    }
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .inventory
            .count(Item::LinglongBamboo),
        3
    );
    assert_eq!(app.world().resource::<GameSession>().progress.total_exp, 90);
    route(
        &mut app,
        &[
            (40.0, -28.5),
            (40.0, 8.0),
            (22.0, 8.0),
            (0.0, 8.0),
            (0.0, 16.0),
            (4.0, 16.0),
        ],
    );
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::ConfirmQuest);
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::Challenge
    );
    assert_eq!(app.world().resource::<GameSession>().progress.silver, 3);
    // Reach the opened gate from the west, avoiding the normal enemy patrol route.
    route(
        &mut app,
        &[
            (0.0, 16.0),
            (0.0, 8.0),
            (0.0, -16.0),
            (-4.0, -16.0),
            (-4.0, -20.0),
            (-42.0, -20.0),
            (-42.0, -36.0),
        ],
    );
    tap(&mut app, KeyCode::Tab);
    for _ in 0..40 {
        tap(&mut app, KeyCode::KeyJ);
        for _ in 0..25 {
            app.update();
        }
        let session = app.world().resource::<GameSession>();
        if session.progress.stage == StoryStage::ReturnToOutpost {
            break;
        }
        assert!(session.progress.hp > 0);
    }
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::ReturnToOutpost
    );
    route(
        &mut app,
        &[
            (-42.0, -20.0),
            (-4.0, -20.0),
            (-4.0, -16.0),
            (0.0, -16.0),
            (0.0, 8.0),
            (0.0, 16.0),
            (4.0, 16.0),
        ],
    );
    tap(&mut app, KeyCode::KeyE);
    click(&mut app, Action::ConfirmQuest);
    assert_eq!(
        app.world().resource::<GameSession>().progress.stage,
        StoryStage::Completed
    );
    assert_eq!(app.world().resource::<GameSession>().progress.silver, 8);
    click(&mut app, Action::Resume);
    tap(&mut app, KeyCode::KeyB);
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Inventory)
    );
    click(&mut app, Action::Resume);
    click(&mut app, Action::Pause);
    click(&mut app, Action::SaveMenu);
    assert_eq!(
        *app.world().resource::<State<AppState>>().get(),
        AppState::MainMenu
    );
    let saved = app
        .world()
        .resource::<SaveStore>()
        .snapshot
        .clone()
        .unwrap();
    click(&mut app, Action::Start);
    click(&mut app, Action::Resume); // Cancel overwrite.
    assert_eq!(
        app.world().resource::<SaveStore>().snapshot.as_ref(),
        Some(&saved)
    );
    click(&mut app, Action::Continue);
    assert_eq!(
        app.world().resource::<GameSession>().progress,
        saved.progress
    );
    assert!(
        !app.world()
            .resource::<GameSession>()
            .enemies
            .iter()
            .any(|e| e.boss())
    );
    assert!(position(&mut app).distance(saved.position.into()) < 0.001);
}

#[test]
fn pause_freezes_combat_and_discard_cancel_does_not_change_inventory() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    app.world_mut()
        .resource_mut::<GameSession>()
        .progress
        .inventory
        .add(Item::LinglongBamboo, 4)
        .unwrap();
    click(&mut app, Action::Pause);
    let before = app.world().resource::<GameSession>().progress.clone();
    let enemies = app
        .world()
        .resource::<GameSession>()
        .enemies
        .iter()
        .map(|e| e.position)
        .collect::<Vec<_>>();
    for _ in 0..180 {
        app.update();
    }
    assert_eq!(app.world().resource::<GameSession>().progress, before);
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .enemies
            .iter()
            .map(|e| e.position)
            .collect::<Vec<_>>(),
        enemies
    );
    click(&mut app, Action::Resume);
    tap(&mut app, KeyCode::KeyB);
    click(&mut app, Action::Discard(1));
    click(&mut app, Action::Inventory);
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .inventory
            .count(Item::LinglongBamboo),
        4
    );
    click(&mut app, Action::Discard(1));
    click(&mut app, Action::ConfirmDiscard);
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .inventory
            .count(Item::LinglongBamboo),
        0
    );
}

#[test]
fn chat_ime_keeps_composition_local_and_blocks_game_controls() {
    use crate::gameplay::messages::Channel;
    use bevy::window::Ime;
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    tap(&mut app, KeyCode::Enter);
    let before = position(&mut app);
    app.world_mut().write_message(KeyboardInput {
        key_code: KeyCode::KeyW,
        logical_key: Key::Character("w".into()),
        state: ButtonState::Pressed,
        text: Some("w".into()),
        repeat: false,
        window: Entity::PLACEHOLDER,
    });
    app.update();
    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .reset_all();
    app.world_mut().write_message(Ime::Preedit {
        window: Entity::PLACEHOLDER,
        value: "ni".into(),
        cursor: Some((2, 2)),
    });
    app.update();
    tap(&mut app, KeyCode::Backspace);
    assert_eq!(app.world().resource::<UiState>().chat_input, "w");
    let count = app.world().resource::<GameSession>().messages.len();
    app.world_mut().write_message(Ime::Commit {
        window: Entity::PLACEHOLDER,
        value: "你好".into(),
    });
    app.world_mut().write_message(KeyboardInput {
        key_code: KeyCode::Enter,
        logical_key: Key::Enter,
        state: ButtonState::Pressed,
        text: Some("\r".into()),
        repeat: false,
        window: Entity::PLACEHOLDER,
    });
    app.update();
    assert_eq!(app.world().resource::<GameSession>().messages.len(), count);
    assert_eq!(app.world().resource::<UiState>().chat_input, "w你好");
    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .reset_all();
    app.update();
    tap(&mut app, KeyCode::Enter);
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .messages
            .back()
            .unwrap()
            .text,
        "方尘：w你好"
    );
    assert_eq!(position(&mut app), before);
    assert!(matches!(
        app.world().resource::<GameSession>().action,
        crate::gameplay::combat::PlayerAction::Idle
    ));
    app.world_mut().resource_mut::<UiState>().chat_input = "/交谈".into();
    click(&mut app, Action::SendChat);
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .messages
            .back()
            .unwrap()
            .channel,
        Channel::System
    );
    assert!(
        app.world()
            .resource::<GameSession>()
            .messages
            .back()
            .unwrap()
            .text
            .contains("曹斌身边")
    );
    click(&mut app, Action::ChatFilter(Some(Channel::Local)));
    app.world_mut().resource_mut::<UiState>().chat_input = "未发送".into();
    click(&mut app, Action::Resume);
    click(&mut app, Action::Pause);
    click(&mut app, Action::MainMenu);
    assert!(app.world().resource::<UiState>().chat_input.is_empty());
    assert!(app.world().resource::<UiState>().chat_filter.is_none());
}

#[test]
fn map_markers_follow_and_cleanup_drops_and_waypoint_arrival_is_reported() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    let markers = app
        .world_mut()
        .query::<&map::Marker>()
        .iter(app.world())
        .count();
    let p = app.world().resource::<GameSession>().position;
    app.world_mut()
        .resource_mut::<GameSession>()
        .drops
        .push(crate::gameplay::combat::Drop {
            id: 42,
            position: p,
            item: Item::SpiritOre,
            count: 1,
        });
    for _ in 0..3 {
        app.update();
    }
    assert!(
        app.world_mut()
            .query::<&map::Marker>()
            .iter(app.world())
            .count()
            > markers
    );
    tap(&mut app, KeyCode::KeyF);
    for _ in 0..3 {
        app.update();
    }
    assert!(app.world().resource::<GameSession>().drops.is_empty());
    assert_eq!(
        app.world_mut()
            .query::<&map::Marker>()
            .iter(app.world())
            .count(),
        markers
    );
    tap(&mut app, KeyCode::KeyM);
    click(&mut app, Action::TrackRegion(1));
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .waypoint
            .as_ref()
            .unwrap()
            .0,
        "云溪谷"
    );
    tap(&mut app, KeyCode::KeyM);
    click(&mut app, Action::ClearWaypoint);
    assert!(app.world().resource::<GameSession>().waypoint.is_none());
    click(&mut app, Action::Resume);
    app.world_mut().resource_mut::<GameSession>().waypoint = Some(("测试入口".into(), p));
    app.update();
    assert!(app.world().resource::<GameSession>().waypoint.is_none());
    assert!(
        app.world()
            .resource::<GameSession>()
            .messages
            .back()
            .unwrap()
            .text
            .contains("已到达测试入口")
    );
}

#[test]
fn hotbar_casts_through_real_combat_and_attribute_panel_matches_damage_rules() {
    use crate::gameplay::skills::Skill;
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    {
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.progress.stage = StoryStage::Gathering;
        session.progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
    }
    click(&mut app, Action::Cast(Skill::Energy));
    assert!(app.world().resource::<GameSession>().energy_cooldown > 5.0);
    let stamina = app.world().resource::<GameSession>().progress.stamina;
    click(&mut app, Action::Cast(Skill::Energy));
    assert!(app.world().resource::<GameSession>().progress.stamina >= stamina);
    tap(&mut app, KeyCode::KeyC);
    let p = &app.world().resource::<GameSession>().progress;
    let rules = app.world().resource::<GameRules>();
    let (equipment_attack, equipment_defense) = p.equipment_bonus(rules);
    let expected = [
        format!(
            "攻击 {}（基础{} / 装备{} / 门派{}）",
            p.attack(rules),
            rules.player.attack(p.total_exp),
            equipment_attack,
            u32::from(p.sect.rank) * rules.sect.attack_per_rank
        ),
        format!(
            "防御 {}（装备{} / 门派{}）",
            p.defense(rules),
            equipment_defense,
            u32::from(p.sect.rank) * rules.sect.defense_per_rank
        ),
    ];
    let texts = app
        .world_mut()
        .query::<&Text>()
        .iter(app.world())
        .map(|t| t.0.clone())
        .collect::<Vec<_>>();
    assert!(expected.iter().all(|line| texts.contains(line)));
}

#[test]
fn character_panel_equips_swaps_and_unequips_gear_and_autosaves() {
    let (mut app, _directory) = game();
    click(&mut app, Action::Start);
    {
        let rules = app.world().resource::<GameRules>().clone();
        let mut session = app.world_mut().resource_mut::<GameSession>();
        session.progress.stage = StoryStage::Gathering;
        session.progress.gain_exp(500, &rules.player);
        session.progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
        session
            .progress
            .add_equipment(Equipment::new("refined_blade"), &rules.equipment)
            .unwrap();
    }
    tap(&mut app, KeyCode::KeyC);
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Character)
    );
    let before = app
        .world()
        .resource::<GameSession>()
        .progress
        .attack(app.world().resource::<GameRules>());
    click(&mut app, Action::Equip(0));
    {
        let progress = &app.world().resource::<GameSession>().progress;
        assert_eq!(
            progress.equipped(EquipmentSlot::Weapon).unwrap().id,
            "refined_blade"
        );
        assert_eq!(progress.loadout.bag[0].id, "fuxian_sword");
    }
    assert_eq!(
        app.world()
            .resource::<GameSession>()
            .progress
            .attack(app.world().resource::<GameRules>()),
        before + 9
    );
    assert_eq!(
        app.world().resource::<UiState>().panel,
        Some(Panel::Character)
    );
    assert_eq!(
        app.world()
            .resource::<SaveStore>()
            .snapshot
            .as_ref()
            .unwrap()
            .progress
            .loadout,
        app.world().resource::<GameSession>().progress.loadout
    );
    click(&mut app, Action::Unequip(EquipmentSlot::Weapon));
    {
        let progress = &app.world().resource::<GameSession>().progress;
        assert!(progress.equipped(EquipmentSlot::Weapon).is_none());
        assert_eq!(progress.loadout.bag.len(), 2);
        assert!(!progress.armed());
    }
}
