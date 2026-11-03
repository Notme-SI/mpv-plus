"""Overlay tracked source files on the verified clean public distribution."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import subprocess
import zipfile
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', type=Path, required=True, help='Clean mpv+ release ZIP (legacy MPV ZIP is also supported)')
parser.add_argument('--runtime-dir', type=Path, help='Already prepared mpv+.exe and ffmpeg.exe; hashes must match the source manifest')
args = parser.parse_args()
base = args.base.resolve()
checksums = (ROOT / 'releases/1.0.3/SHA256SUMS.txt').read_text().splitlines()
expected = next(line.split()[0].lower() for line in checksums if line.split()[-1] == 'mpv+-1.0.3.zip')
if hashlib.sha256(base.read_bytes()).hexdigest() != expected:
    raise SystemExit('The base ZIP is not the verified public release')
version = (ROOT / 'VERSION').read_text().strip()
out = ROOT / 'dist' / f'mpv+-{version}.zip'
if out.resolve() == base:
    raise SystemExit('Input and output must be different files')

tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode('utf-8').split('\0')
folders = {'portable_config', 'LICENSES', 'SOURCES', 'mpv'}
files = {}
with zipfile.ZipFile(base) as archive:
    for item in archive.infolist():
        path = PurePosixPath(item.filename)
        if item.is_dir():
            continue
        if path.is_absolute() or '..' in path.parts or ':' in item.filename or path.parts[0] != 'mpv+-1.0.3':
            raise SystemExit('Unexpected archive entry')
        files[PurePosixPath(*path.parts[1:]).as_posix()] = archive.read(item)

for name in tracked:
    if not name or not (ROOT/name).is_file():
        continue
    path = PurePosixPath(name)
    if path.parts[0] in folders or (len(path.parts) == 1 and path.suffix in {'.cmd', '.txt'}):
        files[name] = (ROOT / name).read_bytes()

# The fixed base supplies fonts and data. New releases may pin newer player
# binaries: never ship those old binaries under a manifest describing new ones.
components = json.loads(files['portable_config/maintenance/manifest.json'])
runtime_entries = [entry for entry in components['entries'] if entry['kind'] in {'mpv', 'ffmpeg'}]
for entry in runtime_entries:
    name = entry['path']
    expected_hash = entry['installedHash'].lower()
    if args.runtime_dir:
        content = (args.runtime_dir / name).read_bytes()
    elif hashlib.sha256(files[name]).hexdigest() == expected_hash:
        continue
    else:
        tag = entry.get('releaseTag') or entry['version']
        api = f"https://api.github.com/repos/{entry['repo']}/releases/tags/{tag}"
        request = urllib.request.Request(api, headers={'User-Agent': 'mpv-plus-builder'})
        with urllib.request.urlopen(request, timeout=30) as response:
            release = json.load(response)
        import re
        assets = [asset for asset in release['assets'] if re.search(entry['assetPattern'], asset['name'])]
        if len(assets) != 1:
            raise SystemExit('Ambiguous pinned runtime asset: ' + entry['name'])
        asset = assets[0]
        if entry['kind'] == 'ffmpeg' and asset['name'] != entry['version']:
            raise SystemExit('Unexpected pinned FFmpeg asset')
        digest = asset.get('digest', '')
        if not re.fullmatch('sha256:[a-f0-9]{64}', digest):
            raise SystemExit('Pinned runtime has no SHA-256 digest')
        cache = ROOT / 'dist/runtime-cache' / tag / entry['kind']
        cache.mkdir(parents=True, exist_ok=True)
        archive_path = cache / asset['name']
        if not archive_path.exists() or hashlib.sha256(archive_path.read_bytes()).hexdigest() != digest[7:]:
            with urllib.request.urlopen(asset['browser_download_url'], timeout=180) as response:
                archive_path.write_bytes(response.read())
        if hashlib.sha256(archive_path.read_bytes()).hexdigest() != digest[7:]:
            raise SystemExit('Runtime archive checksum mismatch')
        seven = cache / '7zr.exe'
        seven.write_bytes(files['7z/7zr.exe'])
        unpack = cache / 'extracted'
        unpack.mkdir(exist_ok=True)
        subprocess.run([str(seven), 'x', '-y', '-o'+str(unpack), str(archive_path)], check=True, stdout=subprocess.DEVNULL)
        upstream_name = 'mpv.exe' if entry['kind'] == 'mpv' else 'ffmpeg.exe'
        candidates = list(unpack.rglob(upstream_name))
        if len(candidates) != 1:
            raise SystemExit('Unexpected runtime archive structure')
        binary = candidates[0]
        upstream_hash = entry.get('upstreamHash', entry['installedHash']).lower()
        if hashlib.sha256(binary.read_bytes()).hexdigest() != upstream_hash:
            raise SystemExit('Runtime binary checksum mismatch before branding')
        if entry['kind'] == 'mpv':
            subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                str(ROOT/'portable_config/maintenance/Set-MPVIcon.ps1'), '-ExecutablePath', str(binary),
                '-IconPath', str(ROOT/'portable_config/assets/mpv-monochrome.ico')], check=True)
        content = binary.read_bytes()
    if hashlib.sha256(content).hexdigest() != expected_hash:
        raise SystemExit('Prepared runtime differs from the source manifest: ' + entry['name'])
    files[name] = content

# Retire the previous launcher name when rebuilding from a legacy ZIP.
files.pop('Обновить MPV.cmd',None)
# The verified base already contains mpv+.exe; never rename its small launcher
# over the real player when moving from the old 1.0.1 base to 1.0.3.
if 'mpv+.exe' not in files:
    raise SystemExit('Verified base is missing the player binary')
files.pop('mpv.com',None)
# Build the narrow compatibility launcher; it only forwards to ../mpv+.exe.
import os
compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
launcher = ROOT / 'dist' / 'lampa-compat' / 'mpv.exe'
launcher.parent.mkdir(parents=True,exist_ok=True)
subprocess.run([str(compiler),'/nologo','/target:winexe','/optimize+',f'/out:{launcher}',str(ROOT/'tools/LampaLauncher.cs')],check=True)
files.pop('compat/mpv.exe', None)
files['mpv.exe'] = launcher.read_bytes()
catalog = ROOT / 'portable_config/data/anime-catalog.json'
if catalog.is_file():
    files['portable_config/data/anime-catalog.json'] = catalog.read_bytes()

# Only tracked source enters a public package. Stage new files before building.
files['README.txt']=(ROOT/'README.txt').read_bytes()
files['doc/Инструкция.md']=(ROOT/'docs/USAGE.md').read_bytes()
files['doc/VERSION']=(ROOT/'VERSION').read_bytes()
files['LICENSES/SOURCES.txt']=(ROOT/'SOURCES.txt').read_bytes()
for name in list(files):
    if (name.endswith(('.cmd','.bat')) or name in {'ПРОЧТИ МЕНЯ.txt','PUBLIC-AUDIT.txt','SOURCES.txt','VERSION.txt'}): files.pop(name)
    elif PurePosixPath(name).name in {'volume-state.json','window-state.json','audio-preferences.json','subtitle-preferences.json','anime-bindings.json','anime-search-cache.json','history.json','network-report.json'} or any(part in {'cache','watch_later'} for part in PurePosixPath(name).parts):
        files.pop(name)
# Public packages must never inherit personal server credentials.
for name in files:
    if PurePosixPath(name).name in {'audio-preferences.json', 'subtitle-preferences.json', 'window-state.json', 'volume-state.json', 'anime-bindings.json', 'anime-search-cache.json', 'history.json','network-report.json'}:
        raise SystemExit('Personal playback preferences in public package')
ts = files['portable_config/script-opts/torrserver-loader.conf'].decode('utf-8-sig')
settings = {}
for line in ts.splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        settings[key.strip()] = value.strip()
if settings.get('host') not in {'127.0.0.1', 'localhost'}:
    raise SystemExit('Use a localhost TorrServer configuration for public builds')
for key, value in settings.items():
    if any(word in key.lower() for word in ('user', 'login', 'pass', 'token', 'secret')) and value:
        raise SystemExit('Remove personal TorrServer credentials before packaging')
titles = files['portable_config/script-opts/readable_titles.conf'].decode('utf-8-sig')
for line in titles.splitlines():
    if line.strip().startswith('tmdb_api_key=') and line.split('=', 1)[1].strip():
        raise SystemExit('Remove the personal TMDB token before packaging')

anime_options = files['portable_config/script-opts/autochapters.conf'].decode('utf-8-sig')
for line in anime_options.splitlines():
    if line.strip().startswith('mal_client_id=') and line.split('=', 1)[1].strip():
        raise SystemExit('Keep the public MAL application configuration empty')

out.parent.mkdir(exist_ok=True)
# Public native-application identifier supplied by the release builder, never an
# account password or Client Secret. The owner authorized its distribution.
mal_client = os.environ.get('MPV_PLUS_MAL_CLIENT_ID', '').strip()
if mal_client:
    import re
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,200}', mal_client):
        raise SystemExit('Invalid MAL application Client ID')
    files['portable_config/mal-client-id.txt'] = (mal_client + '\n').encode('ascii')
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, content in sorted(files.items()):
        archive.writestr(f'mpv+-{version}/{name}', content)
digest = hashlib.sha256(out.read_bytes()).hexdigest()
Path(str(out) + '.sha256').write_text(f'{digest}  {out.name}\n', encoding='ascii')
print(f'{out.name}: {len(files)} files, SHA-256 {digest}')
