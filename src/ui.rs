use bevy::{input::InputSystems, prelude::*};

mod chat;
mod hotbar;
mod map;
mod panels;

use crate::{
    app::{AppState, SessionState},
    data::{ExplorationConfig, LoadError, WorldConfig},
    gameplay::{
        combat::GameSession,
        config::GameRules,
        equipment::EquipmentSlot,
        exploration::{CameraRig, NearbyInteraction, Player},
        journey::JourneyStage,
        progress::{Item, QuestAction, QuestRules, Stack, StoryStage, Trade},
    },
    save::{GameSettings, ResumeGame, SaveStore, save_current},
};

const INK: Color = Color::srgb(0.073, 0.118, 0.118);
const PAPER: Color = Color::srgb(0.94, 0.91, 0.83);
const JADE: Color = Color::srgb(0.28, 0.51, 0.45);
const GOLD: Color = Color::srgb(0.77, 0.64, 0.40);

pub struct UiPlugin;

#[derive(Resource, Default)]
pub(crate) struct UiFont(pub(crate) Handle<Font>);

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) struct MenuBuildSet;

#[derive(SystemSet, Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) struct UiInputSet;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<UiFont>()
            .init_resource::<UiState>()
            .add_message::<bevy::window::WindowCloseRequested>()
            .add_message::<bevy::window::Ime>()
            .add_systems(Startup, (setup_ui_camera, load_font))
            .add_systems(OnEnter(AppState::Loading), loading_screen)
            .add_systems(OnEnter(AppState::MainMenu), main_menu.in_set(MenuBuildSet))
            .add_systems(
                OnEnter(AppState::InGame),
                (remove_menu_camera, world_overlay),
            )
            .add_systems(OnEnter(AppState::LoadError), error_screen)
            .add_systems(OnEnter(SessionState::Paused), ensure_pause)
            .add_systems(OnExit(SessionState::Paused), clear_panel)
            .add_systems(OnExit(AppState::Loading), clear_screen)
            .add_systems(OnExit(AppState::MainMenu), (clear_screen, clear_panel))
            .add_systems(
                OnExit(AppState::InGame),
                (clear_screen, clear_panel, reset_chat, setup_ui_camera),
            )
            .add_systems(OnExit(AppState::LoadError), clear_screen)
            .add_systems(
                PreUpdate,
                (chat::input, keyboard_actions)
                    .chain()
                    .after(InputSystems)
                    .in_set(UiInputSet)
                    .run_if(in_state(AppState::InGame)),
            )
            .add_systems(
                Update,
                (
                    button_actions,
                    close_requests,
                    detect_death,
                    refresh_hud,
                    rebuild_panel,
                )
                    .chain(),
            )
            .add_systems(
                Update,
                (map::refresh, hotbar::refresh, chat::refresh)
                    .after(rebuild_panel)
                    .run_if(in_state(AppState::InGame)),
            );
    }
}

