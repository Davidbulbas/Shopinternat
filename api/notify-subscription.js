export default async function handler(req,res){
 if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
 try{
  const token=(req.headers.authorization||'').match(/^Bearer (.+)$/)?.[1];
  if(!token)return res.status(401).json({error:'Authentication required'});
  const base=process.env.SUPABASE_URL,key=process.env.SUPABASE_PUBLISHABLE_KEY,secret=process.env.RESEND_API_KEY;
  if(!base||!key||!secret)return res.status(503).json({error:'Email configuration missing'});
  const headers={apikey:key,Authorization:'Bearer '+token};
  const u=await fetch(base+'/auth/v1/user',{headers});
  if(!u.ok)return res.status(401).json({error:'Invalid session'});
  const user=await u.json();
  const q=await fetch(base+'/rest/v1/shop_subscriptions?user_id=eq.'+encodeURIComponent(user.id)+'&status=eq.pending&select=id,amount,requested_at&order=requested_at.desc&limit=1',{headers});
  if(!q.ok)return res.status(502).json({error:'Subscription lookup failed'});
  const subscription=(await q.json())[0];
  if(!subscription)return res.status(404).json({error:'No pending request'});
  const age=Date.now()-new Date(subscription.requested_at).getTime();
  if(!Number.isFinite(age)||age<0||age>10*60*1000)return res.status(400).json({error:'Request is not recent'});
  const p=await fetch(base+'/rest/v1/profiles?id=eq.'+encodeURIComponent(user.id)+'&select=full_name,room_number,phone',{headers});
  const profile=p.ok?(await p.json())[0]||{}:{};
  const body='Cerere nouă de abonament #'+subscription.id+'\nNume: '+(profile.full_name||'Nespecificat')+'\nCamera: '+(profile.room_number||'Nespecificată')+'\nTelefon: '+(profile.phone||'Nespecificat')+'\nEmail: '+(user.email||'')+'\nSumă declarată: '+Number(subscription.amount).toFixed(2)+' MDL\nData: '+new Date(subscription.requested_at).toLocaleString('ro-RO',{timeZone:'Europe/Chisinau'})+'\n\nVerifică plata MIA în maibank înainte de aprobare.';
  const email=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json','Idempotency-Key':'shop-subscription-'+subscription.id},body:JSON.stringify({from:'ShopInternat <onboarding@resend.dev>',to:['bulbasgmdavid@gmail.com'],subject:'💳 Cerere nouă de abonament ShopInternat #'+subscription.id,text:body})});
  if(!email.ok){console.error('Subscription email failed',email.status);return res.status(502).json({error:'Email service rejected message'})}
  return res.status(200).json({ok:true});
 }catch(e){console.error('Subscription notification error',e);return res.status(500).json({error:'Notification failed'})}
}