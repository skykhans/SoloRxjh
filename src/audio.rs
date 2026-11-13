use std::collections::BTreeMap;

use bevy::{
    audio::{AudioSinkPlayback, Volume},
    prelude::*,
};

use crate::{
    app::{AppState, SessionState, WorldEntity},
    gameplay::combat::{EffectKind, GameSession},
    presentation::ModelLibrary,
    save::GameSettings,
};

#[derive(Message)]
pub struct SoundRequest(pub &'static str);

#[derive(Resource, Default)]
pub struct AudioStatus {
    pub message: String,
    last_effect: u64,
    started: Option<f64>,
}

#[derive(Component)]
struct Music(&'static str);

#[derive(Component)]
struct Sound {
    kind: &'static str,
    remaining: f32,
    ui: bool,
}

pub struct GameAudioPlugin;

impl Plugin for GameAudioPlugin {
    fn build(&self, app: &mut App) {
        app.add_message::<SoundRequest>()
            .init_resource::<AudioStatus>()
            .add_systems(OnEnter(AppState::InGame), reset_audio)
            .add_systems(Update, update_audio.after(crate::ui::button_actions))
            .add_systems(Last, shutdown_audio);
    }
}

fn shutdown_audio(world: &mut World, mut exit: Local<bevy::ecs::message::MessageCursor<AppExit>>) {
    if exit
        .read(world.resource::<Messages<AppExit>>())
        .next()
        .is_none()
    {
        return;
    }
    let entities = world
        .query_filtered::<Entity, With<AudioPlayer>>()
        .iter(world)
        .collect::<Vec<_>>();
    for entity in entities {
        if let Some(sink) = world.get::<AudioSink>(entity) {
            sink.stop();
        }
        world.despawn(entity);
    }
}

fn reset_audio(mut audio: ResMut<AudioStatus>, time: Res<Time<Real>>) {
    audio.last_effect = 0;
    audio.started = Some(time.elapsed_secs_f64());
    audio.message = "音频初始化中".into();
}

fn spawn_sound(world: &mut World, kind: &'static str, ui: bool, volume: f32) {
    let source = world
        .resource::<ModelLibrary>()
        .audio
        .get(kind)
        .expect("validated audio ID")
        .clone();
    let mut entity = world.spawn((
        AudioPlayer::new(source),
        PlaybackSettings {
            volume: Volume::Linear(volume * 0.45),
            ..PlaybackSettings::DESPAWN
        },
        Sound {
            kind,
            remaining: 1.0,
            ui,
        },
    ));
    if !ui {
        entity.insert(WorldEntity);
    }
}

fn update_audio(
    world: &mut World,
    mut cursor: Local<bevy::ecs::message::MessageCursor<SoundRequest>>,
) {
    let dt = world.resource::<Time<Real>>().delta_secs();
    let paused = world
        .get_resource::<State<SessionState>>()
        .is_some_and(|s| *s.get() == SessionState::Paused);
    let Some(settings) = world.get_resource::<GameSettings>() else {
        return;
    };
    let volume = settings.volume;
    let mut remove = vec![];
    for (entity, mut sound, sink) in world
        .query::<(Entity, &mut Sound, Option<&mut AudioSink>)>()
        .iter_mut(world)
    {
        if let Some(mut sink) = sink {
            sink.set_volume(Volume::Linear(volume * 0.45));
            if paused && !sound.ui {
                sink.pause();
            } else {
                sink.play();
            }
        }
        if !paused || sound.ui {
            sound.remaining -= dt;
        }
        if sound.remaining <= 0.0 {
            remove.push(entity);
        }
    }
    for entity in remove {
        world.despawn(entity);
    }
    let requests = cursor
        .read(world.resource::<Messages<SoundRequest>>())
        .map(|r| r.0)
        .collect::<Vec<_>>();
    if !world.contains_resource::<ModelLibrary>() {
        return;
    }
    for request in requests {
        spawn_sound(world, request, true, volume);
    }
    if !world.contains_resource::<GameSession>() {
        return;
    }
    let session = world.resource::<GameSession>();
    let battle = session
        .enemies
        .iter()
        .any(|e| e.boss() && e.hp > 0 && e.position.distance(session.position) <= 12.0);
    let track = if battle {
        "bamboo_battle"
    } else {
        "qianzhu_theme"
    };
    let music = world
        .query::<(Entity, &Music)>()
        .iter(world)
        .map(|(e, m)| (e, m.0))
        .collect::<Vec<_>>();
    if !music.iter().any(|(_, m)| *m == track) {
        for (entity, _) in music {
            world.despawn(entity);
        }
        let source = world
            .resource::<ModelLibrary>()
            .audio
            .get(track)
            .expect("validated music ID")
            .clone();
        world.spawn((
            WorldEntity,
            Music(track),
            AudioPlayer::new(source),
            PlaybackSettings {
                volume: Volume::Linear(volume * 0.25),
                paused,
                ..PlaybackSettings::LOOP
            },
        ));
    }
    for mut sink in world
        .query_filtered::<&mut AudioSink, With<Music>>()
        .iter_mut(world)
    {
        sink.set_volume(Volume::Linear(volume * 0.25));
        if paused {
            sink.pause();
        } else {
            sink.play();
        }
    }
    let last = world.resource::<AudioStatus>().last_effect;
    let effects = world
        .resource::<GameSession>()
        .effects
        .iter()
        .filter(|e| e.id > last)
        .cloned()
        .collect::<Vec<_>>();
    let mut counts = BTreeMap::new();
    for sound in world.query::<&Sound>().iter(world) {
        *counts.entry(sound.kind).or_insert(0_usize) += 1;
    }
    for effect in effects {
        let kind = match effect.kind {
            EffectKind::Swing => "swing",
            EffectKind::Energy => "energy",
            EffectKind::Damage | EffectKind::Gather => "hit",
            EffectKind::Hurt => "hurt",
            EffectKind::Heal => "heal",
            EffectKind::LevelUp => "level_up",
            EffectKind::Windup => "windup",
            EffectKind::Pickup => "pickup",
            EffectKind::Dodge => "swing",
        };
        let count = counts.entry(kind).or_insert(0);
        if *count < 3 {
            spawn_sound(world, kind, false, volume);
            *count += 1;
        }
        world.resource_mut::<AudioStatus>().last_effect = effect.id;
    }
    let available = world
        .query_filtered::<&AudioSink, With<Music>>()
        .iter(world)
        .next()
        .is_some();
    let elapsed = world.resource::<Time<Real>>().elapsed_secs_f64();
    let mut status = world.resource_mut::<AudioStatus>();
    if available {
        status.message = "音频已启用".into();
    } else if status.started.is_some_and(|start| elapsed - start > 5.0) {
        status.message = "音频输出不可用，请检查系统播放设备".into();
    }
}
