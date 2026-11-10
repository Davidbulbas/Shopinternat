const assert=require('node:assert/strict');
const {quote,welcomeEligible,loyaltyCredits}=require('./discount-quote');
const rewards=[
 {id:'invite',status:'available',amountBani:500,reason:'Invită un prieten'},
 {id:'loyal',status:'available',amountBani:1000,reason:'Client fidel'}
];
assert.deepEqual(quote(7500,rewards),{subtotalBani:7500,discountBani:1000,totalBani:6500,rewardId:'loyal',reason:'Client fidel'});
assert.equal(quote(7500,rewards,'invite').totalBani,7000);
assert.equal(quote(7500,rewards,'none').totalBani,7500);
assert.equal(quote(300,rewards).totalBani,0);
assert.equal(quote(0,rewards).rewardId,null);
assert.equal(quote(7500,[{...rewards[1],status:'reserved'}]).rewardId,null);
assert.throws(()=>quote(100,rewards,'missing'),/disponibilă/);
assert.throws(()=>quote(-1,rewards),/invalid/);
assert.equal(welcomeEligible(5000,0),true);
assert.equal(welcomeEligible(4999,0),false);
assert.equal(welcomeEligible(5000,1),false);
assert.equal(loyaltyCredits(4,0),0);
assert.equal(loyaltyCredits(5,0),1);
assert.equal(loyaltyCredits(11,1),1);
assert.equal(loyaltyCredits(10,2),0);
console.log('15 verificări reduceri: OK');
