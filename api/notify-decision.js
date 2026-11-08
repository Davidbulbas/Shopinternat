export default async function handler(req,res){
 if(req.method!=="POST")return res.status(405).json({error:"Method not allowed"});
 try{
 const token=(req.headers.authorization||"").match(/^Bearer (.+)$/)?.[1];
 const type=req.body?.type,id=Number(req.body?.id);
 if(!token||!["order","subscription"].includes(type)||!Number.isSafeInteger(id)||id<=0)return res.status(400).json({error:"Invalid request"});
 const base=process.env.SUPABASE_URL,key=process.env.SUPABASE_PUBLISHABLE_KEY,secret=process.env.RESEND_API_KEY;
 if(!base||!key||!secret)return res.status(503).json({error:"Email not configured"});
 const headers={apikey:key,Authorization:"Bearer "+token};
 const me=await fetch(base+"/auth/v1/user",{headers});if(!me.ok)return res.status(401).json({error:"Invalid session"});
 const user=await me.json();
 const admin=await fetch(base+"/rest/v1/profiles?id=eq."+encodeURIComponent(user.id)+"&select=is_admin",{headers});
 if(!admin.ok||(await admin.json())[0]?.is_admin!==true)return res.status(403).json({error:"Director only"});
 const table=type==="order"?"orders":"shop_subscriptions";
 const q=await fetch(base+"/rest/v1/"+table+"?id=eq."+id+"&select="+(type==="order"?"id,user_id,total,payment_status":"id,user_id,amount,status") ,{headers});
 if(!q.ok)return res.status(502).json({error:"Request lookup failed"});
 const row=(await q.json())[0];if(!row)return res.status(404).json({error:"Not found"});
 const state=type==="order"?row.payment_status:row.status;
 if(!["approved","rejected"].includes(state))return res.status(409).json({error:"Not reviewed"});
 const emails=await fetch(base+"/rest/v1/rpc/shop_admin_order_emails",{method:"POST",headers:{...headers,"Content-Type":"application/json"},body:"{}"});
 if(!emails.ok)return res.status(502).json({error:"Email lookup failed"});
 const recipient=(await emails.json()).find(x=>x.user_id===row.user_id)?.email;
 if(!recipient)return res.status(404).json({error:"Customer email unavailable"});
 const label=type==="order"?"comanda":"abonamentul",amount=Number(type==="order"?row.total:row.amount).toFixed(2);
 const approved=state==="approved";
 const body=(approved?"Plata a fost confirmată pentru ":"Cererea a fost respinsă pentru ")+label+" #"+id+".\nSumă: "+amount+" MDL.\n"+(approved?(type==="order"?"Directorul va pregăti comanda.":"Abonamentul a fost activat."): "Contactează directorul pentru detalii.");
 const response=await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:"Bearer "+secret,"Content-Type":"application/json","Idempotency-Key":"shop-decision-"+type+"-"+id+"-"+state},body:JSON.stringify({from:"ShopInternat <onboarding@resend.dev>",to:[recipient],subject:(approved?"✅ Aprobat: ":"❌ Respins: ")+label+" #"+id,text:body})});
 if(!response.ok){console.error("Decision email rejected",response.status);return res.status(502).json({error:"Email provider rejected message"})}
 return res.status(200).json({ok:true});
 }catch(e){console.error("Decision email error",e);return res.status(500).json({error:"Notification failed"})}
}