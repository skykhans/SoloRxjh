use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};

use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use crate::{
    data::{ExplorationConfig, WorldConfig},
    gameplay::{
        combat::{GameSession, collision_map},
        config::GameRules,
        equipment::{Equipment, Loadout},
        progress::Progress,
    },
};

pub const SCHEMA_VERSION: u32 = 4;
pub const CONTENT_VERSION: &str = "liuli-0.6";

const MIGRATED_STARTER_WEAPON: &str = "fuxian_sword";
const MIGRATED_STARTER_ARMOR: &str = "menial_robe";

#[derive(Resource, Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameSettings {
    pub volume: f32,
    pub camera_distance: f32,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub schema_version: u32,
    pub content_version: String,
    pub progress: Progress,
    pub position: [f32; 2],
    pub yaw: f32,
    pub settings: GameSettings,
}

impl Snapshot {
    pub fn decode(bytes: &[u8]) -> Result<Self, String> {
        let header: serde_json::Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        let version = header.get("schema_version").and_then(|v| v.as_u64());
        let content = header.get("content_version").and_then(|v| v.as_str());
        match (version, content) {
            (Some(1), Some("liuli-0.3")) => Self::migrate_fixed_progress(bytes),
            (Some(2), Some("liuli-0.4")) => Self::migrate_extension_fields(header, 2),
            (Some(3), Some("liuli-0.5")) => Self::migrate_extension_fields(header, 3),
            _ => serde_json::from_slice(bytes).map_err(|e| e.to_string()),
        }
    }

    fn migrate_fixed_progress(bytes: &[u8]) -> Result<Self, String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct OldProgress {
            total_exp: u32,
            hp: u32,
            stamina: f32,
            silver: u32,
            inventory: super::gameplay::progress::Inventory,
            stage: super::gameplay::progress::StoryStage,
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct OldSnapshot {
            schema_version: u32,
            content_version: String,
            progress: OldProgress,
            position: [f32; 2],
            yaw: f32,
            settings: GameSettings,
        }
        let old: OldSnapshot = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        if old.schema_version != 1 || old.content_version != "liuli-0.3" {
            return Err("旧档版本不符".into());
        }
        Ok(Self {
            schema_version: SCHEMA_VERSION,
            content_version: CONTENT_VERSION.into(),
            progress: Progress {
                total_exp: old.progress.total_exp,
                hp: old.progress.hp,
                stamina: old.progress.stamina,
                silver: old.progress.silver,
                inventory: old.progress.inventory,
                stage: old.progress.stage,
                adventure: Default::default(),
                loadout: Loadout {
                    weapon: old
                        .progress
                        .stage
                        .sword_owned()
                        .then(|| Equipment::new(MIGRATED_STARTER_WEAPON)),
                    armor: Some(Equipment::new(MIGRATED_STARTER_ARMOR)),
                    bag: Vec::new(),
                },
                martial: Default::default(),
                journey: Default::default(),
                sect: Default::default(),
            },
            position: old.position,
            yaw: old.yaw,
            settings: old.settings,
        })
    }

