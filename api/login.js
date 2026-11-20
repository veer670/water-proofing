import { handler, body, readUsers, checkPw, makeToken, publicUser, send } from '../lib/auth.js';
export default handler(async (req, res) => {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST' });
  const b = body(req), id = String(b.id || '').trim().toLowerCase();
  const u = (await readUsers()).find(x => x.id === id);
  if (!checkPw(u, b.password || '')) { await new Promise(r => setTimeout(r, 400)); return send(res, 401, { error: 'User ID or password is wrong. Please try again.' }); }
  send(res, 200, { token: makeToken(u, b.remember === true ? 168 : 12), user: publicUser(u) });
}, { open: true });
