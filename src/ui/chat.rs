use super::*;
use crate::gameplay::messages::Channel;
use bevy::{
    ecs::message::MessageCursor,
    input::{ButtonState, keyboard::KeyboardInput},
    window::Ime,
};

#[derive(Component)]
pub(super) struct History;
#[derive(Component)]
pub(super) struct Conversation;
#[derive(Component)]
pub(super) struct InputText;

pub(super) fn build_history(p: &mut ChildSpawnerCommands, font: &Handle<Font>) {
    p.spawn((
        Button,
        Action::Chat,
        Node {
            position_type: PositionType::Absolute,
            left: px(20),
            bottom: px(18),
            width: px(350),
            height: px(130),
            padding: UiRect::all(px(10)),
            overflow: Overflow::clip(),
            ..default()
        },
        BackgroundColor(INK.with_alpha(0.9)),
    ))
    .with_children(|p| {
        p.spawn((History, label("Enter · 本地聊天", 14.0, PAPER, font)));
    });
}

pub(super) fn build_panel(
    p: &mut ChildSpawnerCommands,
    font: &Handle<Font>,
    input: &str,
    filter: Option<Channel>,
) {
    p.spawn(Node {
        column_gap: px(5),
        ..default()
    })
    .with_children(|p| {
        for channel in [
            None,
            Some(Channel::System),
            Some(Channel::Combat),
            Some(Channel::Npc),
            Some(Channel::Local),
        ] {
            let name = channel.map_or("全部", Channel::label);
            button(
                p,
                &format!("{}{}", if filter == channel { "● " } else { "" }, name),
                Action::ChatFilter(channel),
                font,
            );
        }
    });
    p.spawn((
        Conversation,
        label("", 17.0, PAPER, font),
        Node {
            width: percent(100),
            height: px(245),
            overflow: Overflow::clip(),
            ..default()
        },
    ));
    p.spawn((
        InputText,
        label(format!("> {input}▏"), 20.0, GOLD, font),
        Node {
            width: percent(100),
            min_height: px(42),
            max_width: percent(100),
            ..default()
        },
    ));
    p.spawn(label(
        "最多120字 · Enter发送 · Esc关闭 · 支持中文输入法",
        16.0,
        PAPER,
        font,
    ));
    p.spawn(Node {
        column_gap: px(8),
        ..default()
    })
    .with_children(|p| {
        button(p, "发送", Action::SendChat, font);
        button(p, "关闭", Action::Resume, font);
    });
}

pub(super) fn send(world: &mut World) {
    let ui = world.resource::<UiState>();
    if !ui.chat_preedit.is_empty() || ui.chat_ime_input {
        return;
    }
    let text = world.resource::<UiState>().chat_input.trim().to_string();
    if text.is_empty() {
        return;
    }
    if text.chars().count() > 120 {
        notify(world, "发言不能超过120字");
        return;
    }
    let near = near_npc(world);
    let session = &mut *world.resource_mut::<GameSession>();
    session.log(Channel::Local, format!("方尘：{text}"));
    match text.as_str() {
        "/帮助" => session.log(
            Channel::System,
            "/任务 查看目标；/位置 查看坐标；/门派 查看身份；在曹斌身边输入/交谈可得到答复。",
        ),
        "/任务" => session.log(
            Channel::System,
            if session.progress.stage == StoryStage::Completed {
                session.progress.journey.stage.objective()
            } else {
                session.progress.stage.objective()
            },
        ),
        "/位置" => session.log(
            Channel::System,
            format!(
                "当前位置 {:.1}, {:.1}",
                session.position.x, session.position.y
            ),
        ),
        "/门派" => session.log(
            Channel::System,
            format!(
                "琉璃剑宗 · {} · 贡献{}",
                session.progress.sect.title(),
                session.progress.sect.contribution
            ),
        ),
        "/交谈" if near => session.log(
            Channel::Npc,
            format!(
                "曹斌：{}。交易、强化与宗门事务可按E办理。",
                if session.progress.stage == StoryStage::Completed {
                    session.progress.journey.stage.objective()
                } else {
                    session.progress.stage.objective()
                }
            ),
        ),
        "/交谈" => session.log(Channel::System, "请先走到曹斌身边，再进行交谈。"),
        _ if text.starts_with('/') => {
            session.log(Channel::System, "未知指令，输入/帮助查看可用指令。")
        }
        _ => {}
    }
    let mut ui = world.resource_mut::<UiState>();
    ui.chat_input.clear();
}

