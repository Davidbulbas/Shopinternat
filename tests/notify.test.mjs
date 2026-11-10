import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../api/notify.js', import.meta.url), 'utf8');
const { default: handler } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));

function response(value, status=200) {
  return { ok:status>=200&&status<300, status, json:async()=>value, text:async()=>JSON.stringify(value) };
}
async function runScenario(sendSucceeds) {
  const oldFetch=globalThis.fetch;
  const oldEnv={SUPABASE_URL:process.env.SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY:process.env.SUPABASE_PUBLISHABLE_KEY,RESEND_API_KEY:process.env.RESEND_API_KEY};
  const calls=[];
  process.env.SUPABASE_URL='https://example.supabase.co';
  process.env.SUPABASE_PUBLISHABLE_KEY='test-public';
  process.env.RESEND_API_KEY='test-secret';
  globalThis.fetch=async(url,opts={})=>{
    calls.push({url,opts});
    if(url.endsWith('/auth/v1/user')) return response({id:'test-user',email:'test@example.com'});
    if(url.includes('/rest/v1/orders?')) return response([{id:42,total:91,payment_method:'mia',order_items:[{product_name:'Produs',quantity:2,unit_price:48}]}]);
    if(url.includes('/rest/v1/profiles?')) return response([{phone:'000',room_number:'1'}]);
    if(url.endsWith('/rpc/begin_shop_order_email')) return response('123e4567-e89b-12d3-a456-426614174000');
    if(url.endsWith('/rpc/finish_shop_order_email')) return response(true);
    if(url==='https://api.resend.com/emails') return response(sendSucceeds?{id:'email-id'}:{error:'temporary'},sendSucceeds?200:503);
    throw new Error('Unexpected request: '+url);
  };
  let status,body;
  const res={status(code){status=code;return this;},json(value){body=value;return this;}};
  try {
    await handler({method:'POST',headers:{authorization:'Bearer test'},body:{order_id:42}},res);
    return {status,body,calls};
  } finally {
    globalThis.fetch=oldFetch;
    for(const [k,v] of Object.entries(oldEnv)) if(v===undefined)delete process.env[k];else process.env[k]=v;
  }
}
test('successful email is finalized after Resend accepts it',async()=>{
 const {status,body,calls}=await runScenario(true);
 assert.equal(status,200);assert.equal(body.ok,true);
 const begin=calls.find(c=>c.url.endsWith('/rpc/begin_shop_order_email'));
 const finish=calls.find(c=>c.url.endsWith('/rpc/finish_shop_order_email'));
 const send=calls.find(c=>c.url==='https://api.resend.com/emails');
 assert.ok(begin&&finish&&send);
 assert.ok(calls.indexOf(begin)<calls.indexOf(send));
 assert.ok(calls.indexOf(send)<calls.indexOf(finish));
 assert.equal(JSON.parse(finish.opts.body).p_success,true);
 assert.equal(send.opts.headers['Idempotency-Key'],'shopinternat-order-42');
});
test('failed email is released for retry',async()=>{
 const {status,calls}=await runScenario(false);
 assert.equal(status,502);
 const finish=calls.find(c=>c.url.endsWith('/rpc/finish_shop_order_email'));
 assert.ok(finish);
 assert.equal(JSON.parse(finish.opts.body).p_success,false);
});
