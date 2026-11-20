import crypto from 'node:crypto';
import { handler, body, readUsers, writeUsers, makeUser, hashPw, send } from '../../lib/auth.js';
export default handler(async (req, res) => {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST' });
  const b = body(req);
  const id = String(b.id || '').trim().toLowerCase(), name = String(b.name || '').trim() || id, pw = String(b.password || '');
  const role = b.role === 'admin' ? 'admin' : 'viewer';
  if (!/^[a-z0-9._-]{2,30}$/.test(id)) return send(res, 400, { error: 'User ID must be 2 to 30 characters: letters, numbers, dot, dash or underscore (no spaces).' });
  const users = await readUsers(), ex = users.find(u => u.id === id);
  if (b.isNew === true) {
    if (ex) return send(res, 409, { error: 'This user ID already exists.' });
    if (pw.length < 6) return send(res, 400, { error: 'Password must have at least 6 characters.' });
    users.push(makeUser(id, name, role, pw));
  } else {
    if (!ex) return send(res, 404, { error: 'User not found.' });
    if (ex.role === 'admin' && role !== 'admin' && users.filter(u => u.role === 'admin').length <= 1) return send(res, 400, { error: 'At least one admin is needed.' });
    ex.name = name; ex.role = role;
    if (pw) {
      if (pw.length < 6) return send(res, 400, { error: 'Password must have at least 6 characters.' });
      ex.salt = crypto.randomBytes(16).toString('hex'); ex.hash = hashPw(ex.salt, pw);
    }
  }
  await writeUsers(users);
  send(res, 200, { ok: true });
}, { admin: true });