pub(super) fn input(
    world: &mut World,
    mut keyboard: Local<MessageCursor<KeyboardInput>>,
    mut ime: Local<MessageCursor<Ime>>,
) {
    let events = keyboard
        .read(world.resource::<Messages<KeyboardInput>>())
        .cloned()
        .collect::<Vec<_>>();
    let ime_events = ime
        .read(world.resource::<Messages<Ime>>())
        .cloned()
        .collect::<Vec<_>>();
    let active = world.resource::<UiState>().panel == Some(Panel::Chat);
    for mut window in world.query::<&mut Window>().iter_mut(world) {
        if window.ime_enabled != active {
            window.ime_enabled = active;
        }
    }
    if !active {
        let mut ui = world.resource_mut::<UiState>();
        ui.chat_preedit.clear();
        ui.chat_ime_input = false;
        return;
    }
    let mut ui = world.resource_mut::<UiState>();
    let committed = ime_events.iter().any(|e| matches!(e, Ime::Commit { .. }));
    let composing = !ui.chat_preedit.is_empty()
        || ime_events
            .iter()
            .any(|e| matches!(e, Ime::Preedit { value, .. } if !value.is_empty()));
    ui.chat_ime_input = committed || composing;
    for event in events {
        if event.state != ButtonState::Pressed {
            continue;
        }
        if composing {
            continue;
        }
        if event.key_code == KeyCode::Backspace {
            ui.chat_input.pop();
        } else if !committed && let Some(text) = event.text {
            for ch in text.chars().filter(|c| !c.is_control()) {
                if ui.chat_input.chars().count() < 120 {
                    ui.chat_input.push(ch);
                }
            }
        }
    }
    for event in ime_events {
        match event {
            Ime::Commit { value, .. } => {
                ui.chat_preedit.clear();
                for ch in value.chars().filter(|c| !c.is_control()) {
                    if ui.chat_input.chars().count() < 120 {
                        ui.chat_input.push(ch);
                    }
                }
            }
            Ime::Preedit { value, .. } => ui.chat_preedit = value,
            Ime::Disabled { .. } => ui.chat_preedit.clear(),
            Ime::Enabled { .. } => {}
        }
    }
}

type ChatTexts<'w, 's> = Query<
    'w,
    's,
    (
        &'static mut Text,
        Option<&'static History>,
        Option<&'static Conversation>,
        Option<&'static InputText>,
    ),
    Or<(With<History>, With<Conversation>, With<InputText>)>,
>;

pub(super) fn refresh(session: Res<GameSession>, ui: Res<UiState>, mut texts: ChatTexts) {
    for (mut text, history, conversation, input) in &mut texts {
        let value = if history.is_some() {
            let mut lines = session
                .messages
                .iter()
                .rev()
                .take(4)
                .map(|m| format!("[{}] {}", m.channel.label(), m.text))
                .collect::<Vec<_>>();
            lines.reverse();
            format!("Enter · 本地聊天\n{}", lines.join("\n"))
        } else if conversation.is_some() {
            let mut lines = session
                .messages
                .iter()
                .filter(|m| ui.chat_filter.is_none_or(|c| m.channel == c))
                .rev()
                .take(9)
                .map(|m| format!("[{}] {}", m.channel.label(), m.text))
                .collect::<Vec<_>>();
            lines.reverse();
            lines.join("\n")
        } else if input.is_some() {
            format!("> {}{}▏", ui.chat_input, ui.chat_preedit)
        } else {
            continue;
        };
        if text.0 != value {
            text.0 = value;
        }
    }
}
