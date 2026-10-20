// Generate only the marked download block; all other documentation is preserved.
const start = '<!-- release-downloads:start -->';
const end = '<!-- release-downloads:end -->';

function downloadBlock(release) {
  const version = release.tag_name.replace(/^v/, '');
  if (!/^\d+\.\d+\.\d+$/.test(version) || release.draft || release.prerelease) {
    throw new Error('Expected a published stable version');
  }
  const find = name => {
    const asset = release.assets.find(item => item.name === name && item.state === 'uploaded');
    if (!asset) throw new Error(`Missing uploaded release asset: ${name}`);
    const url = new URL(asset.browser_download_url);
    if (url.origin !== 'https://github.com') throw new Error('Unexpected download host');
    return url.href;
  };
  const setup = find(`mpv+-${version}-Setup.exe`);
  const zip = find(`mpv+-${version}.zip`);
  return `${start}
**Актуальная версия: [${version}](${release.html_url}) · Windows 10/11 x64**

| Система | Установщик | Портативная версия |
| --- | --- | --- |
| Windows 10/11 x64 | [![Setup x64](https://img.shields.io/badge/Windows-Setup_x64-0078D4?style=flat-square)](${setup}) | [![Portable x64](https://img.shields.io/badge/Windows-Portable_x64-2496ED?style=flat-square)](${zip}) |

Установщик — установка с выбором папки и созданием ярлыков. Портативная версия — запуск из распакованной папки.

[Все выпуски](https://github.com/Notme-SI/mpv-plus/releases) · [Изменения](${release.html_url}) · [Контрольные суммы](releases/${version}/SHA256SUMS.txt)
${end}`;
}

function replaceDownloadBlock(readme, release) {
  if (readme.split(start).length !== 2 || readme.split(end).length !== 2 || readme.indexOf(end) < readme.indexOf(start)) {
    throw new Error('Expected one complete download block in README.md');
  }
  return readme.slice(0, readme.indexOf(start)) + downloadBlock(release) + readme.slice(readme.indexOf(end) + end.length);
}

async function syncDownloads({ github, context, core }) {
  const repo = { owner: context.repo.owner, repo: context.repo.repo };
  const { data: release } = await github.rest.repos.getLatestRelease(repo);
  const { data: file } = await github.rest.repos.getContent({ ...repo, path: 'README.md', ref: 'main' });
  const current = Buffer.from(file.content, 'base64').toString('utf8');
  const updated = replaceDownloadBlock(current, release);
  if (updated === current) return core.info('Download links are already current');
  const { data: owner } = await github.rest.users.getByUsername({ username: repo.owner });
  const identity = { name: owner.login, email: `${owner.id}+${owner.login}@users.noreply.github.com` };
  await github.rest.repos.createOrUpdateFileContents({
    ...repo, path: 'README.md', branch: 'main', sha: file.sha,
    message: `docs: update downloads for ${release.tag_name}`,
    content: Buffer.from(updated).toString('base64'),
    author: identity,
    committer: identity,
  });
}

module.exports = { downloadBlock, replaceDownloadBlock, syncDownloads };
