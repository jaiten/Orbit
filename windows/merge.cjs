const {isDeepStrictEqual:equal}=require('node:util');
function visible(payload){return Object.fromEntries(Object.entries(payload||{}).filter(([k,v])=>!['id','updatedAt'].includes(k)&&v!==null&&v!==undefined&&v!==''&&!(Array.isArray(v)&&v.length===0)));}
function merge(local,remote,base){
 if(equal(visible(local),visible(remote)))return remote;
 if(!base)return null;
 const result={...remote};
 for(const key of new Set([...Object.keys(local),...Object.keys(remote),...Object.keys(base)])){
  if(['id','updatedAt'].includes(key))continue;
  const l=local[key]??null,r=remote[key]??null,b=base[key]??null;
  if(equal(l,r))continue;
  if(equal(l,b))continue;
  if(!equal(r,b))return null;
  if(key in local)result[key]=local[key];else delete result[key];
 }
 result.updatedAt=Math.max(local.updatedAt||0,remote.updatedAt||0);
 return result;
}
module.exports={merge};
