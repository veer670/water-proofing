import { handler, body, readUsers, writeUsers, checkPw, hashPw, send } from '../lib/auth.js';
import crypto from 'node:crypto';
export default handler(async (req, res, me) => {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST' });
  const b = body(req);
  if (!checkPw(me, b.old || '')) return send(res, 400, { error: 'Current password is wrong.' });
  if (String(b.new || '').length < 6) return send(res, 400, { error: 'New password must have at least 6 characters.' });
  const users = await readUsers(), u = users.find(x => x.id === me.id);
  u.salt = crypto.randomBytes(16).toString('hex'); u.hash = hashPw(u.salt, b.new);
  await writeUsers(users);
  send(res, 200, { ok: true });
});