    fn migrate_extension_fields(mut root: serde_json::Value, version: u32) -> Result<Self, String> {
        let progress = root
            .get_mut("progress")
            .and_then(|value| value.as_object_mut())
            .ok_or("旧档缺少角色进度")?;
        if version == 2 {
            for field in ["sect", "journey", "martial"] {
                if progress.contains_key(field) {
                    return Err(format!("旧档包含未知{field}字段"));
                }
            }
        }
        if progress.contains_key("loadout") {
            return Err("旧档包含未知装备字段".into());
        }
        let adventure = progress
            .get_mut("adventure")
            .and_then(|value| value.as_object_mut())
            .ok_or("旧档缺少委托进度")?;
        let sword_rank = adventure
            .remove("sword_rank")
            .and_then(|value| value.as_u64())
            .ok_or("旧档缺少武器强化等级")?;
        let armor_rank = adventure
            .remove("armor_rank")
            .and_then(|value| value.as_u64())
            .ok_or("旧档缺少护甲强化等级")?;
        let stage = progress
            .get("stage")
            .and_then(|value| value.as_str())
            .ok_or("旧档缺少任务阶段")?
            .to_owned();
        let owned = matches!(
            stage.as_str(),
            "bind_sword" | "gathering" | "challenge" | "return_to_outpost" | "completed"
        );
        let weapon = if owned {
            serde_json::json!({ "id": MIGRATED_STARTER_WEAPON, "rank": sword_rank })
        } else {
            serde_json::Value::Null
        };
        progress.insert(
            "loadout".into(),
            serde_json::json!({
                "weapon": weapon,
                "armor": { "id": MIGRATED_STARTER_ARMOR, "rank": armor_rank },
                "bag": [],
            }),
        );
        if version == 2 {
            for (field, value) in [
                (
                    "martial",
                    serde_json::to_value(super::gameplay::skills::MartialProgress::default())
                        .map_err(|e| e.to_string())?,
                ),
                (
                    "journey",
                    serde_json::to_value(super::gameplay::journey::JourneyProgress::default())
                        .map_err(|e| e.to_string())?,
                ),
                (
                    "sect",
                    serde_json::to_value(super::gameplay::sect::SectProgress::default())
                        .map_err(|e| e.to_string())?,
                ),
            ] {
                progress.insert(field.into(), value);
            }
        }
        root["schema_version"] = SCHEMA_VERSION.into();
        root["content_version"] = CONTENT_VERSION.into();
        serde_json::from_value(root).map_err(|e| e.to_string())
    }

    pub fn capture(session: &GameSession, settings: &GameSettings) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            content_version: CONTENT_VERSION.into(),
            progress: session.progress.clone(),
            position: session.position.to_array(),
            yaw: session.yaw,
            settings: settings.clone(),
        }
    }

    pub fn validate(
        &self,
        rules: &GameRules,
        world: &WorldConfig,
        exploration: &ExplorationConfig,
    ) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION || self.content_version != CONTENT_VERSION {
            return Err(format!(
                "存档版本不兼容：schema={} content={}",
                self.schema_version, self.content_version
            ));
        }
        self.progress.inventory.validate()?;
        self.progress.validate_loadout(rules)?;
        self.progress.validate_journey(&rules.journey)?;
        self.progress.validate_sect(&rules.sect, &rules.player)?;
        self.progress
            .martial
            .validate(rules.player.level(self.progress.total_exp), &rules.skills)?;
        if !self.progress.stage.sword_bound() && self.progress.martial != Default::default() {
            return Err("尚未认主的存档不能学习武学".into());
        }
        let player = &self.progress;
        if player.total_exp
            > *rules
                .player
                .exp_thresholds
                .last()
                .expect("validated thresholds")
            || player.hp == 0
            || player.hp > rules.player.max_hp(player.total_exp)
            || !player.stamina.is_finite()
            || !(0.0..=rules.player.stamina).contains(&player.stamina)
            || !self.yaw.is_finite()
            || !self.settings.volume.is_finite()
            || !(0.0..=1.0).contains(&self.settings.volume)
            || !self.settings.camera_distance.is_finite()
            || !(exploration.camera.min_distance..=exploration.camera.max_distance)
                .contains(&self.settings.camera_distance)
        {
            return Err("存档中生命、经验、体力或设置非法".into());
        }
        let position = Vec2::from_array(self.position);
        let map = collision_map(world, player.stage, &[]);
        if !position.is_finite()
            || position.abs().max_element() >= map.half_size - exploration.player_radius
            || map
                .movement
                .iter()
                .any(|b| b.overlaps_circle(position, exploration.player_radius))
        {
            return Err("存档位置越界或与恢复后的场景阻挡重叠，请离开采集点后重试保存".into());
        }
        Ok(())
    }
}

