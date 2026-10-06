import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import handler from '../api/index.js';
const root=resolve('public'),types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8'};
http.createServer(async(req,res)=>{const url=new URL(req.url,'http://localhost');if(url.pathname.startsWith('/api/'))return handler(req,res);try{const path=resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname));if(!path.startsWith(root+sep)){res.writeHead(403);return res.end();}const bytes=await readFile(path);res.setHeader('Content-Type',types[extname(path)]||'application/octet-stream');res.end(bytes);}catch{res.writeHead(404);res.end('No encontrado');}}).listen(3000,'127.0.0.1',()=>console.log('Cafeteria Genesis: http://localhost:3000'));
