"""Create a reviewable Windows runtime folder and ZIP from a verified release binary."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "target" / "dist" / "SoloRxjh-liuli-0.5-windows-x64"


def collect_licenses(destination):
    result = subprocess.run(["cargo", "metadata", "--locked", "--offline", "--format-version", "1",
        "--filter-platform", "x86_64-pc-windows-msvc"], cwd=ROOT, check=True, capture_output=True, text=True, encoding="utf-8")
    metadata = json.loads(result.stdout)
    active = {node["id"] for node in metadata["resolve"]["nodes"]}
    records = []
    missing = []
    for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
        if package["id"] not in active or package["source"] is None:
            continue
        source = Path(package["manifest_path"]).parent
        files = [p for p in source.iterdir() if p.is_file() and
            p.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT", "UNLICENSE"))]
        if package["license_file"]:
            explicit = source / package["license_file"]
            if explicit.is_file() and explicit not in files:
                files.append(explicit)
        supplement = ROOT / "LICENSES" / "supplemental" / f'{package["name"]}-{package["version"]}'
        if supplement.exists():
            provenance = json.loads((supplement / "source.json").read_text(encoding="utf-8"))
            for entry in provenance:
                file = supplement / entry["file"]
                if hashlib.sha256(file.read_bytes()).hexdigest() != entry["sha256"]:
                    raise RuntimeError(f"License source checksum mismatch: {file}")
                files.append(file)
            files.append(supplement / "source.json")
        if not files:
            missing.append(f'{package["name"]} {package["version"]}: {package["license"]}')
        folder = destination / "crates" / f'{package["name"]}-{package["version"]}'
        folder.mkdir(parents=True)
        for file in files:
            shutil.copy2(file, folder / file.name)
        records.append({"name":package["name"], "version":package["version"],
            "license":package["license"], "repository":package["repository"],
            "files":[str((folder / p.name).relative_to(destination)).replace("\\", "/") for p in files]})
    (destination / "dependencies.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# Rust dependency notices", "", "Generated from Cargo.lock and the resolved Windows dependency graph.", "",
        "| Package | Version | Declared license |", "| --- | --- | --- |"]
    lines += [f'| {r["name"]} | {r["version"]} | {r["license"]} |' for r in records]
    (destination / "README.md").write_text("\n".join(lines)+"\n", encoding="utf-8")
    if missing:
        raise RuntimeError("Review packages without bundled license texts:\n" + "\n".join(missing))
    return len(records)


def main():
    executable = ROOT / "target" / "release" / "solo-rxjh.exe"
    if not executable.is_file():
        raise RuntimeError("Build cargo build --release --locked --offline --bin solo-rxjh first")
    if DEST.exists() or DEST.with_suffix(".zip").exists():
        raise FileExistsError(f"Output already exists; review and remove this exact generated folder before rebuilding: {DEST}")
    DEST.mkdir(parents=True)
    shutil.copy2(executable, DEST / executable.name)
    for directory in ["config", "audio", "fonts"]:
        shutil.copytree(ROOT / "assets" / directory, DEST / "assets" / directory)
    models = DEST / "assets" / "models" / "characters"
    models.mkdir(parents=True)
    for name in ["fang_chen", "cao_bin", "boar", "mountain_wolf", "bamboo_beast", "linglong_bamboo"]:
        shutil.copy2(ROOT / "assets" / "models" / "characters" / (name+".glb"), models / (name+".glb"))
    shutil.copy2(ROOT / "assets" / "README.md", DEST / "assets" / "README.md")
    shutil.copy2(ROOT / "docs" / "10-运行与发布.md", DEST / "运行说明.md")
    licenses = collect_licenses(DEST / "LICENSES")
    shutil.copy2(ROOT / "LICENSES" / "README.md", DEST / "LICENSES" / "来源说明.md")
    entries = [{"path":p.relative_to(DEST).as_posix(), "bytes":p.stat().st_size,
        "sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(DEST.rglob("*")) if p.is_file()]
    (DEST / "manifest.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8")
    archive = DEST.with_suffix(".zip")
    archive_stamp = time.localtime(executable.stat().st_mtime)[:6]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for file in sorted(DEST.rglob("*")):
            if file.is_file():
                entry = zipfile.ZipInfo((Path(DEST.name) / file.relative_to(DEST)).as_posix(), archive_stamp)
                z.writestr(entry, file.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    print(f"PACKAGE_CREATED {DEST}; {licenses} dependencies; {len(entries)+1} files")
    print(f"ZIP {archive}; SHA256 {hashlib.sha256(archive.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
