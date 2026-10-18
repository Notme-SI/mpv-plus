const test=require('node:test'),assert=require('node:assert/strict');
const {downloadBlock,replaceDownloadBlock}=require('./update-release-docs.cjs');
const release={tag_name:'v1.1.0',draft:false,prerelease:false,html_url:'https://github.com/Notme-SI/mpv-plus/releases/tag/v1.1.0',assets:['mpv+-1.1.0.zip','mpv+-1.1.0-Setup.exe'].map(name=>({name,state:'uploaded',browser_download_url:'https://github.com/Notme-SI/mpv-plus/releases/download/v1.1.0/'+encodeURIComponent(name)}))};
test('downloads require both uploaded artifacts and preserve the rest of README',()=>{
 const before='intro\n<!-- release-downloads:start -->old<!-- release-downloads:end -->\nfooter';
 const result=replaceDownloadBlock(before,release);
 assert.ok(result.startsWith('intro\n'));assert.ok(result.endsWith('\nfooter'));assert.match(result,/1\.1\.0/);
 assert.equal(replaceDownloadBlock(result,release),result);
 assert.throws(()=>downloadBlock({...release,assets:release.assets.slice(1)}),/Missing uploaded/);
 assert.throws(()=>downloadBlock({...release,prerelease:true}),/stable/);
 assert.throws(()=>replaceDownloadBlock('no markers',release),/one complete/);
});