#[derive(Resource, Debug)]
pub struct SaveStore {
    pub path: PathBuf,
    pub snapshot: Option<Snapshot>,
    pub exists: bool,
    pub error: Option<String>,
    pub status: String,
}

impl SaveStore {
    pub fn new(directory: PathBuf) -> Self {
        Self {
            path: directory.join("save.json"),
            snapshot: None,
            exists: false,
            error: None,
            status: "暂无存档".into(),
        }
    }

    pub fn resolve(explicit: Option<PathBuf>) -> Result<Self, String> {
        let directory = match explicit {
            Some(path) => std::path::absolute(path).map_err(|e| e.to_string())?,
            None => {
                let base = std::env::var_os("LOCALAPPDATA")
                    .ok_or("无法解析 LOCALAPPDATA，请使用 --save-dir 指定存档目录")?;
                PathBuf::from(base).join("SoloRxjh")
            }
        };
        Ok(Self::new(directory))
    }

    pub fn refresh(
        &mut self,
        rules: &GameRules,
        world: &WorldConfig,
        exploration: &ExplorationConfig,
    ) {
        self.snapshot = None;
        self.exists = self.path.exists();
        self.error = None;
        let temporary = self.path.with_extension("json.tmp");
        if temporary.exists() {
            self.error = Some(format!(
                "发现未提交的临时存档 {}；请检查后手动移除，不会自动读取或覆盖",
                temporary.display()
            ));
        }
        let result = match fs::read(&self.path) {
            Ok(bytes) => Snapshot::decode(&bytes)
                .and_then(|snapshot| {
                    snapshot.validate(rules, world, exploration)?;
                    Ok(snapshot)
                })
                .map(Some),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error.to_string()),
        };
        match result {
            Ok(snapshot) => {
                self.snapshot = snapshot;
                self.status = if self.snapshot.is_some() {
                    "已有有效存档"
                } else {
                    "暂无存档"
                }
                .into();
            }
            Err(error) => {
                let error = format!("{}: {error}", self.path.display());
                self.status = "存档无法读取".into();
                self.error = Some(error);
            }
        }
    }

    pub fn save(
        &mut self,
        snapshot: Snapshot,
        rules: &GameRules,
        world: &WorldConfig,
        exploration: &ExplorationConfig,
    ) -> Result<(), String> {
        let result = snapshot
            .validate(rules, world, exploration)
            .and_then(|()| serde_json::to_vec_pretty(&snapshot).map_err(|e| e.to_string()))
            .and_then(|bytes| atomic_write(&self.path, &bytes));
        match result {
            Ok(()) => {
                self.snapshot = Some(snapshot);
                self.exists = true;
                self.error = None;
                self.status = "进度已保存".into();
                Ok(())
            }
            Err(reason) => {
                let error = format!("保存失败 {}: {reason}", self.path.display());
                self.status = "保存失败，内存进度保留".into();
                self.error = Some(error.clone());
                Err(error)
            }
        }
    }
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    atomic_write_with(path, bytes, replace_file)
}

fn atomic_write_with(
    path: &Path,
    bytes: &[u8],
    commit: impl FnOnce(&Path, &Path) -> std::io::Result<()>,
) -> Result<(), String> {
    let parent = path.parent().ok_or("存档路径没有父目录")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let temporary = path.with_extension("json.tmp");
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(|e| e.to_string())?;
    let write_result = file.write_all(bytes).and_then(|()| file.sync_all());
    drop(file);
    let result = write_result.and_then(|()| commit(path, &temporary));
    if let Err(error) = result {
        return match fs::remove_file(&temporary) {
            Ok(()) => Err(error.to_string()),
            Err(cleanup) => Err(format!("{error}；临时文件清理失败：{cleanup}")),
        };
    }
    Ok(())
}

