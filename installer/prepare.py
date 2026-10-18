from pathlib import Path, PurePosixPath
import hashlib
import json
import zipfile
import sys

ROOT = Path(__file__).resolve().parent
VERSION = (ROOT.parent / 'VERSION').read_text(encoding='utf-8').strip()
ARCHIVE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT.parent / f'dist/mpv+-{VERSION}.zip'
EXPECTED = Path(str(ARCHIVE) + '.sha256').read_text(encoding='utf-8-sig').split()[0].lower()
digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
if digest != EXPECTED:
    raise SystemExit('The public archive changed. Review it before packaging.')

payload = ROOT / 'payload'
if payload.exists() and any(payload.iterdir()):
    raise SystemExit('installer/payload is not empty. Use a clean checkout or remove the old generated payload first.')
manifest = {}
with zipfile.ZipFile(ARCHIVE) as archive:
    for item in archive.infolist():
        if item.is_dir():
            continue
        normalized = item.filename.replace('\\', '/')
        entry = PurePosixPath(normalized)
        parts = entry.parts
        if entry.is_absolute() or ':' in normalized or len(parts) < 2 or parts[0] != f'mpv+-{VERSION}' or '..' in parts:
            raise SystemExit('Unexpected archive path')
        relative = Path(*parts[1:])
        target = payload / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        content = archive.read(item)
        target.write_bytes(content)
        manifest[relative.as_posix()] = hashlib.sha256(content).hexdigest()

ts = (payload / 'portable_config/script-opts/torrserver-loader.conf').read_text(encoding='utf-8-sig')
active = [line.strip() for line in ts.splitlines() if line.strip() and not line.lstrip().startswith('#')]
for line in active:
    key, _, value = line.partition('=')
    if key.strip() in ('username', 'password', 'login', 'torrserver_username', 'torrserver_password') and value.strip():
        raise SystemExit('Nonempty TorrServer credentials in public payload')
assert not (payload / 'portable_config/audio-preferences.json').exists()
assert not (payload / 'portable_config/subtitle-preferences.json').exists()
assert not (payload / 'portable_config/window-state.json').exists()

entries = []
preserved = []
for relative in sorted(manifest):
    path = Path(relative)
    personal = relative in ('portable_config/mpv.conf', 'portable_config/input.conf') or relative.startswith('portable_config/script-opts/')
    flags = 'onlyifdoesntexist uninsneveruninstall' if personal else 'ignoreversion'
    if personal:
        preserved.append(relative)
    destination = '{app}' if str(path.parent) == '.' else '{app}\\' + str(path.parent)
    entries.append(f'Source: "payload\\{path}"; DestDir: "{destination}"; Flags: {flags}')
(ROOT / 'files.iss').write_text('\n'.join(entries) + '\n', encoding='utf-8-sig')
(ROOT / 'payload-manifest.json').write_text(json.dumps({'archive_sha256': digest, 'files': manifest, 'preserved': preserved}, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({'files': len(manifest), 'bytes': sum(p.stat().st_size for p in payload.rglob('*') if p.is_file()), 'preserved_files': len(preserved)}))
