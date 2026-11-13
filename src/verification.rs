//! Native GPU verification only; excluded unless the verification feature is enabled.
use std::{
    collections::HashSet,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use bevy::{
    prelude::*,
    render::{
        renderer::RenderAdapterInfo,
        view::screenshot::{Screenshot, ScreenshotCaptured},
    },
};

use crate::{
    LaunchOptions,
    app::{AppState, SessionState, WorldEntity},
    build_app,
    data::LoadError,
    ui::Action,
};

mod expansion;
mod model;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Case {
    World,
    Exploration,
    MissingConfig,
    Performance,
    Expansion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Step {
    Menu,
    World,
    Model,
    Walk,
    Orbit,
    Pause,
    Return,
    Error,
    Profile,
    Expansion(u8),
}

#[derive(Clone, Resource, Default)]
struct Completion(Arc<Mutex<Option<Result<(), String>>>>);

#[derive(Clone, Resource, Default)]
struct RenderProbe(Arc<Mutex<RenderStatus>>);

#[derive(Resource)]
struct VerificationTarget(Handle<Image>);

fn bind_verification_target(target: Res<VerificationTarget>, mut cameras: Query<&mut Camera>) {
    for mut camera in &mut cameras {
        if !matches!(&camera.target, bevy::camera::RenderTarget::Image(image) if image.handle == target.0)
        {
            camera.target = bevy::camera::RenderTarget::Image(target.0.clone().into());
        }
    }
}

#[derive(Default, Clone, Copy)]
struct RenderStatus {
    meshes: usize,
    opaque_phases: usize,
    pending_pipelines: usize,
}

#[derive(Resource)]
struct Verification {
    case: Case,
    step: Step,
    frames: u32,
    cycles: u8,
    world_counts: Option<(usize, usize)>,
    started: Instant,
    output: PathBuf,
    saved: HashSet<&'static str>,
    capture_pending: bool,
    capture_error: Option<String>,
    walk_start: Option<(Vec3, f64)>,
    observed: Option<(Step, AppState)>,
    profile: Option<(Instant, Instant, Vec<f64>, bool)>,
}

pub fn run(args: Vec<String>) -> Result<(), String> {
    let (case, name) = match args.first().map(String::as_str) {
        Some("world") => (Case::World, "world"),
        Some("exploration") => (Case::Exploration, "exploration"),
        Some("missing-config") => (Case::MissingConfig, "missing-config"),
        Some("performance") => (Case::Performance, "performance"),
        Some("expansion") => (Case::Expansion, "expansion"),
        _ => {
            return Err(
                "Usage: verify-native <world|exploration|expansion|missing-config|performance> [--assets-dir PATH]"
                    .into(),
            );
        }
    };
    let options = LaunchOptions::parse(args.into_iter().skip(1).map(std::ffi::OsString::from))?;
    if options.help || (case == Case::MissingConfig && options.assets_dir.is_some()) {
        return Err(
            "missing-config uses its own absent directory; --help is not a verification case"
                .into(),
        );
    }
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut output = root.join("target/verification").join(name);
    if let Some(path) = &options.assets_dir {
        output = output.join(
            path.file_name()
                .ok_or("Test assets directory must have a final component")?,
        );
    }
    let assets = if case != Case::MissingConfig {
        options.assets_dir.unwrap_or_else(|| root.join("assets"))
    } else {
        let missing = root.join("target/verification/missing-assets");
        if missing.exists() {
            return Err(format!(
                "Expected absent test directory: {}",
                missing.display()
            ));
        }
        missing
    };
    std::fs::create_dir_all(&output).map_err(|error| error.to_string())?;
    let completion = Completion::default();
    let mut app = build_app(LaunchOptions {
        assets_dir: Some(assets),
        save_dir: Some(output.join("saves")),
        help: false,
    })?;
    // Fixed offscreen rendering keeps verification independent of desktop window visibility.
    let mut target = Image::new_target_texture(
        1600,
        900,
        bevy::render::render_resource::TextureFormat::Bgra8UnormSrgb,
    );
    target.texture_descriptor.usage |= bevy::render::render_resource::TextureUsages::COPY_SRC;
    let target = app.world_mut().resource_mut::<Assets<Image>>().add(target);
    for mut window in app
        .world_mut()
        .query::<&mut Window>()
        .iter_mut(app.world_mut())
    {
        window.visible = false;
    }
    app.insert_resource(VerificationTarget(target))
        .insert_resource(bevy::winit::WinitSettings::continuous())
        .add_systems(Update, bind_verification_target.after(drive));
    app.insert_resource(completion.clone())
        .insert_resource(Verification {
            case,
            step: if case != Case::MissingConfig {
                Step::Menu
            } else {
                Step::Error
            },
            frames: 0,
            cycles: 0,
            world_counts: None,
            started: Instant::now(),
            output,
            saved: HashSet::new(),
            capture_pending: false,
            capture_error: None,
            walk_start: None,
            observed: None,
            profile: None,
        })
        .add_systems(Startup, log_adapter)
        .add_systems(Update, drive.before(crate::ui::button_actions));
    let render_probe = RenderProbe::default();
    app.insert_resource(render_probe.clone());
    app.sub_app_mut(bevy::render::RenderApp)
        .insert_resource(render_probe)
        .add_systems(
            bevy::render::Render,
            probe_render
                .after(bevy::render::RenderSystems::Render)
                .before(bevy::render::RenderSystems::Cleanup),
        );
    let exit = app.run();
    completion
        .0
        .lock()
        .map_err(|error| error.to_string())?
        .take()
        .ok_or("Verification ended before completing its assertions")??;
    let expected = if case != Case::MissingConfig {
        AppExit::Success
    } else {
        AppExit::Error(std::num::NonZeroU8::MIN)
    };
    if exit != expected {
        return Err(format!("Expected {expected:?}, got {exit:?}"));
    }
    eprintln!("[VERIFY] PASS: {name}; expected exit {exit:?}");
    Ok(())
}

fn log_adapter(info: Res<RenderAdapterInfo>) {
    eprintln!(
        "[VERIFY] adapter: {} / {:?} / {}",
        info.name, info.backend, info.driver_info
    );
}

fn probe_render(
    cache: Res<bevy::render::render_resource::PipelineCache>,
    meshes: Res<bevy::pbr::RenderMeshInstances>,
    phases: Res<
        bevy::render::render_phase::ViewBinnedRenderPhases<bevy::core_pipeline::core_3d::Opaque3d>,
    >,
    probe: Res<RenderProbe>,
) {
    let meshes = match &*meshes {
        bevy::pbr::RenderMeshInstances::CpuBuilding(meshes) => meshes.len(),
        bevy::pbr::RenderMeshInstances::GpuBuilding(meshes) => meshes.len(),
    };
    let pending_pipelines = cache
        .pipelines()
        .filter(|pipeline| {
            !matches!(
                pipeline.state,
                bevy::render::render_resource::CachedPipelineState::Ok(_)
            )
        })
        .count();
    *probe.0.lock().expect("Render verification lock poisoned") = RenderStatus {
        meshes,
        opaque_phases: phases.values().filter(|phase| !phase.is_empty()).count(),
        pending_pipelines,
    };
}

fn drive(world: &mut World) {
    let result =
        world.resource_scope(|world, mut verification: Mut<Verification>| verification.tick(world));
    match result {
        Ok(false) => {}
        finished => {
            let result = finished.map(|_| ());
            if let Err(error) = &result {
                eprintln!("[VERIFY] FAIL: {error}");
            }
            let failed = result.is_err();
            let completion = world.resource::<Completion>().clone();
            match completion.0.lock() {
                Ok(mut slot) => *slot = Some(result),
                Err(error) => eprintln!("[VERIFY] completion lock failed: {error}"),
            }
            if failed {
                world.write_message(AppExit::Error(std::num::NonZeroU8::MIN));
            }
        }
    }
}

impl Verification {
    fn tick(&mut self, world: &mut World) -> Result<bool, String> {
        if self.started.elapsed() > Duration::from_secs(240) {
            return Err("Native verification exceeded 240 seconds".into());
        }
        if let Some(error) = self.capture_error.take() {
            return Err(error);
        }
        let state = *world.resource::<State<AppState>>().get();
        if self.observed != Some((self.step, state)) {
            eprintln!("[VERIFY] step={:?}, state={state:?}", self.step);
            self.observed = Some((self.step, state));
        }
        if self.case != Case::MissingConfig && state == AppState::LoadError {
            return Err(world.resource::<LoadError>().0.clone());
        }
        let confirmation = match (self.step, state) {
            (Step::World, AppState::MainMenu) => Some(Action::ConfirmNew),
            (Step::Return, AppState::InGame) => Some(Action::ConfirmMenu),
            _ => None,
        };
        if let Some(action) = confirmation
            && world.query::<&Action>().iter(world).any(|a| *a == action)
        {
            press(world, action)?;
            return Ok(false);
        }
        let expected = match self.step {
            Step::Menu | Step::Return => AppState::MainMenu,
            Step::World | Step::Model | Step::Walk | Step::Orbit | Step::Pause | Step::Profile => {
                AppState::InGame
            }
            Step::Expansion(_) => AppState::InGame,
            Step::Error => AppState::LoadError,
        };
        if state != expected {
            self.frames = 0;
            return Ok(false);
        }
        self.frames += 1;
        if self.frames < 12 || self.capture_pending {
            return Ok(false);
        }
        match self.step {
            Step::Menu => {
                verify_menu(world)?;
                if self.capture(world, "menu") {
                    return Ok(false);
                }
                press(world, Action::Start)?;
                self.advance(Step::World);
            }
            Step::World => {
                let mut models =
                    world.query_filtered::<Entity, With<crate::presentation::AnimatedModel>>();
                let roots = models.iter(world).collect::<Vec<_>>();
                let mut children = world.query::<&Children>();
                let children = children.query(world);
                if roots.is_empty()
                    || roots.iter().any(|root| {
                        !children
                            .iter_descendants(*root)
                            .any(|e| world.get::<AnimationPlayer>(e).is_some())
                    })
                {
                    return Ok(false);
                }
                let render = *world
                    .resource::<RenderProbe>()
                    .0
                    .lock()
                    .map_err(|error| format!("Render verification lock poisoned: {error}"))?;
                if render.pending_pipelines != 0 || render.meshes == 0 || render.opaque_phases == 0
                {
                    return Ok(false);
                }
                let roots = world
                    .query_filtered::<Entity, With<WorldEntity>>()
                    .iter(world)
                    .count();
                let meshes = world.query::<&Mesh3d>().iter(world).count();
                if roots == 0
                    || meshes == 0
                    || world.query::<&Camera3d>().iter(world).count() != 1
                    || world.query::<&DirectionalLight>().iter(world).count() != 1
                {
                    return Err("World roots, meshes, camera or light count is invalid".into());
                }
                if let Some(counts) = self.world_counts {
                    if counts != (roots, meshes) {
                        return Err("World entity counts changed between sessions".into());
                    }
                } else {
                    self.world_counts = Some((roots, meshes));
                }
                if self.capture(world, "scene") {
                    return Ok(false);
                }
                if self.case == Case::Performance {
                    world.insert_resource(bevy::light::DirectionalLightShadowMap::default());
                    for mut cascade in world
                        .query::<&mut bevy::light::CascadeShadowConfig>()
                        .iter_mut(world)
                    {
                        *cascade = bevy::light::CascadeShadowConfigBuilder::default().build();
                    }
                    self.profile = Some((Instant::now(), Instant::now(), vec![], false));
                    self.advance(Step::Profile);
                    return Ok(false);
                }
                if self.case == Case::Exploration && self.cycles == 0 {
                    self.advance(Step::Model);
                    return Ok(false);
                }
                if self.case == Case::Expansion && self.cycles == 0 {
                    expansion::prepare(world)?;
                    self.advance(Step::Expansion(0));
                    return Ok(false);
                }
                self.cycles += 1;
                eprintln!(
                    "[VERIFY] world cycle {}: {roots} roots, {meshes} meshes, camera=1, sun=1",
                    self.cycles
                );
                press(world, Action::Pause)?;
                self.advance(Step::Pause);
            }
            Step::Model => {
                if !model::check(world)? {
                    return Ok(false);
                }
                if world
                    .resource::<RenderProbe>()
                    .0
                    .lock()
                    .map_err(|e| e.to_string())?
                    .pending_pipelines
                    != 0
                {
                    return Ok(false);
                }
                if self.capture(world, "model") {
                    return Ok(false);
                }
                eprintln!(
                    "[VERIFY] Blender GLB: axes/metres, 5 meshes, 2 skins, 2 joints, visibility hierarchy and playing ProbeWave passed"
                );
                self.walk_start = Some((
                    player_position(world)?,
                    world.resource::<Time>().elapsed_secs_f64(),
                ));
                world
                    .resource_mut::<ButtonInput<KeyCode>>()
                    .press(KeyCode::KeyW);
                self.advance(Step::Walk);
            }
            Step::Walk => {
                let (start, since) = self.walk_start.ok_or("Movement observation not started")?;
                let elapsed = world.resource::<Time>().elapsed_secs_f64() - since;
                if elapsed < 1.2 {
                    return Ok(false);
                }
                let distance = start.distance(player_position(world)?);
                let speed = world
                    .resource::<crate::data::ExplorationConfig>()
                    .walk_speed;
                if (distance - speed * elapsed as f32).abs() > 0.5 {
                    return Err(format!(
                        "Native movement mismatch: {distance} metres in {elapsed} seconds"
                    ));
                }
                eprintln!(
                    "[VERIFY] native W movement: {distance:.3} metres / {elapsed:.3} seconds"
                );
                world
                    .resource_mut::<ButtonInput<KeyCode>>()
                    .release(KeyCode::KeyW);
                world
                    .resource_mut::<ButtonInput<MouseButton>>()
                    .press(MouseButton::Right);
                world.write_message(bevy::input::mouse::MouseMotion {
                    delta: Vec2::new(100.0, 0.0),
                });
                world.write_message(bevy::input::mouse::MouseWheel {
                    unit: bevy::input::mouse::MouseScrollUnit::Line,
                    x: 0.0,
                    y: -2.0,
                    window: Entity::PLACEHOLDER,
                });
                world.write_message(bevy::input::keyboard::KeyboardInput {
                    key_code: KeyCode::F3,
                    logical_key: bevy::input::keyboard::Key::F3,
                    state: bevy::input::ButtonState::Pressed,
                    text: None,
                    repeat: false,
                    window: Entity::PLACEHOLDER,
                });
                self.advance(Step::Orbit);
            }
            Step::Orbit => {
                let rig = world.resource::<crate::gameplay::exploration::CameraRig>();
                if (rig.yaw - (-0.4_f32).rem_euclid(std::f32::consts::TAU)).abs() > 1e-4
                    || (rig.distance - 8.6).abs() > 1e-4
                    || !world
                        .resource::<crate::gameplay::exploration::CollisionDebug>()
                        .0
                {
                    return Err("Native orbit/zoom/F3 input failed".into());
                }
                if self.capture(world, "exploration") {
                    return Ok(false);
                }
                world
                    .resource_mut::<ButtonInput<MouseButton>>()
                    .release(MouseButton::Right);
                self.cycles += 1;
                press(world, Action::Pause)?;
                self.advance(Step::Pause);
            }
            Step::Pause => {
                if *world.resource::<State<SessionState>>().get() != SessionState::Paused {
                    return Err("Pause button did not pause the session".into());
                }
                if self.capture(world, "pause") {
                    return Ok(false);
                }
                press(world, Action::MainMenu)?;
                self.advance(Step::Return);
            }
            Step::Return => {
                verify_menu(world)?;
                let target = world.resource::<VerificationTarget>().0.clone();
                let size = world
                    .resource::<Assets<Image>>()
                    .get(&target)
                    .expect("Verification render target must exist")
                    .size();
                let last_cycle = if self.case == Case::Expansion && size.x != 1600 {
                    1
                } else {
                    10
                };
                if self.cycles == last_cycle {
                    if self.capture(world, "returned-menu") {
                        return Ok(false);
                    }
                    let next_size = match (self.case, size.x) {
                        (Case::Expansion, 1600) => Some(UVec2::new(1280, 720)),
                        (Case::Expansion, 1280) => Some(UVec2::new(2560, 1440)),
                        _ => None,
                    };
                    if let Some(size) = next_size {
                        world
                            .resource_mut::<Assets<Image>>()
                            .get_mut(&target)
                            .expect("Verification render target must exist")
                            .resize(bevy::render::render_resource::Extent3d {
                                width: size.x,
                                height: size.y,
                                depth_or_array_layers: 1,
                            });
                        self.saved.clear();
                        self.cycles = 0;
                        self.started = Instant::now();
                        self.advance(Step::Menu);
                        return Ok(false);
                    }
                    press(world, Action::Exit)?;
                    return Ok(true);
                }
                press(world, Action::Start)?;
                self.advance(Step::World);
            }
            Step::Error => {
                verify_menu(world)?;
                if !world.resource::<LoadError>().0.contains("world.ron") {
                    return Err("Error page does not identify the missing configuration".into());
                }
                if self.capture(world, "error") {
                    return Ok(false);
                }
                press(world, Action::Exit)?;
                return Ok(true);
            }
            Step::Profile => {
                let (started, previous, samples, optimized) =
                    self.profile.as_mut().expect("profile started");
                let now = Instant::now();
                let delta = now.duration_since(*previous).as_secs_f64();
                *previous = now;
                if started.elapsed().as_secs_f64() < 5.0 {
                    return Ok(false);
                }
                samples.push(delta);
                if samples.iter().sum::<f64>() < 60.0 {
                    return Ok(false);
                }
                let total = samples.iter().sum::<f64>();
                let fps = samples.len() as f64 / total;
                samples.sort_by(f64::total_cmp);
                let p95 = samples[((samples.len() - 1) as f64 * 0.95).ceil() as usize] * 1000.0;
                let label = if *optimized {
                    "one-cascade-1024"
                } else {
                    "previous-default-shadows"
                };
                let report = format!(
                    "{label}: {} frames / {total:.3}s, average {fps:.2} FPS, P95 {p95:.2}ms",
                    samples.len()
                );
                eprintln!("[VERIFY] {report}");
                std::fs::write(self.output.join(format!("{label}.txt")), report)
                    .map_err(|e| e.to_string())?;
                if *optimized {
                    world.write_message(AppExit::Success);
                    return Ok(true);
                }
                world.insert_resource(bevy::light::DirectionalLightShadowMap { size: 1024 });
                for mut cascade in world
                    .query::<&mut bevy::light::CascadeShadowConfig>()
                    .iter_mut(world)
                {
                    *cascade = bevy::light::CascadeShadowConfigBuilder {
                        num_cascades: 1,
                        maximum_distance: 36.0,
                        ..default()
                    }
                    .build();
                }
                self.profile = Some((Instant::now(), Instant::now(), vec![], true));
            }
            Step::Expansion(phase) => self.expansion(world, phase)?,
        }
        Ok(false)
    }

    fn advance(&mut self, step: Step) {
        self.step = step;
        self.frames = 0;
    }

    fn capture(&mut self, world: &mut World, label: &'static str) -> bool {
        if self.saved.contains(label) {
            return false;
        }
        self.capture_pending = true;
        for window in world.query::<&Window>().iter(world) {
            eprintln!(
                "[VERIFY] {label} window={}x{}",
                window.physical_width(),
                window.physical_height()
            );
        }
        for camera in world.query::<&Camera>().iter(world) {
            eprintln!(
                "[VERIFY] {label} camera order={} target={:?}",
                camera.order,
                camera.physical_target_size()
            );
        }
        if label == "scene" {
            let probe = world.resource::<RenderProbe>();
            if let Ok(status) = probe.0.lock() {
                eprintln!(
                    "[VERIFY] GPU ready: {} mesh instances, {} opaque phases, {} pending pipelines",
                    status.meshes, status.opaque_phases, status.pending_pipelines
                );
            }
        }
        let target = world.resource::<VerificationTarget>().0.clone();
        let expected = world
            .resource::<Assets<Image>>()
            .get(&target)
            .expect("Verification render target must exist")
            .size();
        let directory = if expected == UVec2::new(1600, 900) {
            self.output.clone()
        } else {
            self.output.join(format!("{}x{}", expected.x, expected.y))
        };
        if let Err(error) = std::fs::create_dir_all(&directory) {
            self.capture_error = Some(error.to_string());
            return true;
        }
        if self.case == Case::Expansion {
            for (action, node, transform) in world
                .query::<(&Action, &ComputedNode, &UiGlobalTransform)>()
                .iter(world)
            {
                if node.size().min_element() <= 0.0 {
                    continue;
                }
                let half = node.size() * 0.5;
                let min = transform.translation - half;
                let max = transform.translation + half;
                if min.min_element() < -1.0 || (max - expected.as_vec2()).max_element() > 1.0 {
                    self.capture_error = Some(format!(
                        "{label}: button {action:?} is outside {expected:?}: {min:?}..{max:?}"
                    ));
                    return true;
                }
            }
        }
        let path = directory.join(format!("{label}.png"));
        world.spawn(Screenshot::image(target)).observe(
            move |event: On<ScreenshotCaptured>, mut verification: ResMut<Verification>| {
                let size = event.image.texture_descriptor.size;
                eprintln!(
                    "[VERIFY] {label} captured size={}x{}",
                    size.width, size.height
                );
                let result = if UVec2::new(size.width, size.height) != expected {
                    Err(format!(
                        "Invalid screenshot size: {}x{}, expected {expected:?}",
                        size.width, size.height,
                    ))
                } else {
                    event
                        .image
                        .clone()
                        .try_into_dynamic()
                        .map_err(|error| error.to_string())
                        .and_then(|image| {
                            let image = image.to_rgb8();
                            image.save(&path).map_err(|error| error.to_string())?;
                            if label == "scene" {
                                // Exclude HUD edges: a uniform background cannot prove a 3D scene.
                                let colors: HashSet<_> = image
                                    .enumerate_pixels()
                                    .filter(|(x, y, _)| {
                                        *x >= size.width / 4
                                            && *x < size.width * 3 / 4
                                            && *y >= size.height / 3
                                            && *y < size.height * 4 / 5
                                    })
                                    .step_by(8)
                                    .map(|(_, _, pixel)| pixel.0)
                                    .collect();
                                if colors.len() < 16 {
                                    return Err(format!(
                                        "Scene capture is blank or lacks visible geometry: {} sampled colors",
                                        colors.len()
                                    ));
                                }
                            }
                            Ok(())
                        })
                };
                verification.capture_pending = false;
                match result {
                    Ok(()) => {
                        verification.saved.insert(label);
                        eprintln!("[VERIFY] captured {}", path.display());
                    }
                    Err(error) => {
                        verification.capture_error = Some(format!("{}: {error}", path.display()))
                    }
                }
            },
        );
        true
    }
}

fn verify_menu(world: &mut World) -> Result<(), String> {
    if world
        .query_filtered::<Entity, With<WorldEntity>>()
        .iter(world)
        .count()
        != 0
        || world.query::<&Mesh3d>().iter(world).count() != 0
        || world.query::<&Camera3d>().iter(world).count() != 0
        || world.query::<&DirectionalLight>().iter(world).count() != 0
        || world.query::<&Camera>().iter(world).count() != 1
    {
        return Err("World entities remain on the menu/error screen".into());
    }
    Ok(())
}

fn player_position(world: &mut World) -> Result<Vec3, String> {
    world
        .query_filtered::<&Transform, With<crate::gameplay::exploration::Player>>()
        .single(world)
        .map(|t| t.translation)
        .map_err(|e| e.to_string())
}

fn press(world: &mut World, action: Action) -> Result<(), String> {
    eprintln!("[VERIFY] pressing {action:?}");
    let buttons: Vec<Entity> = world
        .query::<(Entity, &Action)>()
        .iter(world)
        .filter_map(|(entity, candidate)| (*candidate == action).then_some(entity))
        .collect();
    if buttons.len() != 1 {
        return Err(format!(
            "Expected exactly one matching button, found {}",
            buttons.len()
        ));
    }
    *world
        .get_mut::<Interaction>(buttons[0])
        .ok_or("Button has no Interaction component")? = Interaction::Pressed;
    Ok(())
}