#[cfg(windows)]
fn replace_file(path: &Path, temporary: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MOVEFILE_WRITE_THROUGH, MoveFileExW, ReplaceFileW,
    };
    let target = path
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    let source = temporary
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    // Both UTF-16 buffers are terminated and live until the synchronous call returns.
    let success = unsafe {
        if path.exists() {
            ReplaceFileW(
                target.as_ptr(),
                source.as_ptr(),
                std::ptr::null(),
                0,
                std::ptr::null(),
                std::ptr::null(),
            )
        } else {
            MoveFileExW(source.as_ptr(), target.as_ptr(), MOVEFILE_WRITE_THROUGH)
        }
    };
    if success == 0 {
        Err(std::io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_file(path: &Path, temporary: &Path) -> std::io::Result<()> {
    fs::rename(temporary, path)
}

#[derive(Resource, Default)]
pub struct ResumeGame(pub Option<Snapshot>);

pub struct SavePlugin;

impl Plugin for SavePlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<ResumeGame>()
            .add_systems(
                OnEnter(crate::app::AppState::MainMenu),
                refresh_slot.before(crate::ui::MenuBuildSet),
            )
            .add_systems(
                Update,
                auto_save
                    .run_if(in_state(crate::app::AppState::InGame))
                    .after(crate::ui::button_actions),
            );
    }
}

fn refresh_slot(
    mut store: ResMut<SaveStore>,
    rules: Res<GameRules>,
    world: Res<WorldConfig>,
    exploration: Res<ExplorationConfig>,
) {
    store.refresh(&rules, &world, &exploration);
}

pub fn save_current(world: &mut World) -> Result<(), String> {
    let settings = world.resource::<GameSettings>().clone();
    let snapshot = Snapshot::capture(world.resource::<GameSession>(), &settings);
    let rules = world.resource::<GameRules>().clone();
    let map = world.resource::<WorldConfig>().clone();
    let exploration = world.resource::<ExplorationConfig>().clone();
    world
        .resource_mut::<SaveStore>()
        .save(snapshot, &rules, &map, &exploration)?;
    let mut session = world.resource_mut::<GameSession>();
    session.dirty = false;
    session.auto_save = false;
    Ok(())
}

fn auto_save(world: &mut World) {
    if !world.resource::<GameSession>().auto_save
        || world.resource::<GameSession>().progress.hp == 0
    {
        return;
    }
    // A failed automatic save remains visible and can be retried from the pause menu.
    world.resource_mut::<GameSession>().auto_save = false;
    if let Err(error) = save_current(world) {
        world.resource_mut::<GameSession>().notify(error);
    }
}

#[cfg(test)]
pub(crate) struct TestSaveDirectory(pub PathBuf);

#[cfg(test)]
impl TestSaveDirectory {
    pub fn new() -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        let id = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("target/verification/save-tests")
            .join(format!("{}-{id}", std::process::id()));
        assert!(!path.exists());
        Self(path)
    }
}

