/* ShopInternat — pure discount quote calculator.
 * Staging helper only. The database must independently validate entitlements.
 * All amounts are integer bani (1 MDL = 100 bani) to avoid floating-point rounding.
 */
(function(root,factory){
 const api=factory();
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.ShopDiscountQuote=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
 'use strict';
 const validAmount=n=>Number.isSafeInteger(n)&&n>=0;
 function quote(subtotalBani,rewards=[],choice='auto'){
  if(!validAmount(subtotalBani))throw new TypeError('Subtotal invalid');
  if(!Array.isArray(rewards))throw new TypeError('Recompense invalide');
  const eligible=rewards.filter(r=>r&&r.status==='available'&&typeof r.id==='string'&&r.id.length>0&&validAmount(r.amountBani)&&r.amountBani>0);
  let selected=null;
  if(choice==='auto'){
   selected=eligible.slice().sort((a,b)=>Math.min(b.amountBani,subtotalBani)-Math.min(a.amountBani,subtotalBani)||b.amountBani-a.amountBani||a.id.localeCompare(b.id))[0]||null;
  }else if(choice==='none'){
   selected=null;
  }else{
   selected=eligible.find(r=>r.id===choice);
   if(!selected)throw new Error('Reducerea selectată nu mai este disponibilă');
  }
  if(subtotalBani===0)selected=null;
  const discountBani=selected?Math.min(selected.amountBani,subtotalBani):0;
  return {subtotalBani,discountBani,totalBani:subtotalBani-discountBani,rewardId:selected?.id||null,reason:selected?.reason||null};
 }
 function welcomeEligible(subtotalBani,previousOrders){
  if(!validAmount(subtotalBani)||!Number.isSafeInteger(previousOrders)||previousOrders<0)throw new TypeError('Date invalide');
  return subtotalBani>=5000&&previousOrders===0;
 }
 function loyaltyCredits(completedPaidOrders,alreadyGrantedCredits){
  if(!Number.isSafeInteger(completedPaidOrders)||completedPaidOrders<0||!Number.isSafeInteger(alreadyGrantedCredits)||alreadyGrantedCredits<0)throw new TypeError('Date invalide');
  return Math.max(0,Math.floor(completedPaidOrders/5)-alreadyGrantedCredits);
 }
 // A referral only qualifies after the invited user's first approved and delivered order.
 // This is a test-only eligibility rule; the database must enforce ownership and idempotency.
 function referralEligible({inviterId,inviteeId,firstOrder,delivered,paymentApproved,alreadyGranted}={}){
  return typeof inviterId==='string'&&inviterId.length>0&&typeof inviteeId==='string'&&inviteeId.length>0
   &&inviterId!==inviteeId&&firstOrder===true&&delivered===true
   &&paymentApproved===true&&alreadyGranted!==true;
 }
 function validReferralCode(code){
  return typeof code==='string'&&/^[A-Z0-9]{8,16}$/.test(code);
 }
 return Object.freeze({quote,welcomeEligible,loyaltyCredits,referralEligible,validReferralCode});
});
