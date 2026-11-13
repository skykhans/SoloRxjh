use std::collections::VecDeque;

use super::combat::GameSession;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Channel {
    System,
    Combat,
    Npc,
    Local,
}

impl Channel {
    pub fn label(self) -> &'static str {
        match self {
            Self::System => "系统",
            Self::Combat => "战斗",
            Self::Npc => "NPC",
            Self::Local => "本地",
        }
    }
}

#[derive(Clone, Debug)]
pub struct ChatMessage {
    pub channel: Channel,
    pub text: String,
}

pub const HISTORY_LIMIT: usize = 100;

impl GameSession {
    pub fn log(&mut self, channel: Channel, text: impl Into<String>) {
        if self.messages.len() == HISTORY_LIMIT {
            self.messages.pop_front();
        }
        self.messages.push_back(ChatMessage {
            channel,
            text: text.into(),
        });
    }
}

pub fn initial_messages() -> VecDeque<ChatMessage> {
    VecDeque::from([ChatMessage {
        channel: Channel::System,
        text: "欢迎来到琉璃剑宗。Enter打开本地聊天，输入/帮助查看指令。".into(),
    }])
}