#[cfg(test)]
impl Drop for TestSaveDirectory {
    fn drop(&mut self) {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/verification/save-tests");
        assert!(self.0.is_absolute() && self.0.starts_with(root));
        if self.0.exists() {
            fs::remove_dir_all(&self.0).expect("clean isolated save directory");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        data::load_configs,
        gameplay::{
            equipment::Equipment,
            progress::{QuestRules, StoryStage},
        },
    };

    #[test]
    fn known_legacy_saves_migrate_explicitly_and_invalid_skill_state_is_rejected() {
        let assets = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (world, exploration) = load_configs(&assets).unwrap();
        let rules = GameRules::load(&assets, &world).unwrap();
        let quests = QuestRules::load(&assets).unwrap();
        let mut session = GameSession::new(&world, &rules, &quests);
        session.progress.stage = StoryStage::Gathering;
        session.progress.loadout.weapon = Some(Equipment::new("fuxian_sword"));
        let settings = GameSettings {
            volume: 0.7,
            camera_distance: 7.0,
        };
        let snapshot = Snapshot::capture(&session, &settings);
        for (version, content) in [(1, "liuli-0.3"), (2, "liuli-0.4"), (3, "liuli-0.5")] {
            let mut old = serde_json::to_value(&snapshot).unwrap();
            old["schema_version"] = version.into();
            old["content_version"] = content.into();
            let progress = old["progress"].as_object_mut().unwrap();
            progress.remove("loadout");
            if version < 3 {
                progress.remove("martial");
                progress.remove("journey");
                progress.remove("sect");
            }
            if version == 1 {
                progress.remove("adventure");
            } else {
                let adventure = progress["adventure"].as_object_mut().unwrap();
                adventure.insert("sword_rank".into(), 0.into());
                adventure.insert("armor_rank".into(), 0.into());
            }
            let restored = Snapshot::decode(&serde_json::to_vec(&old).unwrap()).unwrap();
            restored.validate(&rules, &world, &exploration).unwrap();
            assert_eq!(restored, snapshot);
            old["progress"]["unknown"] = 1.into();
            assert!(Snapshot::decode(&serde_json::to_vec(&old).unwrap()).is_err());
        }
        for ranks in [[0, 0, 0, 0], [4, 0, 0, 0], [1, 1, 0, 0], [1, 0, 0, 1]] {
            let mut invalid = snapshot.clone();
            invalid.progress.martial.ranks = ranks;
            assert!(invalid.validate(&rules, &world, &exploration).is_err());
        }
    }

    #[test]
    fn fixed_enhancement_ranks_migrate_into_equipment_instances() {
        let assets = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (world, exploration) = load_configs(&assets).unwrap();
        let rules = GameRules::load(&assets, &world).unwrap();
        let quests = QuestRules::load(&assets).unwrap();
        let mut session = GameSession::new(&world, &rules, &quests);
        session.progress.stage = StoryStage::Completed;
        session.progress.loadout.weapon = Some(Equipment::with_rank("fuxian_sword", 3));
        session.progress.loadout.armor = Some(Equipment::with_rank("menial_robe", 2));
        let snapshot = Snapshot::capture(
            &session,
            &GameSettings {
                volume: 0.7,
                camera_distance: 7.0,
            },
        );
        let before = session.progress.equipment_bonus(&rules);
        let mut old = serde_json::to_value(&snapshot).unwrap();
        old["schema_version"] = 3.into();
        old["content_version"] = "liuli-0.5".into();
        let progress = old["progress"].as_object_mut().unwrap();
        progress.remove("loadout");
        let adventure = progress["adventure"].as_object_mut().unwrap();
        adventure.insert("sword_rank".into(), 3.into());
        adventure.insert("armor_rank".into(), 2.into());
        let restored = Snapshot::decode(&serde_json::to_vec(&old).unwrap()).unwrap();
        restored.validate(&rules, &world, &exploration).unwrap();
        assert_eq!(restored.progress.loadout, snapshot.progress.loadout);
        assert_eq!(restored.progress.equipment_bonus(&rules), before);
        assert_eq!(before, (12, 4));
    }

    #[test]
    fn extended_growth_roundtrips_and_rejects_illegal_sect_or_journey_state() {
        use crate::gameplay::{journey::JourneyStage, progress::Item};
        let assets = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (world, exploration) = load_configs(&assets).unwrap();
        let rules = GameRules::load(&assets, &world).unwrap();
        let quests = QuestRules::load(&assets).unwrap();
        let mut session = GameSession::new(&world, &rules, &quests);
        let p = &mut session.progress;
        p.stage = StoryStage::Completed;
        p.gain_exp(5000, &rules.player);
        p.martial.ranks = [3, 3, 2, 2];
        p.loadout.weapon = Some(Equipment::with_rank("fuxian_sword", 3));
        p.loadout.armor = Some(Equipment::with_rank("menial_robe", 2));
        p.adventure.boars_defeated = 6;
        p.journey.stage = JourneyStage::Completed;
        p.journey.kills = [10, 10];
        p.journey.repeat_claimed = [2, 1];
        p.sect.rank = 3;
        p.sect.earned = 100;
        p.sect.contribution = 15;
        p.sect.commissions_claimed = [1, 0, 0];
        p.inventory.add(Item::SpiritOre, 5).unwrap();
        let snapshot = Snapshot::capture(
            &session,
            &GameSettings {
                volume: 0.7,
                camera_distance: 7.0,
            },
        );
        snapshot.validate(&rules, &world, &exploration).unwrap();
        assert_eq!(
            Snapshot::decode(&serde_json::to_vec(&snapshot).unwrap()).unwrap(),
            snapshot
        );
        for mutation in 0..5 {
            let mut bad = snapshot.clone();
            match mutation {
                0 => bad.progress.sect.rank = 4,
                1 => bad.progress.sect.contribution = 16,
                2 => bad.progress.sect.commissions_claimed[0] = 100,
                3 => bad.progress.journey.stage = JourneyStage::ValleyHunt,
                _ => bad.progress.total_exp = 0,
            }
            assert!(bad.validate(&rules, &world, &exploration).is_err());
        }
    }

    #[test]
    fn windows_atomic_replace_roundtrip_and_failed_commit_preserve_old_file() {
        let directory = TestSaveDirectory::new();
        let path = directory.0.join("save.json");
        atomic_write(&path, b"first").unwrap();
        atomic_write(&path, b"second").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"second");
        assert!(!path.with_extension("json.tmp").exists());
        let failure = atomic_write_with(&path, b"third", |_, _| {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "injected commit failure",
            ))
        });
        assert!(failure.is_err());
        assert_eq!(fs::read(&path).unwrap(), b"second");
        assert!(!path.with_extension("json.tmp").exists());
        fs::write(path.with_extension("json.tmp"), b"uncommitted").unwrap();
        assert!(atomic_write(&path, b"fourth").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"second");
        assert_eq!(
            fs::read(path.with_extension("json.tmp")).unwrap(),
            b"uncommitted"
        );
    }

    #[test]
    fn snapshot_roundtrip_invalid_content_and_bad_slot_never_silently_reset() {
        let assets = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("assets");
        let (world, exploration) = load_configs(&assets).unwrap();
        let rules = GameRules::load(&assets, &world).unwrap();
        let quests = QuestRules::load(&assets).unwrap();
        let mut session = GameSession::new(&world, &rules, &quests);
        session.progress.stage = StoryStage::ReturnToOutpost;
        session.progress.total_exp = 210;
        session.progress.hp = 73;
        let settings = GameSettings {
            volume: 0.4,
            camera_distance: 8.0,
        };
        let snapshot = Snapshot::capture(&session, &settings);
        let directory = TestSaveDirectory::new();
        let mut store = SaveStore::new(directory.0.clone());
        store
            .save(snapshot.clone(), &rules, &world, &exploration)
            .unwrap();
        store.refresh(&rules, &world, &exploration);
        assert_eq!(store.snapshot, Some(snapshot.clone()));
        for mutation in 0..7 {
            let mut invalid = snapshot.clone();
            match mutation {
                0 => invalid.schema_version += 1,
                1 => invalid.progress.hp = 0,
                2 => invalid.progress.stamina = f32::NAN,
                3 => invalid.position = [-12.0, 6.0],
                4 => invalid.position = [200.0, 0.0],
                5 => invalid.progress.inventory.stacks[0].count = 100,
                _ => invalid.settings.volume = 2.0,
            }
            assert!(store.save(invalid, &rules, &world, &exploration).is_err());
            store.refresh(&rules, &world, &exploration);
            assert_eq!(store.snapshot, Some(snapshot.clone()));
        }
        fs::write(&store.path, b"{broken json").unwrap();
        store.refresh(&rules, &world, &exploration);
        assert!(store.exists && store.snapshot.is_none() && store.error.is_some());
        assert_eq!(fs::read(&store.path).unwrap(), b"{broken json");
        let bad_stage = serde_json::to_string(&snapshot)
            .unwrap()
            .replace("return_to_outpost", "unknown_stage");
        assert!(serde_json::from_str::<Snapshot>(&bad_stage).is_err());
    }
}
