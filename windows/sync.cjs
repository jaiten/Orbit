class Sync {
 constructor(store,client,notify){Object.assign(this,{store,client,notify,busy:false,status:'Saved on this PC'});}
 async run(){if(this.busy||!this.client)return;this.busy=true;try{const {data:{session},error}=await this.client.auth.getSession();if(error)throw error;if(!session){this.status='Saved on this PC';return;}this.store.bind(session.user.id);this.status='Syncing…';this.notify();for(const row of this.store.rows().filter(r=>r.dirty&&!r.conflict)){const {data,error}=await this.client.rpc('orbit_put',{p_key:row.key,p_payload:row.payload,p_deleted:row.deleted,p_base:row.revision,p_mutation:row.mutation});if(error)throw error;if(data.accepted)this.store.accept(data.record,row);else this.store.accept(data.record);}
 // Full, key-ordered catch-up avoids timestamp/cursor gaps after reconnect.
 for(let offset=0;;offset+=500){const {data,error}=await this.client.from('orbit_records').select('*').order('key').range(offset,offset+499);if(error)throw error;for(const row of data)this.store.accept(row);if(data.length<500)break;}
 this.status=this.store.rows().some(r=>r.conflict)?'Changes need review':this.store.rows().some(r=>r.dirty)?'Changes waiting to sync':'All changes synced';
 }catch(e){this.status=`Saved locally · ${e.message}`;}finally{this.busy=false;this.notify();}}
}
module.exports={Sync};
