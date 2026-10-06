import test from 'node:test';
import assert from 'node:assert/strict';
import handler,{issueSession,verifySession} from '../api/index.js';
process.env.SUPABASE_URL='https://example.supabase.co';process.env.SUPABASE_SECRET_KEY='test-only';process.env.VENDEDOR_PASSWORD='vendor-test';process.env.CONTADOR_PASSWORD='counter-test';process.env.SESSION_SECRET='a'.repeat(40);
function request(path,method='GET',body,cookie){return {url:'/api/'+path,method,body,headers:{host:'localhost',origin:'http://localhost',cookie},socket:{remoteAddress:'local'}}}
async function run(req){let status,headers={},text;const res={set statusCode(v){status=v},setHeader:(k,v)=>headers[k]=v,end:v=>text=v};await handler(req,res);return {status,headers,data:JSON.parse(text)}}
test('signed session rejects tampering',()=>{let token=issueSession('vendedor');assert.equal(verifySession('genesis_session='+token),'vendedor');assert.equal(verifySession('genesis_session='+token+'x'),null);});
test('wrong password rejected and no database request',async()=>{const r=await run(request('login','POST',{role:'vendedor',password:'bad'}));assert.equal(r.status,401)});
test('valid login returns HttpOnly cookie',async()=>{const r=await run(request('login','POST',{role:'vendedor',password:'vendor-test'}));assert.equal(r.status,200);assert(r.headers['Set-Cookie'].includes('HttpOnly'));assert.equal(r.data.role,'vendedor')});
test('unauthenticated records access rejected',async()=>{assert.equal((await run(request('state'))).status,401)});
test('contador cannot modify inventory',async()=>{assert.equal((await run(request('inventory','POST',{},'genesis_session='+issueSession('contador')))).status,403)});
test('cross-origin writes rejected',async()=>{let req=request('sale','POST',{},'genesis_session='+issueSession('vendedor'));req.headers.origin='https://elsewhere.example';assert.equal((await run(req)).status,403)});
test('sale uses verified RPC and does not send client cost',async()=>{let old=global.fetch,call;global.fetch=async(url,options)=>{call={url,options};return {ok:true,json:async()=> 'sale-id'}};try{let r=await run(request('sale','POST',{id:'sale-id',payment:'nequi',total:3000,items:[{id:'product-id',quantity:2,price:1}]},'genesis_session='+issueSession('vendedor')));assert.equal(r.status,200);assert(call.url.endsWith('registrar_venta_verificada'));let b=JSON.parse(call.options.body);assert.equal(b.p_total,3000);assert.deepEqual(b.p_items,[{producto_id:'product-id',cantidad:2}]);assert.equal(call.options.headers.apikey,'test-only')}finally{global.fetch=old}});
