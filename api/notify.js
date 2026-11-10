export default async function handler(req,res){
if(req.method!=="POST")return res.status(405).json({error:"Method not allowed"});
try{
 const token=(req.headers.authorization||"").match(/^Bearer (.+)$/)?.[1];
 if(!token)return res.status(401).json({error:"Authentication required"});
 const id=Number(req.body?.order_id);
 if(!Number.isSafeInteger(id)||id<=0)return res.status(400).json({error:"Invalid order"});
 const base=process.env.SUPABASE_URL,key=process.env.SUPABASE_PUBLISHABLE_KEY,secret=process.env.RESEND_API_KEY;
 if(!base||!key||!secret)return res.status(503).json({error:"Email configuration missing"});
 const headers={apikey:key,Authorization:"Bearer "+token};
 const u=await fetch(base+"/auth/v1/user",{headers});
 if(!u.ok)return res.status(401).json({error:"Invalid session"});
 const user=await u.json();
 const q=await fetch(base+"/rest/v1/orders?id=eq."+id+"&user_id=eq."+encodeURIComponent(user.id)+"&select=id,total,status,payment_method,created_at,order_items(product_name,quantity,unit_price)",{headers});
 if(!q.ok)return res.status(502).json({error:"Order lookup failed"});
 const orders=await q.json(),order=orders[0];
 if(!order)return res.status(403).json({error:"Order not found"});
 const p=await fetch(base+"/rest/v1/profiles?id=eq."+encodeURIComponent(user.id)+"&select=phone,room_number",{headers});
 const prof=p.ok?(await p.json())[0]||{}:{};
 const claim=await fetch(base+"/rest/v1/rpc/begin_shop_order_email",{method:"POST",headers:{...headers,"Content-Type":"application/json"},body:JSON.stringify({p_order_id:id})});
 if(!claim.ok)return res.status(502).json({error:"Could not register notification"});
 const claimToken=await claim.json();
 if(!claimToken)return res.status(200).json({ok:true,already_sent_or_sending:true});
 const finish=async(success)=>{
  const result=await fetch(base+"/rest/v1/rpc/finish_shop_order_email",{method:"POST",headers:{...headers,"Content-Type":"application/json"},body:JSON.stringify({p_order_id:id,p_token:claimToken,p_success:success})});
  if(!result.ok)throw Error("Notification completion failed");
  return await result.json()===true;
 };
 const items=(order.order_items||[]).map(i=>i.product_name+" × "+i.quantity+" ("+Number(i.unit_price).toFixed(2)+" MDL/buc)").join("\n");
 const method=order.payment_method==="cash"?"Cash / numerar":"MIA / transfer";
 const body="Cerere nouă de comandă ("+method+" de verificat) #"+id+"\nCamera: "+(prof.room_number||"Nespecificată")+"\nTelefon: "+(prof.phone||"Nespecificat")+"\nClient: "+(user.email||"")+"\n\nProduse:\n"+items+"\n\nTotal de verificat "+(order.payment_method==="cash"?"în numerar":"în maibank")+": "+Number(order.total).toFixed(2)+" MDL";
 const email=await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:"Bearer "+secret,"Content-Type":"application/json","Idempotency-Key":"shopinternat-order-"+id},body:JSON.stringify({from:"ShopInternat <onboarding@resend.dev>",to:["bulbasgmdavid@gmail.com"],subject:"🛒 Comandă nouă ShopInternat #"+id,text:body})});
 if(!email.ok){
  const error=await email.text();console.error("Resend rejected",email.status,error.slice(0,300));
  await finish(false);
  return res.status(502).json({error:"Email service rejected message"});
 }
 const completed=await finish(true);
 if(!completed)return res.status(502).json({error:"Notification confirmation failed"});
 return res.status(200).json({ok:true});
}catch(e){console.error("Notification error",e);return res.status(500).json({error:"Notification failed"})}
}