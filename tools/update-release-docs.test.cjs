const test=require('node:test'),assert=require('node:assert/strict');
const {downloadBlock,replaceDownloadBlock,syncDownloads}=require('./update-release-docs.cjs');
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

test('automatic download updates use the repository owner as author and committer',async()=>{
 let update;
 const github={rest:{repos:{
  getLatestRelease:async()=>({data:release}),
  getContent:async()=>({data:{sha:'readme-sha',content:Buffer.from('intro\n<!-- release-downloads:start -->old<!-- release-downloads:end -->\nfooter').toString('base64')}}),
  createOrUpdateFileContents:async args=>{update=args;},
 },users:{getByUsername:async args=>{
  assert.equal(args.username,'Notme-SI');
  return {data:{login:'Notme-SI',id:111609341}};
 }}}};
 await syncDownloads({github,context:{repo:{owner:'Notme-SI',repo:'mpv-plus'}},core:{info:()=>{}}});
 const identity={name:'Notme-SI',email:'111609341+Notme-SI@users.noreply.github.com'};
 assert.deepEqual(update.author,identity);
 assert.deepEqual(update.committer,identity);
 assert.equal(update.sha,'readme-sha');
 assert.equal(update.branch,'main');
 assert.equal(Buffer.from(update.content,'base64').toString('utf8'),replaceDownloadBlock('intro\n<!-- release-downloads:start -->old<!-- release-downloads:end -->\nfooter',release));
 update=undefined;
 github.rest.repos.getContent=async()=>({data:{content:Buffer.from(downloadBlock(release)).toString('base64')}});
 github.rest.users.getByUsername=async()=>{throw new Error('No identity lookup for an unchanged README');};
 await syncDownloads({github,context:{repo:{owner:'Notme-SI',repo:'mpv-plus'}},core:{info:()=>{}}});
 assert.equal(update,undefined);
});
