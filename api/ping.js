import { hasStorage, send } from '../lib/auth.js';
export default function ping(req, res) { send(res, 200, { ok: true, storage: hasStorage(), host: 'vercel' }); }
