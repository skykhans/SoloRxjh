pub mod app;
pub mod audio;
pub mod data;
mod feedback;
pub mod gameplay;
pub mod presentation;
pub mod save;
pub mod ui;
pub mod world;

#[cfg(feature = "verification")]
pub mod verification;

use std::{ffi::OsString, path::PathBuf};

use bevy::{
    prelude::*,
    render::{
        RenderPlugin,
        settings::{Backends, RenderCreation, WgpuSettings},
    },
    window::{PresentMode, WindowResolution},
};

#[derive(Debug, Default)]
pub struct LaunchOptions {
    pub assets_dir: Option<PathBuf>,
    pub save_dir: Option<PathBuf>,
    pub help: bool,
}

impl LaunchOptions {
    pub fn parse(args: impl IntoIterator<Item = OsString>) -> Result<Self, String> {
        let mut options = Self::default();
        let mut args = args.into_iter();
        while let Some(argument) = args.next() {
            match argument.to_str() {
                Some("--assets-dir") => {
                    if options.assets_dir.is_some() {
                        return Err("--assets-dir may only be specified once".into());
                    }
                    let path = args.next().ok_or("--assets-dir requires a path")?;
                    options.assets_dir = Some(PathBuf::from(path));
                }
                Some("--help" | "-h") => options.help = true,
                Some("--save-dir") => {
                    if options.save_dir.is_some() {
                        return Err("--save-dir may only be specified once".into());
                    }
                    options.save_dir = Some(PathBuf::from(
                        args.next().ok_or("--save-dir requires a path")?,
                    ));
                }
                _ => return Err(format!("Unknown argument: {}", argument.to_string_lossy())),
            }
        }
        Ok(options)
    }
}

pub fn run(options: LaunchOptions) -> Result<AppExit, String> {
    Ok(build_app(options)?.run())
}

pub fn build_app(options: LaunchOptions) -> Result<App, String> {
    let save_store = save::SaveStore::resolve(options.save_dir)?;
    let paths = data::RuntimePaths::resolve(options.assets_dir)
        .map_err(|error| format!("Cannot determine resource directory: {error}"))?;
    let asset_path = paths.assets.to_string_lossy().into_owned();
    let mut app = App::new();
    app.insert_resource(paths)
        .insert_resource(save_store)
        .insert_resource(ClearColor(Color::srgb(0.073, 0.118, 0.118)))
        .insert_resource(Time::<Fixed>::from_hz(60.0))
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    close_when_requested: false,
                    primary_window: Some(Window {
                        title: "SoloRxjh · 琉璃剑宗".into(),
                        resolution: WindowResolution::new(1600, 900),
                        resize_constraints: bevy::window::WindowResizeConstraints {
                            min_width: 1280.0,
                            min_height: 720.0,
                            ..default()
                        },
                        present_mode: PresentMode::AutoVsync,
                        ..default()
                    }),
                    ..default()
                })
                .set(AssetPlugin {
                    file_path: asset_path,
                    ..default()
                })
                .set(RenderPlugin {
                    render_creation: RenderCreation::Automatic(WgpuSettings {
                        backends: Some(Backends::DX12),
                        ..default()
                    }),
                    ..default()
                }),
        )
        .add_plugins((
            app::LifecyclePlugin,
            data::DataPlugin,
            world::WorldPlugin,
            gameplay::exploration::ExplorationPlugin,
            gameplay::runtime::GameplayPlugin,
            ui::UiPlugin,
            save::SavePlugin,
            presentation::PresentationPlugin,
            audio::GameAudioPlugin,
            feedback::FeedbackPlugin,
        ));
    Ok(app)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arguments_reject_ambiguous_or_unknown_input() {
        for args in [
            vec!["--assets-dir"],
            vec!["--assets-dir", "a", "--assets-dir", "b"],
            vec!["--unknown"],
        ] {
            assert!(LaunchOptions::parse(args.into_iter().map(OsString::from)).is_err());
        }
    }
}
