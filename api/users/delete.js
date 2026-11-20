import { handler, body, readUsers, writeUsers, send } from '../../lib/auth.js';
export default handler(async (req, res, me) => {
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST' });
  const id = String(body(req).id || '').trim().toLowerCase();
  if (id === me.id) return send(res, 400, { error: 'You cannot delete your own user.' });
  const users = await readUsers(), ex = users.find(u => u.id === id);
  if (!ex) return send(res, 404, { error: 'User not found.' });
  if (ex.role === 'admin' && users.filter(u => u.role === 'admin').length <= 1) return send(res, 400, { error: 'At least one admin is needed.' });
  await writeUsers(users.filter(u => u.id !== id));
  send(res, 200, { ok: true });
}, { admin: true });
