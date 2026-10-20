const {app,BrowserWindow,ipcMain,safeStorage,session,protocol,net}=require('electron');
const {confirmationNotice}=require('./auth-links.cjs');
const path=require('node:path');const fs=require('node:fs');const {pathToFileURL}=require('node:url');const {Store}=require('./store.cjs');const {Sync}=require('./sync.cjs');const {createClient}=require('@supabase/supabase-js');const config=require('./config.json');
protocol.registerSchemesAsPrivileged([{scheme:'orbit',privileges:{standard:true,secure:true,supportFetchAPI:true}}]);
if(process.env.ORBIT_TEST_DATA)app.setPath('userData',process.env.ORBIT_TEST_DATA);
let window,store,sync,client,accountNotice;
const handleConfirmation=raw=>{const notice=confirmationNotice(raw);if(!notice)return;accountNotice=notice;if(window){if(window.isMinimized())window.restore();window.show();window.focus();window.webContents.send('changed');}};
if(!app.requestSingleInstanceLock())app.quit();
else {
 app.on('second-instance',(_,argv)=>{for(const arg of argv)handleConfirmation(arg);if(window){if(window.isMinimized())window.restore();window.show();window.focus();}});
 app.on('open-url',(event,url)=>{event.preventDefault();handleConfirmation(url);});
}
for(const arg of process.argv)handleConfirmation(arg);
app.whenReady().then(async()=>{
if(app.isPackaged&&!process.env.ORBIT_TEST_DATA)app.setAsDefaultProtocolClient('orbit',process.env.PORTABLE_EXECUTABLE_FILE||process.execPath);
store=new Store(path.join(app.getPath('userData'),'orbit.sqlite'));const notify=(kind='data')=>{if(kind==='status')window?.webContents.send('sync-status',{status:sync.status,syncing:sync.busy});else window?.webContents.send('changed');};
const tokenPath=path.join(app.getPath('userData'),'session.enc');
const storage={getItem:()=>fs.existsSync(tokenPath)?safeStorage.decryptString(fs.readFileSync(tokenPath)):null,setItem:(_,v)=>{if(!safeStorage.isEncryptionAvailable())throw Error('Windows credential encryption is unavailable');fs.writeFileSync(tokenPath+'.tmp',safeStorage.encryptString(v));fs.renameSync(tokenPath+'.tmp',tokenPath);},removeItem:()=>{if(fs.existsSync(tokenPath))fs.unlinkSync(tokenPath);}};
if(config.url&&config.publishableKey)client=createClient(config.url,config.publishableKey,{auth:{storage,autoRefreshToken:true,persistSession:true,detectSessionInUrl:false}});
sync=new Sync(store,client,notify);
protocol.handle('orbit',request=>{const url=new URL(request.url);const files={'/':'index.html','/index.html':'index.html','/app.js':'app.js','/today.js':'today.js','/planning.js':'planning.js','/conversions.js':'conversions.js','/styles.css':'styles.css','/mockup-theme.css':'mockup-theme.css','/logo.svg':'logo.svg'};if(url.host!=='app'||!files[url.pathname])return new Response('Not found',{status:404});return net.fetch(pathToFileURL(path.join(__dirname,'ui',files[url.pathname])).href);});
session.defaultSession.setPermissionRequestHandler((_,__,callback)=>callback(false));
window=new BrowserWindow({width:1240,height:860,minWidth:820,minHeight:620,title:'Orbit',backgroundColor:'#f8f7f5',icon:path.join(__dirname,'assets','orbit.png'),autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
window.webContents.setWindowOpenHandler(()=>({action:'deny'}));window.webContents.on('will-navigate',e=>e.preventDefault());
const handle=(name,fn)=>ipcMain.handle(name,async(event,arg)=>{if(event.senderFrame!==window.webContents.mainFrame||!event.senderFrame.url.startsWith('orbit://app/'))throw Error('Invalid sender');return fn(arg);});
handle('read',async()=>{const notice=accountNotice;accountNotice=null;return {records:store.rows(),accountNotice:notice,status:sync.status,syncing:sync.busy,configured:!!client,email:(await client?.auth.getSession())?.data?.session?.user?.email??null};});
handle('put',({key,payload,deleted})=>{store.put(key,payload,deleted===true);notify();void sync.run();});
handle('batch',changes=>{store.batch(changes);notify();void sync.run();});handle('sync',()=>sync.run());handle('resolve',({key,choice})=>{store.resolve(key,choice);return sync.run();});
handle('auth',async({mode,email,password})=>{
 if(!client)throw Error('Sync backend is not configured yet');
 if(mode==='out'){await client.auth.signOut({scope:'local'});sync.status='Saved on this PC';notify();return;}
 if(!['in','up','resend','verify'].includes(mode)||typeof email!=='string'||(mode!=='resend'&&typeof password!=='string'))throw Error('Invalid sign-in request');
 email=email.trim();
 if(mode==='resend'){const {error}=await client.auth.resend({type:'signup',email,options:{emailRedirectTo:'orbit://auth'}});if(error)throw error;return 'If this account needs confirmation, a fresh confirmation email is on its way.';}
 const result=await (mode==='verify'?client.auth.verifyOtp({email,token:password.trim(),type:'email'}):mode==='up'?client.auth.signUp({email,password,options:{emailRedirectTo:'orbit://auth'}}):client.auth.signInWithPassword({email,password}));
 if(result.error)throw result.error;
 if(result.data.session){accountNotice=null;try{store.bind(result.data.user.id);}catch(e){await client.auth.signOut({scope:'local'});throw e;}await sync.run();}
 return result.data.session?'Signed in':'Open the newest confirmation email, tap its link, then sign in here.';
});
await window.loadURL('orbit://app');window.on('focus',()=>void sync.run());setInterval(()=>void sync.run(),20000).unref();
if(client){client.channel('planner').on('postgres_changes',{event:'*',schema:'public',table:'orbit_records'},()=>void sync.run()).subscribe(status=>{if(status==='SUBSCRIBED')void sync.run();});void sync.run();}
});
app.on('window-all-closed',()=>app.quit());app.on('before-quit',()=>store?.close());
