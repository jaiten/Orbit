function confirmationNotice(raw){
 if(typeof raw!=='string'||raw.length>20000)return null;
 let url;try{url=new URL(raw);}catch{return null;}
 if(url.protocol!=='orbit:'||url.hostname!=='auth'||!['','/'].includes(url.pathname)||url.username||url.password)return null;
 const fragment=new URLSearchParams(url.hash.slice(1));
 if(fragment.has('error')||fragment.has('error_code')||url.searchParams.has('error')||url.searchParams.has('error_code'))return 'That confirmation link is invalid or expired. Request a fresh email in Settings and use the newest link.';
 // Never accept a sign-in session supplied through an external URL.
 return 'Your email link has returned to Orbit. Sign in with your email and password to start syncing.';
}
module.exports={confirmationNotice};
