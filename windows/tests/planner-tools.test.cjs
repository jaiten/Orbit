const {test}=require('node:test');const assert=require('node:assert/strict');
const {Store}=require('../store.cjs');const {PlannerTools,encodeBackup,decodeBackup}=require('../planner-tools.cjs');
const id='11111111-1111-4111-8111-111111111111';
test('undo restores a deletion without rewinding the server revision',()=>{
 const s=new Store(':memory:'),t=new PlannerTools(s);try{
  t.change([{key:'tasks/'+id,payload:{id,title:'Read'}}]);t.change([{key:'tasks/'+id,payload:{id,title:'Read'},deleted:true}]);t.undo();
  assert.equal(s.rows()[0].deleted,false);assert.equal(s.rows()[0].payload.title,'Read');assert.equal(s.rows()[0].dirty,1);
 }finally{s.close();}
});
test('undo refuses to replace a changed synced record',()=>{
 const s=new Store(':memory:'),t=new PlannerTools(s);try{
  t.change([{key:'tasks/'+id,payload:{id,title:'Read'}}]);s.put('tasks/'+id,{id,title:'Different device'});
  assert.throws(()=>t.undo(),/changed on another device/);assert.equal(s.rows()[0].payload.title,'Different device');
 }finally{s.close();}
});
test('backup excludes auth and sync metadata and validates all records before restore',()=>{
 const text=encodeBackup([{key:'lists/'+id,payload:{id,name:'Work'},deleted:false,revision:5,mutation:'private'},{key:'tasks/'+id,payload:{id,title:'Deleted'},deleted:true}]);
 const records=decodeBackup(text);assert.equal(records.length,1);assert.equal(records[0].key,'lists/'+id);assert.ok(!text.includes('private'));
 assert.throws(()=>decodeBackup(JSON.stringify({format:'orbit-backup',version:1,records:[...records,...records]})),/Invalid/);
 assert.throws(()=>decodeBackup(JSON.stringify({format:'orbit-backup',version:1,records:[{key:'owner',payload:{id,title:'Bad'}}]})),/Invalid/);
});