#[derive(Component)]
struct ScreenRoot;
#[derive(Component)]
struct MenuCamera;
#[derive(Component)]
struct PanelRoot;
#[derive(Component)]
struct Hud;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Action {
    Start,
    Continue,
    ConfirmNew,
    MainMenu,
    Pause,
    Resume,
    Exit,
    ConfirmExit,
    ConfirmMenu,
    Save,
    SaveMenu,
    ConfirmQuest,
    Trading,
    Npc,
    Character,
    Enhancement,
    Sect,
    SectAction(crate::gameplay::sect::SectAction),
    WorldMap,
    TrackRegion(usize),
    ClearWaypoint,
    Chat,
    ChatFilter(Option<crate::gameplay::messages::Channel>),
    SendChat,
    Cast(crate::gameplay::skills::Skill),
    Commissions,
    Journal,
    Martial,
    Train(crate::gameplay::skills::Skill),
    ReportJourney,
    Hunt(usize),
    Trade(Trade),
    Inventory,
    Potion,
    Equip(usize),
    Unequip(EquipmentSlot),
    Discard(usize),
    ConfirmDiscard,
    Outpost,
    Help,
    VolumeDown,
    VolumeUp,
    CameraNear,
    CameraFar,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Panel {
    Pause,
    Trading,
    Npc,
    Character,
    Enhancement,
    Sect,
    WorldMap,
    Chat,
    Commissions,
    Journal,
    Martial,
    Dialogue {
        action: QuestAction,
        title: String,
        body: String,
    },
    Info(String),
    Inventory,
    Discard {
        index: usize,
        expected: Stack,
    },
    Death,
    Chapter,
    ConfirmNew,
    ConfirmExit,
    ConfirmMenu,
    Help,
}

#[derive(Resource, Default)]
struct UiState {
    panel: Option<Panel>,
    rebuild: bool,
    chat_input: String,
    chat_filter: Option<crate::gameplay::messages::Channel>,
    chat_preedit: String,
    chat_ime_input: bool,
}

fn load_font(mut font: ResMut<UiFont>, assets: Option<Res<AssetServer>>) {
    // Headless tests omit AssetServer; native builds require the bundled font.
    if let Some(assets) = assets {
        font.0 = assets.load("fonts/NotoSansCJKsc-Regular.otf");
    }
}

fn setup_ui_camera(mut commands: Commands) {
    commands.spawn((
        MenuCamera,
        Camera2d,
        IsDefaultUiCamera,
        Name::new("Menu camera"),
    ));
}

fn remove_menu_camera(mut commands: Commands, cameras: Query<Entity, With<MenuCamera>>) {
    for entity in &cameras {
        commands.entity(entity).despawn();
    }
}

fn label(text: impl Into<String>, size: f32, color: Color, font: &Handle<Font>) -> impl Bundle {
    (
        Text::new(text),
        TextFont {
            font: font.clone(),
            font_size: size,
            ..default()
        },
        TextColor(color),
    )
}

fn button(parent: &mut ChildSpawnerCommands, text: &str, action: Action, font: &Handle<Font>) {
    parent
        .spawn((
            Button,
            action,
            Node {
                width: percent(100),
                max_width: px(420),
                min_height: px(46),
                padding: UiRect::axes(px(16), px(8)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(px(1)),
                ..default()
            },
            BorderColor::all(Color::srgb(0.37, 0.43, 0.36)),
            BackgroundColor(Color::srgb(0.10, 0.16, 0.15)),
        ))
        .with_children(|p| {
            p.spawn(label(text, 18.0, PAPER, font));
        });
}

fn screen_node() -> Node {
    Node {
        width: percent(100),
        height: percent(100),
        flex_direction: FlexDirection::Column,
        justify_content: JustifyContent::Center,
        align_items: AlignItems::Center,
        padding: UiRect::all(px(24)),
        row_gap: px(14),
        ..default()
    }
}

fn loading_screen(mut commands: Commands, font: Res<UiFont>) {
    commands
        .spawn((ScreenRoot, screen_node(), BackgroundColor(INK)))
        .with_children(|p| {
            p.spawn(label("LOADING QIANZHU RIDGE...", 24.0, PAPER, &font.0));
        });
}

fn main_menu(mut commands: Commands, font: Res<UiFont>, store: Option<Res<SaveStore>>) {
    let has_save = store.as_ref().is_some_and(|s| s.snapshot.is_some());
    let store_msg = store
        .as_ref()
        .map(|s| s.error.as_deref().unwrap_or(&s.status).to_owned());

    commands
        .spawn((
            ScreenRoot,
            Node {
                width: percent(100),
                height: percent(100),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                padding: UiRect::all(px(24)),
                ..default()
            },
            BackgroundColor(Color::srgb(0.055, 0.09, 0.085)),
        ))
        .with_children(|p| {
            p.spawn((
                Node {
                    width: percent(100),
                    max_width: px(760),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    row_gap: px(10),
                    padding: UiRect::all(px(32)),
                    border: UiRect::all(px(1)),
                    ..default()
                },
                BorderColor::all(Color::srgb(0.31, 0.35, 0.28)),
                BackgroundColor(Color::srgb(0.075, 0.12, 0.11)),
            ))
            .with_children(|p| {
                p.spawn(label("琉 璃 剑 宗", 18.0, JADE, &font.0));
                p.spawn(label("千竹岭", 56.0, PAPER, &font.0));
                p.spawn((
                    label("方尘的修行，从一柄残剑开始", 18.0, GOLD, &font.0),
                    Node {
                        margin: UiRect::bottom(px(22)),
                        ..default()
                    },
                ));
                button(p, "新游戏", Action::Start, &font.0);
                if has_save {
                    button(p, "继续修行", Action::Continue, &font.0);
                } else {
                    p.spawn(label(
                        "暂无存档",
                        16.0,
                        Color::srgb(0.58, 0.62, 0.57),
                        &font.0,
                    ));
                }
                button(p, "操作说明", Action::Help, &font.0);
                button(p, "退出", Action::Exit, &font.0);

                if let Some(msg) = store_msg {
                    p.spawn((
                        label(&msg, 16.0, GOLD, &font.0),
                        Node {
                            max_width: percent(85),
                            ..default()
                        },
                    ));
                }
                p.spawn(label(
                    "原著：亲一下芒果《谁说没灵根不能修仙的？》",
                    15.0,
                    Color::srgb(0.6, 0.5, 0.4),
                    &font.0,
                ));
            });
        });
}

fn world_overlay(
    mut commands: Commands,
    font: Res<UiFont>,
    config: Res<WorldConfig>,
    rules: Res<GameRules>,
) {
    commands
        .spawn((
            ScreenRoot,
            Node {
                width: percent(100),
                height: percent(100),
                justify_content: JustifyContent::SpaceBetween,
                padding: UiRect::all(px(20)),
                ..default()
            },
        ))
        .with_children(|p| {
            p.spawn((
                Node {
                    width: px(470),
                    max_width: percent(65),
                    align_self: AlignSelf::FlexStart,
                    padding: UiRect::all(px(14)),
                    border: UiRect::left(px(3)),
                    ..default()
                },
                BackgroundColor(INK.with_alpha(0.88)),
                BorderColor::all(GOLD),
            ))
            .with_children(|p| {
                p.spawn((Hud, label("方尘 / 琉璃剑宗杂役", 17.0, PAPER, &font.0)));
            });
            p.spawn(Node {
                width: px(240),
                align_self: AlignSelf::FlexStart,
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                ..default()
            })
            .with_children(|p| {
                map::build_mini(p, &font.0, &config, &rules);
                p.spawn(Node {
                    display: Display::Grid,
                    grid_template_columns: RepeatedGridTrack::flex(2, 1.0),
                    column_gap: px(4),
                    row_gap: px(4),
                    ..default()
                })
                .with_children(|p| {
                    button(p, "暂停", Action::Pause, &font.0);
                    button(p, "背包 B", Action::Inventory, &font.0);
                    button(p, "修行记录 T", Action::Journal, &font.0);
                    button(p, "武学 K", Action::Martial, &font.0);
                    button(p, "角色 C", Action::Character, &font.0);
                    button(p, "强化 U", Action::Enhancement, &font.0);
                    button(p, "门派 H", Action::Sect, &font.0);
                    button(p, "地图 M", Action::WorldMap, &font.0);
                    button(p, "聊天", Action::Chat, &font.0);
                });
            });
            hotbar::build(p, &font.0);
            chat::build_history(p, &font.0);
        });
}

fn error_screen(mut commands: Commands, error: Res<LoadError>, font: Res<UiFont>) {
    commands
        .spawn((ScreenRoot, screen_node(), BackgroundColor(INK)))
        .with_children(|p| {
            // Keep diagnostics readable even if a missing font caused loading to fail.
            p.spawn(label(
                "RESOURCE LOAD FAILED",
                32.0,
                GOLD,
                &Handle::default(),
            ));
            p.spawn((
                label(&error.0, 20.0, PAPER, &Handle::default()),
                Node {
                    max_width: percent(90),
                    ..default()
                },
            ));
            button(p, "QUIT", Action::Exit, &font.0);
        });
}

fn clear_screen(mut commands: Commands, roots: Query<Entity, With<ScreenRoot>>) {
    for entity in &roots {
        commands.entity(entity).despawn();
    }
}

fn clear_panel(
    mut commands: Commands,
    roots: Query<Entity, With<PanelRoot>>,
    mut ui: ResMut<UiState>,
) {
    for entity in &roots {
        commands.entity(entity).despawn();
    }
    ui.panel = None;
    ui.rebuild = false;
}

fn reset_chat(mut ui: ResMut<UiState>) {
    ui.chat_input.clear();
    ui.chat_preedit.clear();
    ui.chat_filter = None;
    ui.chat_ime_input = false;
}

fn ensure_pause(mut ui: ResMut<UiState>) {
    if ui.panel.is_none() {
        ui.panel = Some(Panel::Pause);
    }
    ui.rebuild = true;
}

fn open_panel(world: &mut World, panel: Panel) {
    let mut ui = world.resource_mut::<UiState>();
    if panel != Panel::Chat {
        ui.chat_preedit.clear();
    }
    ui.panel = Some(panel);
    ui.rebuild = true;
    if *world.resource::<State<AppState>>().get() == AppState::InGame {
        world
            .resource_mut::<NextState<SessionState>>()
            .set(SessionState::Paused);
    }
}

fn resume(world: &mut World) {
    let roots = world
        .query_filtered::<Entity, With<PanelRoot>>()
        .iter(world)
        .collect::<Vec<_>>();
    for root in roots {
        world.despawn(root);
    }
    world.resource_mut::<UiState>().panel = None;
    if *world.resource::<State<AppState>>().get() == AppState::InGame {
        world
            .resource_mut::<NextState<SessionState>>()
            .set(SessionState::Playing);
    }
}

fn notify(world: &mut World, message: impl Into<String>) {
    if let Some(mut session) = world.get_resource_mut::<GameSession>() {
        session.notify(message);
    }
}

fn apply_equipment_result(world: &mut World, result: Result<String, String>) {
    match result {
        Ok(message) => {
            {
                let mut session = world.resource_mut::<GameSession>();
                session.notify(message);
                session.dirty = true;
                session.auto_save = true;
            }
            world.resource_mut::<UiState>().rebuild = true;
        }
        Err(message) => open_panel(world, Panel::Info(message)),
    }
}

fn new_game(world: &mut World) {
    if let Some(mut resume) = world.get_resource_mut::<ResumeGame>() {
        resume.0 = None;
    }
    world
        .resource_mut::<NextState<AppState>>()
        .set(AppState::InGame);
}

fn near_npc(world: &World) -> bool {
    let Some(session) = world.get_resource::<GameSession>() else {
        return false;
    };
    world
        .resource::<WorldConfig>()
        .objects
        .iter()
        .find(|o| o.id == "cao_bin")
        .is_some_and(|o| {
            Vec3::from_array(o.center).xz().distance(session.position)
                <= world.resource::<ExplorationConfig>().interaction_distance
        })
}

pub(crate) fn process_action(world: &mut World, action: Action) {
    let state = *world.resource::<State<AppState>>().get();
    match action {
        Action::Start if state == AppState::MainMenu => {
            if world.get_resource::<SaveStore>().is_some_and(|s| s.exists) {
                open_panel(world, Panel::ConfirmNew);
            } else {
                new_game(world);
            }
        }
        Action::ConfirmNew if world.resource::<UiState>().panel == Some(Panel::ConfirmNew) => {
            new_game(world)
        }
        Action::Continue if state == AppState::MainMenu => {
            if let Some(snapshot) = world
                .get_resource::<SaveStore>()
                .and_then(|s| s.snapshot.clone())
            {
                world.resource_mut::<ResumeGame>().0 = Some(snapshot);
                world
                    .resource_mut::<NextState<AppState>>()
                    .set(AppState::InGame);
            }
        }
        Action::Pause if state == AppState::InGame => open_panel(world, Panel::Pause),
        Action::Resume => resume(world),
        Action::MainMenu if state == AppState::InGame => {
            if world.get_resource::<GameSession>().is_some_and(|s| s.dirty) {
                open_panel(world, Panel::ConfirmMenu);
            } else {
                world
                    .resource_mut::<NextState<AppState>>()
                    .set(AppState::MainMenu);
            }
        }
        Action::ConfirmMenu if world.resource::<UiState>().panel == Some(Panel::ConfirmMenu) => {
            world
                .resource_mut::<NextState<AppState>>()
                .set(AppState::MainMenu);
        }
        Action::Exit => {
            if world.get_resource::<GameSession>().is_some_and(|s| s.dirty) {
                open_panel(world, Panel::ConfirmExit);
            } else {
                exit(world);
            }
        }
        Action::ConfirmExit if world.resource::<UiState>().panel == Some(Panel::ConfirmExit) => {
            exit(world)
        }
        Action::Save | Action::SaveMenu if state == AppState::InGame => {
            let safe = {
                let session = world.resource::<GameSession>();
                let config = world.resource::<WorldConfig>();
                session.progress.hp > 0
                    && session.position.distance(config.safe_zone.center.into())
                        <= config.safe_zone.radius
            };
            if !safe {
                open_panel(world, Panel::Info("只有工棚安全区内可以保存".into()));
            } else {
                match save_current(world) {
                    Ok(()) if action == Action::SaveMenu => world
                        .resource_mut::<NextState<AppState>>()
                        .set(AppState::MainMenu),
                    Ok(()) => open_panel(world, Panel::Info("进度已保存".into())),
                    Err(error) => open_panel(world, Panel::Info(error)),
                }
            }
        }
        Action::ConfirmQuest => {
            let action = match world.resource::<UiState>().panel.clone() {
                Some(Panel::Dialogue { action, .. }) => action,
                _ => return,
            };
            let rules = world.resource::<GameRules>().clone();
            let quests = world.resource::<QuestRules>().clone();
            let result = world
                .resource_mut::<GameSession>()
                .progress
                .apply_quest(action, &quests, &rules);
            match result {
                Ok(()) => {
                    world.resource_mut::<GameSession>().quest_changed(&rules);
                    if action == QuestAction::ReportVictory {
                        open_panel(world, Panel::Chapter);
                    } else {
                        resume(world);
                    }
                }
                Err(error) => open_panel(world, Panel::Info(error)),
            }
        }
        Action::Inventory if state == AppState::InGame => open_panel(world, Panel::Inventory),
        Action::Npc if state == AppState::InGame && near_npc(world) => {
            open_panel(world, Panel::Npc)
        }
        Action::Character if state == AppState::InGame => open_panel(world, Panel::Character),
        Action::Enhancement if state == AppState::InGame => open_panel(world, Panel::Enhancement),
        Action::Sect if state == AppState::InGame => open_panel(world, Panel::Sect),
        Action::WorldMap if state == AppState::InGame => open_panel(world, Panel::WorldMap),
        Action::Chat if state == AppState::InGame => open_panel(world, Panel::Chat),
        Action::ChatFilter(channel) if world.resource::<UiState>().panel == Some(Panel::Chat) => {
            let mut ui = world.resource_mut::<UiState>();
            ui.chat_filter = channel;
            ui.rebuild = true;
        }
        Action::SendChat if world.resource::<UiState>().panel == Some(Panel::Chat) => {
            chat::send(world)
        }
        Action::TrackRegion(index)
            if world.resource::<UiState>().panel == Some(Panel::WorldMap) =>
        {
            let rules = world.resource::<GameRules>();
            if let Some(region) = rules.journey.regions.get(index) {
                let waypoint = (region.label.clone(), Vec2::from_array(region.entry));
                world.resource_mut::<GameSession>().waypoint = Some(waypoint);
                resume(world);
            }
        }
        Action::ClearWaypoint if world.resource::<UiState>().panel == Some(Panel::WorldMap) => {
            world.resource_mut::<GameSession>().waypoint = None;
        }
        Action::Cast(skill)
            if state == AppState::InGame && world.resource::<UiState>().panel.is_none() =>
        {
            let rules = world.resource::<GameRules>().clone();
            world.resource_scope(|world, mut session: Mut<GameSession>| {
                session.request(
                    crate::gameplay::combat::CombatInput {
                        skill: Some(skill),
                        ..default()
                    },
                    &rules,
                    world.resource::<crate::gameplay::collision::CollisionMap>(),
                )
            });
            world
                .resource_mut::<crate::gameplay::click_move::ClickMove>()
                .cancel();
        }
        Action::SectAction(action) if world.resource::<UiState>().panel == Some(Panel::Sect) => {
            if !near_npc(world) {
                open_panel(world, Panel::Info("请到曹斌身边办理门派事务".into()));
                return;
            }
            let rules = world.resource::<GameRules>().clone();
            let quests = world.resource::<QuestRules>().clone();
            let session = &mut *world.resource_mut::<GameSession>();
            match session.progress.sect_action(action, &quests, &rules) {
                Ok(message) => {
                    session.notify(message);
                    session.dirty = true;
                    session.auto_save = true;
                    world.resource_mut::<UiState>().rebuild = true;
                }
                Err(message) => open_panel(world, Panel::Info(message)),
            }
        }
        Action::Journal if state == AppState::InGame => open_panel(world, Panel::Journal),
        Action::Martial if state == AppState::InGame => open_panel(world, Panel::Martial),
        Action::Train(skill) if world.resource::<UiState>().panel == Some(Panel::Martial) => {
            let rules = world.resource::<GameRules>().clone();
            let session = &mut *world.resource_mut::<GameSession>();
            match session.progress.learn_skill(skill, &rules) {
                Ok(message) => {
                    session.notify(message);
                    session.dirty = true;
                    session.auto_save = true;
                    world.resource_mut::<UiState>().rebuild = true;
                }
                Err(message) => open_panel(world, Panel::Info(message)),
            }
        }
        Action::Trading if state == AppState::InGame => open_panel(world, Panel::Trading),
        Action::Commissions if state == AppState::InGame => open_panel(world, Panel::Commissions),
        Action::ReportJourney if world.resource::<UiState>().panel == Some(Panel::Npc) => {
            let near = world
                .resource::<WorldConfig>()
                .objects
                .iter()
                .find(|o| o.id == "cao_bin")
                .is_some_and(|o| {
                    Vec3::from_array(o.center)
                        .xz()
                        .distance(world.resource::<GameSession>().position)
                        <= world.resource::<ExplorationConfig>().interaction_distance
                });
            if !near {
                open_panel(world, Panel::Info("请到曹斌身边回报历练".into()));
                return;
            }
            let rules = world.resource::<GameRules>().clone();
            let session = &mut *world.resource_mut::<GameSession>();
            match session.progress.report_journey(&rules) {
                Ok(message) => {
                    session.quest_changed(&rules);
                    session.notify(message);
                    world.resource_mut::<UiState>().rebuild = true;
                }
                Err(message) => open_panel(world, Panel::Info(message)),
            }
        }
        Action::Hunt(index) if world.resource::<UiState>().panel == Some(Panel::Commissions) => {
            if !near_npc(world) {
                open_panel(world, Panel::Info("请到曹斌身边领取委托".into()));
                return;
            }
            let rules = world.resource::<GameRules>().clone();
            let session = &mut *world.resource_mut::<GameSession>();
            match session.progress.claim_hunt(index, &rules) {
                Ok(message) => {
                    session.notify(message);
                    session.dirty = true;
                    session.auto_save = true;
                    world.resource_mut::<UiState>().rebuild = true;
                }
                Err(message) => open_panel(world, Panel::Info(message)),
            }
        }
        Action::Trade(action)
            if matches!(
                world.resource::<UiState>().panel,
                Some(Panel::Trading | Panel::Enhancement | Panel::Commissions)
            ) =>
        {
            let expected = match action {
                Trade::BuyPotion
                | Trade::Sell(_)
                | Trade::BuyEquipment(_)
                | Trade::SellEquipment(_) => Panel::Trading,
                Trade::UpgradeWeapon | Trade::UpgradeArmor => Panel::Enhancement,
                Trade::Commission(_) => Panel::Commissions,
            };
            if world.resource::<UiState>().panel != Some(expected) {
                return;
            }
            if !near_npc(world) {
                open_panel(world, Panel::Info("请到曹斌身边进行交易或强化".into()));
                return;
            }
            let quests = world.resource::<QuestRules>().clone();
            let rules = world.resource::<GameRules>().clone();
            let session = &mut *world.resource_mut::<GameSession>();
            match session.progress.trade(action, &quests, &rules) {
                Ok(message) => {
                    session.dirty = true;
                    session.auto_save = true;
                    session.notify(message);
                    world.resource_mut::<UiState>().rebuild = true;
                }
                Err(message) => open_panel(world, Panel::Info(message)),
            }
        }
        Action::Potion if state == AppState::InGame => {
            let rules = world.resource::<GameRules>().clone();
            world.resource_mut::<GameSession>().use_potion(&rules);
            open_panel(world, Panel::Inventory);
        }
        Action::Equip(index) if world.resource::<UiState>().panel == Some(Panel::Character) => {
            let rules = world.resource::<GameRules>().clone();
            let result = world
                .resource_mut::<GameSession>()
                .progress
                .equip_from_bag(index, &rules);
            apply_equipment_result(world, result);
        }
        Action::Unequip(slot) if world.resource::<UiState>().panel == Some(Panel::Character) => {
            let rules = world.resource::<GameRules>().clone();
            let result = world
                .resource_mut::<GameSession>()
                .progress
                .unequip(slot, &rules);
            apply_equipment_result(world, result);
        }
        Action::Discard(index) => {
            let stack = world
                .resource::<GameSession>()
                .progress
                .inventory
                .stacks
                .get(index)
                .cloned();
            if let Some(expected) = stack.filter(|s| s.item == Item::LinglongBamboo) {
                open_panel(world, Panel::Discard { index, expected });
            }
        }
        Action::ConfirmDiscard => {
            if let Some(Panel::Discard { index, expected }) =
                world.resource::<UiState>().panel.clone()
            {
                let mut session = world.resource_mut::<GameSession>();
                if session.progress.inventory.stacks.get(index) == Some(&expected)
                    && expected.item == Item::LinglongBamboo
                {
                    session.progress.inventory.stacks.remove(index);
                    session.dirty = true;
                }
                open_panel(world, Panel::Inventory);
            }
        }
        Action::Outpost
            if state == AppState::InGame && world.resource::<GameSession>().progress.hp == 0 =>
        {
            let rules = world.resource::<GameRules>().clone();
            let config = world.resource::<WorldConfig>().clone();
            world
                .resource_mut::<GameSession>()
                .return_to_outpost(&config, &rules);
            let session = world.resource::<GameSession>();
            let position = session.position;
            let yaw = session.yaw;
            let height = world.resource::<ExplorationConfig>().player_height;
            for mut transform in world
                .query_filtered::<&mut Transform, With<Player>>()
                .iter_mut(world)
            {
                transform.translation = Vec3::new(position.x, height * 0.5, position.y);
                transform.rotation = Quat::from_rotation_y(yaw);
            }
            resume(world);
        }
        Action::Help => open_panel(world, Panel::Help),
        Action::VolumeDown | Action::VolumeUp => {
            if let Some(mut settings) = world.get_resource_mut::<GameSettings>() {
                let delta = if action == Action::VolumeDown {
                    -0.1
                } else {
                    0.1
                };
                settings.volume = (settings.volume + delta).clamp(0.0, 1.0);
                if let Some(mut session) = world.get_resource_mut::<GameSession>() {
                    session.dirty = true;
                }
                open_panel(world, Panel::Pause);
            }
        }
        Action::CameraNear | Action::CameraFar => {
            let config = world.resource::<ExplorationConfig>().clone();
            let delta = if action == Action::CameraNear {
                -1.0
            } else {
                1.0
            };
            let distance = (world.resource::<GameSettings>().camera_distance + delta)
                .clamp(config.camera.min_distance, config.camera.max_distance);
            world.resource_mut::<GameSettings>().camera_distance = distance;
            world.resource_mut::<CameraRig>().distance = distance;
            world.resource_mut::<GameSession>().dirty = true;
            open_panel(world, Panel::Pause);
        }
        _ => {}
    }
}

fn exit(world: &mut World) {
    let error = *world.resource::<State<AppState>>().get() == AppState::LoadError;
    world.write_message(if error {
        AppExit::Error(std::num::NonZeroU8::MIN)
    } else {
        AppExit::Success
    });
}

pub(crate) fn button_actions(world: &mut World) {
    let actions = world
        .query_filtered::<(&Interaction, &Action, &mut BackgroundColor), Changed<Interaction>>()
        .iter_mut(world)
        .filter_map(|(interaction, action, mut background)| {
            background.0 = if *interaction == Interaction::Hovered {
                JADE
            } else {
                Color::srgb(0.10, 0.16, 0.15)
            };
            (*interaction == Interaction::Pressed).then_some(*action)
        })
        .collect::<Vec<_>>();
    // A pointer press performs one UI transaction even if overlapping buttons were hit.
    if let Some(action) = actions.first() {
        if let Some(mut audio) = world.get_resource_mut::<Messages<crate::audio::SoundRequest>>() {
            audio.write(crate::audio::SoundRequest("ui_confirm"));
        }
        process_action(world, *action);
    }
}

fn keyboard_actions(world: &mut World) {
    let keys = world.resource::<ButtonInput<KeyCode>>();
    let (escape, backpack, journal, martial, interact, pickup) = (
        keys.just_pressed(KeyCode::Escape),
        keys.just_pressed(KeyCode::KeyB),
        keys.just_pressed(KeyCode::KeyT),
        keys.just_pressed(KeyCode::KeyK),
        keys.just_pressed(KeyCode::KeyE),
        keys.just_pressed(KeyCode::KeyF),
    );
    let panel = world.resource::<UiState>().panel.clone();
    if escape {
        match panel {
            Some(Panel::Death) => {}
            Some(Panel::Discard { .. }) => open_panel(world, Panel::Inventory),
            Some(_) => resume(world),
            None => open_panel(world, Panel::Pause),
        }
        return;
    }
    if panel == Some(Panel::Chat) {
        if keys.just_pressed(KeyCode::Enter) {
            chat::send(world);
        }
        return;
    }
    let toggles = [
        (KeyCode::KeyC, Panel::Character),
        (KeyCode::KeyU, Panel::Enhancement),
        (KeyCode::KeyH, Panel::Sect),
        (KeyCode::KeyM, Panel::WorldMap),
        (KeyCode::Enter, Panel::Chat),
    ];
    for (key, target) in toggles {
        if keys.just_pressed(key) {
            if panel == Some(target.clone()) {
                resume(world);
            } else if panel.is_none() {
                open_panel(world, target);
            }
            return;
        }
    }
    if backpack {
        if panel == Some(Panel::Inventory) {
            resume(world);
        } else if panel.is_none() {
            open_panel(world, Panel::Inventory);
        }
        return;
    }
    if journal {
        if panel == Some(Panel::Journal) {
            resume(world);
        } else if panel.is_none() {
            open_panel(world, Panel::Journal);
        }
        return;
    }
    if martial {
        if panel == Some(Panel::Martial) {
            resume(world);
        } else if panel.is_none() {
            open_panel(world, Panel::Martial);
        }
        return;
    }
    if panel.is_some() || !world.contains_resource::<GameSession>() {
        return;
    }
    if pickup {
        let result = world.resource_scope(|world, mut session: Mut<GameSession>| {
            session.pickup(world.resource::<crate::gameplay::collision::CollisionMap>())
        });
        if let Err(error) = result {
            notify(world, error);
        }
    }
    if interact {
        interact_nearby(world);
    }
}

fn interact_nearby(world: &mut World) {
    let Some(nearby) = world.resource::<NearbyInteraction>().0.clone() else {
        notify(world, "附近没有可交互对象");
        return;
    };
    let stage = world.resource::<GameSession>().progress.stage;
    let action = match (nearby.id.as_str(), stage) {
        ("cao_bin", StoryStage::Report) => Some((
            QuestAction::Report,
            "杂役与残剑",
            "曹斌：到工棚挑工具，然后上山砍竹，别耽搁。",
        )),
        ("tool_rack", StoryStage::TakeSword) => Some((
            QuestAction::TakeSword,
            "黑色残剑",
            "工具架上，一柄锈迹斑斑的黑色长剑映入眼帘。取走它，去偏僻山涧查看。",
        )),
        ("sword_binding_point", StoryStage::BindSword) => Some((
            QuestAction::BindSword,
            "浮仙剑认主",
            "掌心传来异样，长剑化作剑印收入掌中。心念一动，浮仙剑再次出现在手里。\n确认后启用普攻、剑气与砍竹；取消不会完成认主。",
        )),
        ("cao_bin", StoryStage::Gathering) => Some((
            QuestAction::DeliverBamboo,
            "挥剑有所得",
            "交付3份玲珑竹材。奖励：80经验、3两银子、2瓶金疮药。\n材料不足或奖励空间不足时不会扣物、发奖。",
        )),
        ("cao_bin", StoryStage::ReturnToOutpost) => Some((
            QuestAction::ReportVictory,
            "自己的修行路",
            "竹林凶兽已除，今日的差事终于完成。\n回报后获得5两银子，并完成首章。",
        )),
        _ => None,
    };
    if let Some((action, title, body)) = action {
        world
            .resource_mut::<GameSession>()
            .log(crate::gameplay::messages::Channel::Npc, body);
        open_panel(
            world,
            Panel::Dialogue {
                action,
                title: title.into(),
                body: body.into(),
            },
        );
    } else if nearby.id == "cao_bin" && stage.sword_bound() {
        open_panel(world, Panel::Npc);
    } else {
        open_panel(world, Panel::Info(stage.objective().into()));
    }
}

fn close_requests(
    world: &mut World,
    mut cursor: Local<bevy::ecs::message::MessageCursor<bevy::window::WindowCloseRequested>>,
) {
    if cursor
        .read(world.resource::<Messages<bevy::window::WindowCloseRequested>>())
        .next()
        .is_some()
    {
        process_action(world, Action::Exit);
    }
}

fn detect_death(world: &mut World) {
    if world
        .get_resource::<GameSession>()
        .is_some_and(|s| s.progress.hp == 0)
        && !matches!(
            world.resource::<UiState>().panel,
            Some(Panel::Death | Panel::ConfirmExit | Panel::ConfirmMenu)
        )
    {
        open_panel(world, Panel::Death);
    }
}

fn refresh_hud(world: &mut World) {
    if *world.resource::<State<AppState>>().get() != AppState::InGame {
        return;
    }
    if let Some(mut session) = world.get_resource_mut::<GameSession>()
        && session
            .waypoint
            .as_ref()
            .is_some_and(|(_, target)| target.distance(session.position) <= 3.0)
    {
        let (label, _) = session.waypoint.take().expect("checked waypoint");
        session.notify(format!("已到达{label}入口"));
    }
    let nearby = world
        .resource::<NearbyInteraction>()
        .0
        .as_ref()
        .map(|n| format!("E 交互：{} ({:.1}m)", n.label, n.distance))
        .unwrap_or_default();
    let text = if let Some(session) = world.get_resource::<GameSession>() {
        let rules = world.resource::<GameRules>();
        let p = &session.progress;
        let level = rules.player.level(p.total_exp);
        let exp = if level as usize > rules.player.exp_thresholds.len() {
            "已满级".into()
        } else {
            let base = if level == 1 {
                0
            } else {
                rules.player.exp_thresholds[level as usize - 2]
            };
            format!(
                "{}/{}",
                p.total_exp - base,
                rules.player.exp_thresholds[level as usize - 1] - base
            )
        };
        let lock = session
            .locked
            .as_ref()
            .and_then(|id| session.enemies.iter().find(|e| &e.id == id))
            .map(|e| {
                format!(
                    "锁定：{} 生命 {}/{}",
                    &format!(
                        "{} Lv.{}",
                        rules.enemy(&e.kind).label,
                        rules.enemy(&e.kind).level
                    ),
                    e.hp,
                    rules.enemy(&e.kind).hp
                )
            })
            .unwrap_or_default();
        let notice = if session.notice_remaining > 0.0 {
            session.notice.as_str()
        } else {
            ""
        };
        let save = world
            .get_resource::<SaveStore>()
            .map(|s| s.status.as_str())
            .unwrap_or("");
        let audio = world
            .get_resource::<crate::audio::AudioStatus>()
            .map(|a| a.message.as_str())
            .unwrap_or("");
        let objective = objective_target(session, world.resource::<WorldConfig>(), rules)
            .map(|(label, target)| {
                let delta = target - session.position;
                let yaw = world.resource::<CameraRig>().yaw;
                let angle = (delta.x.atan2(-delta.y) + yaw).rem_euclid(std::f32::consts::TAU);
                let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"];
                let index = ((angle / std::f32::consts::FRAC_PI_4).round() as usize) % 8;
                format!("{} {label} · {:.0}m", arrows[index], delta.length())
            })
            .unwrap_or_default();
        let skills = format!(
            "R 穿云刺 {:.1}s  G 护体 {:.1}s  V 回春 {:.1}s\n护体剩余 {:.1}s  K 武学",
            session.skill_cooldowns[0],
            session.skill_cooldowns[1],
            session.skill_cooldowns[2],
            session.guard_remaining
        );
        let waypoint = session
            .waypoint
            .as_ref()
            .map(|(label, target)| {
                let delta = *target - session.position;
                let angle = (delta.x.atan2(-delta.y) + world.resource::<CameraRig>().yaw)
                    .rem_euclid(std::f32::consts::TAU);
                let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"];
                let index = ((angle / std::f32::consts::FRAC_PI_4).round() as usize) % 8;
                format!(
                    "路标 {} {label}入口 · {:.0}m",
                    arrows[index],
                    delta.length()
                )
            })
            .unwrap_or_default();
        format!(
            "方尘  ·  琉璃剑宗{}    等级 {level}\n生命 {}/{}   体力 {:.0}/100   经验 {exp}\n\n任务  {}\n{objective}\n{waypoint}\n竹材 {}   金疮药 {}   银两 {}\n\n左键/J 普攻   Q 剑气 {:.1}s\n{skills}\n空格 闪避   1 用药 {:.1}s   Tab 锁定\nWASD 移动   Shift 奔跑   右键/滚轮 镜头\n{nearby}\n{lock}\n{notice}\n{save}   {audio}",
            p.sect.title(),
            p.hp,
            rules.player.max_hp(p.total_exp),
            p.stamina,
            if p.stage == StoryStage::Completed {
                p.journey.stage.objective()
            } else {
                p.stage.objective()
            },
            p.inventory.count(Item::LinglongBamboo),
            p.inventory.count(Item::HealingPotion),
            p.silver,
            session.energy_cooldown,
            session.potion_cooldown
        )
    } else {
        format!(
            "Fang Chen / Liuli Sword Sect\nWASD move / Shift run / RMB orbit\nWheel zoom / Esc pause / F3 colliders\n{nearby}"
        )
    };
    for mut value in world
        .query_filtered::<&mut Text, With<Hud>>()
        .iter_mut(world)
    {
        if value.0 != text {
            value.0.clone_from(&text);
        }
    }
}

pub(crate) fn objective_target<'a>(
    session: &GameSession,
    config: &'a WorldConfig,
    rules: &'a GameRules,
) -> Option<(&'a str, Vec2)> {
    let id = match session.progress.stage {
        StoryStage::Report | StoryStage::ReturnToOutpost => "cao_bin",
        StoryStage::TakeSword => "tool_rack",
        StoryStage::BindSword => "sword_binding_point",
        StoryStage::Gathering if session.progress.inventory.count(Item::LinglongBamboo) >= 3 => {
            "cao_bin"
        }
        StoryStage::Gathering => {
            let bamboo = session
                .bamboo
                .iter()
                .filter(|n| n.remaining == 0.0)
                .min_by(|a, b| {
                    a.position
                        .distance_squared(session.position)
                        .total_cmp(&b.position.distance_squared(session.position))
                })?;
            bamboo.id.as_str()
        }
        StoryStage::Challenge => {
            let boss = rules.spawns.iter().find(|s| s.kind == "bamboo_beast")?;
            return Some(("竹林凶兽", boss.position.into()));
        }
        StoryStage::Completed => {
            let kind = match session.progress.journey.stage {
                JourneyStage::ValleyHunt => "valley_boar",
                JourneyStage::ValleyBoss => "valley_guardian",
                JourneyStage::NorthHunt => "frost_wolf",
                JourneyStage::NorthBoss => "frost_guardian",
                JourneyStage::ValleyReport | JourneyStage::NorthReport => {
                    return config
                        .objects
                        .iter()
                        .find(|o| o.id == "cao_bin")
                        .map(|o| (o.label.as_str(), Vec3::from_array(o.center).xz()));
                }
                JourneyStage::Completed => return None,
            };
            return session
                .enemies
                .iter()
                .filter(|e| e.kind == kind)
                .min_by(|a, b| {
                    (a.hp == 0).cmp(&(b.hp == 0)).then_with(|| {
                        a.position
                            .distance_squared(session.position)
                            .total_cmp(&b.position.distance_squared(session.position))
                    })
                })
                .map(|e| {
                    (
                        rules.enemy(kind).label.as_str(),
                        if e.hp == 0 { e.home } else { e.position },
                    )
                });
        }
    };
    config
        .objects
        .iter()
        .find(|o| o.id == id)
        .map(|o| (o.label.as_str(), Vec3::from_array(o.center).xz()))
}

fn rebuild_panel(world: &mut World) {
    if !world.resource::<UiState>().rebuild {
        return;
    }
    world.resource_mut::<UiState>().rebuild = false;
    let roots = world
        .query_filtered::<Entity, With<PanelRoot>>()
        .iter(world)
        .collect::<Vec<_>>();
    for root in roots {
        world.despawn(root);
    }
    let Some(panel) = world.resource::<UiState>().panel.clone() else {
        return;
    };
    let font = world.resource::<UiFont>().0.clone();
    let settings = world.get_resource::<GameSettings>().cloned();
    let inventory = world
        .get_resource::<GameSession>()
        .map(|s| s.progress.inventory.clone());
    let progress = world
        .get_resource::<GameSession>()
        .map(|s| s.progress.clone());
    let quests = world.get_resource::<QuestRules>().cloned();
    let rules = world.get_resource::<GameRules>().cloned();
    let config = world.get_resource::<WorldConfig>().cloned();
    let near = near_npc(world);
    let chat_input = world.resource::<UiState>().chat_input.clone();
    let chat_filter = world.resource::<UiState>().chat_filter;
    let (title, body) = match &panel {
        Panel::Pause => ("暂停修行", "世界、战斗和恢复计时已暂停。\n读档会重置短期动作和冷却；未拾取掉落物不会保存。".into()),
        Panel::Dialogue { title, body, .. } => (title.as_str(), body.clone()),
        Panel::Info(body) => ("提示", body.clone()),
        Panel::Inventory => ("行囊 · 12格", "金疮药恢复60生命；竹材用于交差。装备在角色面板（C）穿脱。点击竹材格可确认丢弃整组。".into()),
        Panel::Trading => ("工棚交易", "买入药品与装备、卖出材料与装备，结算后保存。".into()),
        Panel::Character => ("角色属性 · 方尘", "属性取自实际战斗与成长规则；装备与卸下不消耗银两。".into()),
        Panel::Enhancement => ("装备强化", "只强化已穿戴的装备，消耗银两、竹材和灵铁矿；成功后攻击或防御即时生效。".into()),
        Panel::Npc => ("曹斌 · 千竹岭管事", "交付差事、领取委托，或办理交易、强化与宗门事务。".into()),
        Panel::Sect => ("琉璃剑宗", "贡献可由捐献和宗门委托获得，用于晋升与兑换。".into()),
        Panel::WorldMap => ("江湖地图", "上北下南 · 绿点NPC / 红点怪物 / 金点掉落 / 蓝点自己。点击区域按钮设置路标。".into()),
        Panel::Chat => ("本地聊天", "记录系统、战斗、NPC与本地发言。输入/帮助查看可用指令。".into()),
        Panel::Commissions => ("工棚委托", "完成目标后领取一次奖励。".into()),
        Panel::Journal => ("修行记录", "当前进度".into()),
        Panel::Martial => ("武学修行", "升级消耗1修行点和银两；角色每升一级获得1修行点。\n穿云刺向前穿透；护体诀减少受伤；回春诀恢复生命。".into()),
        Panel::Discard { expected, .. } => ("丢弃竹材？", format!("将删除这组 {} 份玲珑竹材，不生成地面物品。", expected.count)),
        Panel::Death => ("你倒下了", "返回工棚恢复生命体力，保留任务、修为、背包和已击败首领标记。".into()),
        Panel::Chapter => ("首章完成 · 自己的修行路", "灵根没有改变，可手中的剑，让我看到了另一条路。\n可以继续探索、砍竹和战斗。".into()),
        Panel::ConfirmNew => ("开始新的修行？", "已有存档将由新游戏进度覆盖。取消保留原存档。".into()),
        Panel::ConfirmExit => ("放弃未保存进度并退出？", "上次成功保存后的变化将丢失。".into()),
        Panel::ConfirmMenu => ("放弃未保存进度并返回主菜单？", "上次成功保存后的变化将丢失。".into()),
        Panel::Help => ("操作说明", "WASD 移动；Shift 奔跑；右键拖动镜头；滚轮缩放\n左键/J 三段普攻；Q 范围剑气；空格闪避；Tab 锁定\nE 与最近对象交互；F 拾取；1 使用金疮药；B 背包；T 修行记录\nEsc 关闭面板或暂停；F3 显示碰撞\n先向曹斌报到、取剑并到山涧认主，再砍竹成长。\n存档记录完整进度；读档后普通敌人、竹与冷却重置。".into()),
    };
    world
        .commands()
        .spawn((
            PanelRoot,
            Node {
                position_type: PositionType::Absolute,
                ..screen_node()
            },
            GlobalZIndex(10),
            BackgroundColor(Color::srgba(0.025, 0.04, 0.035, 0.90)),
        ))
        .with_children(|root| {
            root.spawn((
                Node {
                    width: percent(85),
                    max_width: px(1000),
                    flex_direction: FlexDirection::Column,
                    align_items: AlignItems::Center,
                    row_gap: px(10),
                    padding: UiRect::all(px(24)),
                    border: UiRect::all(px(1)),
                    ..default()
                },
                BackgroundColor(INK),
                BorderColor::all(GOLD),
            ))
            .with_children(|p| {
                p.spawn(label(title, 32.0, GOLD, &font));
                p.spawn((
                    label(body, 20.0, PAPER, &font),
                    Node {
                        max_width: percent(100),
                        ..default()
                    },
                ));
                match panel {
                    Panel::Pause => {
                        p.spawn(Node {
                            width: percent(100),
                            justify_content: JustifyContent::Center,
                            column_gap: px(10),
                            ..default()
                        })
                        .with_children(|p| {
                            button(p, "返回游戏", Action::Resume, &font);
                            button(p, "保存进度（安全区）", Action::Save, &font);
                        });
                        p.spawn(Node {
                            width: percent(100),
                            justify_content: JustifyContent::Center,
                            column_gap: px(10),
                            ..default()
                        })
                        .with_children(|p| {
                            button(p, "保存并返回主菜单（安全区）", Action::SaveMenu, &font);
                            button(p, "返回主菜单（放弃未保存）", Action::MainMenu, &font);
                        });
                        if let Some(settings) = settings {
                            p.spawn(label(
                                format!(
                                    "主音量 {:.0}% / 镜头 {:.0}m",
                                    settings.volume * 100.0,
                                    settings.camera_distance
                                ),
                                20.0,
                                GOLD,
                                &font,
                            ));
                            p.spawn(Node {
                                width: percent(100),
                                justify_content: JustifyContent::Center,
                                column_gap: px(10),
                                ..default()
                            })
                            .with_children(|p| {
                                button(p, "音量 −", Action::VolumeDown, &font);
                                button(p, "音量 +", Action::VolumeUp, &font);
                            });
                            p.spawn(Node {
                                width: percent(100),
                                justify_content: JustifyContent::Center,
                                column_gap: px(10),
                                ..default()
                            })
                            .with_children(|p| {
                                button(p, "镜头拉近", Action::CameraNear, &font);
                                button(p, "镜头拉远", Action::CameraFar, &font);
                            });
                        }
                        button(p, "直接退出（放弃未保存）", Action::Exit, &font);
                    }
                    Panel::Dialogue { .. } => {
                        button(p, "确认", Action::ConfirmQuest, &font);
                        if near && progress.as_ref().is_some_and(|p| p.stage.sword_bound()) {
                            button(p, "曹斌 · 交易、强化与宗门事务", Action::Npc, &font);
                        }
                        button(p, "取消", Action::Resume, &font);
                    }
                    Panel::Trading
                    | Panel::Enhancement
                    | Panel::Character
                    | Panel::Npc
                    | Panel::Sect => {
                        if let (Some(progress), Some(rules), Some(quests)) =
                            (&progress, &rules, &quests)
                        {
                            panels::build(p, &font, &panel, progress, rules, quests, near);
                        }
                    }
                    Panel::WorldMap => {
                        if let (Some(config), Some(rules)) = (&config, &rules) {
                            map::build_world(p, &font, config, rules);
                        }
                        button(p, "关闭", Action::Resume, &font);
                    }
                    Panel::Chat => {
                        chat::build_panel(p, &font, &chat_input, chat_filter);
                    }
                    Panel::Commissions => {
                        if let (Some(progress), Some(rules)) = (&progress, &rules) {
                            for (i, title) in ["云溪谷狩猎", "寒石古道狩猎"].iter().enumerate()
                            {
                                let used = u64::from(progress.journey.repeat_claimed[i])
                                    * u64::from(rules.journey.repeat_goals[i]);
                                let remaining = u64::from(progress.journey.kills[i]) - used;
                                button(
                                    p,
                                    &format!(
                                        "{title} · {remaining}/{} · {}两 / {}经验",
                                        rules.journey.repeat_goals[i],
                                        rules.journey.repeat_silver[i],
                                        rules.journey.repeat_exp[i]
                                    ),
                                    Action::Hunt(i),
                                    &font,
                                );
                            }
                        }
                        if let (Some(progress), Some(quests)) = (&progress, &quests) {
                            let counts = progress.adventure.commission_progress();
                            for (i, title) in
                                ["击败野猪", "击败山狼", "采伐玲珑竹"].iter().enumerate()
                            {
                                let status = if progress.adventure.commissions_claimed[i] {
                                    "已领取".to_owned()
                                } else {
                                    format!(
                                        "{}/{} · {}两 / {}经验",
                                        counts[i],
                                        quests.economy.commission_goals[i],
                                        quests.economy.commission_silver[i],
                                        quests.economy.commission_exp[i]
                                    )
                                };
                                button(
                                    p,
                                    &format!("{}  {}", title, status),
                                    Action::Trade(Trade::Commission(i)),
                                    &font,
                                );
                            }
                        }
                        button(p, "返回补给", Action::Trading, &font);
                        button(p, "离开", Action::Resume, &font);
                    }
                    Panel::Journal => {
                        if let (Some(progress), Some(quests), Some(rules)) =
                            (&progress, &quests, &rules)
                        {
                            p.spawn(label(progress.stage.objective(), 20.0, PAPER, &font));
                            let gear = |slot: EquipmentSlot| {
                                progress
                                    .equipped(slot)
                                    .map(|item| item.display(&rules.equipment))
                                    .unwrap_or_else(|| "未装备".into())
                            };
                            p.spawn(label(
                                format!(
                                    "{}  ·  {}  ·  银两 {}",
                                    gear(EquipmentSlot::Weapon),
                                    gear(EquipmentSlot::Armor),
                                    progress.silver
                                ),
                                18.0,
                                GOLD,
                                &font,
                            ));
                            let counts = progress.adventure.commission_progress();
                            for (i, title) in
                                ["击败野猪", "击败山狼", "采伐玲珑竹"].iter().enumerate()
                            {
                                let status = if progress.adventure.commissions_claimed[i] {
                                    "已领取".to_owned()
                                } else if counts[i] >= quests.economy.commission_goals[i] {
                                    "可领取".to_owned()
                                } else {
                                    format!("{}/{}", counts[i], quests.economy.commission_goals[i])
                                };
                                p.spawn(label(
                                    format!("{}  ·  {}", title, status),
                                    18.0,
                                    PAPER,
                                    &font,
                                ));
                            }
                        }
                        button(p, "关闭", Action::Resume, &font);
                    }
                    Panel::Martial => {
                        if let (Some(progress), Some(rules)) = (&progress, &rules) {
                            let level = rules.player.level(progress.total_exp);
                            p.spawn(label(
                                format!(
                                    "等级 {level}  ·  可用修行点 {}  ·  银两 {}",
                                    level - 1 - progress.martial.spent(),
                                    progress.silver
                                ),
                                20.0,
                                GOLD,
                                &font,
                            ));
                            for skill in crate::gameplay::skills::Skill::ALL {
                                let rank = progress.martial.ranks[skill.index()];
                                let status = if rank == 3 {
                                    "已满级".into()
                                } else if skill.index() > 0
                                    && level < rules.skills.unlock_levels[skill.index() - 1]
                                {
                                    format!(
                                        "等级{}解锁",
                                        rules.skills.unlock_levels[skill.index() - 1]
                                    )
                                } else {
                                    format!(
                                        "{} · {}两 / 1修行点",
                                        if rank == 0 { "学习" } else { "升级" },
                                        rules.skills.training_prices[rank as usize]
                                    )
                                };
                                button(
                                    p,
                                    &format!(
                                        "{} {}  {rank}/3级  ·  {status}",
                                        skill.key(),
                                        skill.label()
                                    ),
                                    Action::Train(skill),
                                    &font,
                                );
                            }
                        }
                        button(p, "关闭", Action::Resume, &font);
                    }
                    Panel::Inventory => {
                        if let Some(inventory) = inventory {
                            p.spawn(Node {
                                width: percent(100),
                                display: Display::Grid,
                                grid_template_columns: RepeatedGridTrack::flex(3, 1.0),
                                row_gap: px(8),
                                column_gap: px(8),
                                ..default()
                            })
                            .with_children(|p| {
                                for i in 0..12 {
                                    if let Some(stack) = inventory.stacks.get(i) {
                                        let text =
                                            format!("{} ×{}", stack.item.label(), stack.count);
                                        match stack.item {
                                            Item::HealingPotion => {
                                                button(p, &text, Action::Potion, &font)
                                            }
                                            Item::LinglongBamboo => {
                                                button(p, &text, Action::Discard(i), &font)
                                            }
                                            Item::BeastHide | Item::WolfFang | Item::SpiritOre => {
                                                p.spawn(label(text, 20.0, PAPER, &font));
                                            }
                                        }
                                    } else {
                                        p.spawn(label(
                                            format!("{} · 空", i + 1),
                                            20.0,
                                            JADE,
                                            &font,
                                        ));
                                    }
                                }
                            });
                        }
                        button(p, "关闭行囊", Action::Resume, &font);
                    }
                    Panel::Discard { .. } => {
                        button(p, "确认丢弃", Action::ConfirmDiscard, &font);
                        button(p, "取消", Action::Inventory, &font);
                    }
                    Panel::Death => {
                        button(p, "返回工棚", Action::Outpost, &font);
                        button(p, "直接退出", Action::Exit, &font);
                    }
                    Panel::ConfirmNew => {
                        button(p, "确认新游戏", Action::ConfirmNew, &font);
                        button(p, "取消", Action::Resume, &font);
                    }
                    Panel::ConfirmExit => {
                        button(p, "确认退出", Action::ConfirmExit, &font);
                        button(p, "取消", Action::Resume, &font);
                    }
                    Panel::ConfirmMenu => {
                        button(p, "确认返回", Action::ConfirmMenu, &font);
                        button(p, "取消", Action::Resume, &font);
                    }
                    Panel::Info(_) => {
                        button(p, "关闭", Action::Resume, &font);
                    }
                    Panel::Chapter | Panel::Help => {
                        button(p, "继续", Action::Resume, &font);
                    }
                }
            });
        });
}

#[cfg(test)]
#[path = "ui_tests.rs"]
mod tests;
