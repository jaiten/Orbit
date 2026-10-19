const {_electron:electron}=require('playwright');
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');
(async()=>{
 const folder=fs.mkdtempSync(path.join(os.tmpdir(),'orbit-ui-'));
 const options={executablePath:require('electron'),args:[path.resolve(__dirname,'..')],env:{...process.env,ORBIT_TEST_DATA:folder}};
 let app;
 try{
  app=await electron.launch(options);const p=await app.firstWindow();const errors=[];p.on('pageerror',e=>errors.push(e.message));
  await p.getByRole('heading',{name:'Today',exact:true}).waitFor();
  await p.getByRole('textbox',{name:'Add an intention'}).fill('Read for twenty minutes');
  await p.getByRole('button',{name:'Add',exact:true}).click();
  await p.getByRole('button',{name:'Read for twenty minutes',exact:true}).click();
  await p.getByLabel('Notes').fill('A small, clear commitment');await p.getByRole('button',{name:'Save task',exact:true}).click();
  await p.getByRole('button',{name:'+ Habit',exact:true}).click();await p.locator('#habit-form input[name=title]').fill('Morning walk');
  await p.getByRole('button',{name:'Save habit',exact:true}).click();await p.getByRole('button',{name:'Log Morning walk',exact:true}).click();
  await p.getByText('1 / 1 today',{exact:true}).waitFor();await p.getByRole('button',{name:'Undo',exact:true}).click();await p.getByText('0 / 1 today',{exact:true}).waitFor();
  await p.getByRole('checkbox',{name:'Complete Read for twenty minutes'}).click();await p.getByText('1 completed',{exact:true}).waitFor();
  await p.getByRole('button',{name:'Settings & sync',exact:true}).click();await p.getByRole('heading',{name:'Connected, quietly'}).waitFor();
  await p.locator('[data-page="today"]').click();
  await p.screenshot({path:path.resolve(__dirname,'../assets/desktop-preview.png'),fullPage:true});
  if(errors.length)throw Error(errors.join('\n'));await app.close();app=await electron.launch(options);const q=await app.firstWindow();await q.getByText('1 completed',{exact:true}).waitFor();await q.getByText('0 / 1 today',{exact:true}).waitFor();
  console.log('PASS: native desktop create, edit, completion, habit log/undo, settings and offline restart');
 }finally{if(app)await app.close();fs.rmSync(folder,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1;});
