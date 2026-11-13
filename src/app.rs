use bevy::prelude::*;

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum AppState {
    #[default]
    Loading,
    MainMenu,
    InGame,
    LoadError,
}

#[derive(SubStates, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
#[source(AppState = AppState::InGame)]
pub enum SessionState {
    #[default]
    Playing,
    Paused,
}

/// Every world root belongs to the current session; children are removed with it.
#[derive(Component)]
pub struct WorldEntity;

pub struct LifecyclePlugin;

impl Plugin for LifecyclePlugin {
    fn build(&self, app: &mut App) {
        app.init_state::<AppState>()
            .add_sub_state::<SessionState>()
            .add_systems(OnExit(AppState::InGame), cleanup_world);
    }
}

fn cleanup_world(mut commands: Commands, entities: Query<Entity, With<WorldEntity>>) {
    for entity in &entities {
        commands.entity(entity).despawn();
    }
    info!("World session removed");
}
