// Shared login / user-store logic for the Vercel API functions.
// Users are kept in a Vercel Blob store (connect one under Project -> Storage -> Blob).
import crypto from 'node:crypto';
import { get, put, list, del } from '@vercel/blob';

const PRIVATE_PATH = 'wp-auth/users.json';
const PUBLIC_PREFIX = 'wp-auth/users-';
const DEFAULT_ADMIN = { id: 'admin', name: 'Administrator', role: 'admin', password: 'Homeland@2026' };
let mode = null; // 'private' | 'public' (detected from the store type)

// A connected Blob store gives the project either BLOB_READ_WRITE_TOKEN or BLOB_STORE_ID (newer, OIDC-based)
export const hasStorage = () => !!(process.env.BLOB_READ_WRITE_TOKEN || process.env.BLOB_STORE_ID);
export const storageKind = () => process.env.BLOB_READ_WRITE_TOKEN ? 'token' : (process.env.BLOB_STORE_ID ? 'store-id' : 'none');

// Secret used to sign login tokens: AUTH_SECRET if set, otherwise a random one kept inside the Blob store
let SECRET = null;
async function secret() {
  if (SECRET) return SECRET;
  if (process.env.AUTH_SECRET) return (SECRET = process.env.AUTH_SECRET);
  await readUsers(); // makes sure the store mode is known
  if (mode === 'private') {
    const r = await get('wp-auth/secret.txt', { access: 'private', useCache: false });
    if (r) SECRET = (await new Response(r.stream).text()).trim();
    if (!SECRET) { SECRET = crypto.randomBytes(32).toString('hex'); await put('wp-auth/secret.txt', SECRET, { access: 'private', allowOverwrite: true, addRandomSuffix: false, contentType: 'text/plain' }); }
  } else {
    const { blobs } = await list({ prefix: 'wp-auth/secret-' });
    if (blobs.length) { const r = await fetch(blobs[0].url, { cache: 'no-store' }); if (r.ok) SECRET = (await r.text()).trim(); }
    if (!SECRET) { SECRET = crypto.randomBytes(32).toString('hex'); await put('wp-auth/secret-.txt', SECRET, { access: 'public', addRandomSuffix: true, contentType: 'text/plain' }); }
  }
  return SECRET;
}

export function hashPw(salt, pw) { return crypto.scryptSync(String(pw), salt, 32).toString('hex'); }
export function makeUser(id, name, role, pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  return { id, name, role, salt, hash: hashPw(salt, pw), created: new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Kolkata' }).slice(0, 16) };
}
export function checkPw(u, pw) {
  if (!u || !u.salt || !u.hash) return false;
  const a = Buffer.from(hashPw(u.salt, pw), 'hex'), b = Buffer.from(u.hash, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
export const publicUser = u => ({ id: u.id, name: u.name, role: u.role, created: u.created || '' });

async function readPrivate() {
  const r = await get(PRIVATE_PATH, { access: 'private', useCache: false });
  if (!r) return null;
  return JSON.parse(await new Response(r.stream).text());
}
async function readPublic() {
  const { blobs } = await list({ prefix: PUBLIC_PREFIX });
  if (!blobs.length) return null;
  blobs.sort((a, b) => new Date(b.uploadedAt) - new Date(a.uploadedAt));
  const r = await fetch(blobs[0].url + '?v=' + Date.now(), { cache: 'no-store' });
  return r.ok ? r.json() : null;
}
export async function readUsers() {
  let data = null;
  if (mode !== 'public') {
    try { data = await readPrivate(); mode = 'private'; }
    catch (e) { mode = 'public'; }
  }
  if (mode === 'public') data = await readPublic();
  if (!Array.isArray(data) || !data.length) {
    data = [makeUser(DEFAULT_ADMIN.id, DEFAULT_ADMIN.name, DEFAULT_ADMIN.role, DEFAULT_ADMIN.password)];
    await writeUsers(data);
  }
  return data;
}
export async function writeUsers(users) {
  const body = JSON.stringify(users, null, 1);
  if (mode !== 'public') {
    try { await put(PRIVATE_PATH, body, { access: 'private', allowOverwrite: true, addRandomSuffix: false, contentType: 'application/json' }); mode = 'private'; return; }
    catch (e) { if (mode === 'private') throw e; mode = 'public'; }
  }
  const { blobs } = await list({ prefix: PUBLIC_PREFIX });
  await put(PUBLIC_PREFIX + '.json', body, { access: 'public', addRandomSuffix: true, contentType: 'application/json', cacheControlMaxAge: 60 });
  if (blobs.length) await del(blobs.map(b => b.url));
}

const b64u = s => Buffer.from(s).toString('base64url');
const sign = async p => crypto.createHmac('sha256', await secret()).update(p).digest('base64url');
export async function makeToken(u, hours) { const p = b64u(u.id + '|' + (Math.floor(Date.now() / 1000) + hours * 3600)); return p + '.' + (await sign(p)); }
export async function tokenUser(req) {
  const h = req.headers.authorization || '';
  if (!h.startsWith('Bearer ')) return null;
  const [p, s] = h.slice(7).split('.');
  if (!p || !s || (await sign(p)) !== s) return null;
  const [id, exp] = Buffer.from(p, 'base64url').toString().split('|');
  if (!id || Number(exp) < Date.now() / 1000) return null;
  return (await readUsers()).find(u => u.id === id) || null;
}

export function body(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  try { return JSON.parse(req.body || '{}'); } catch (e) { return {}; }
}
export function send(res, code, obj) { res.setHeader('Cache-Control', 'no-store'); res.status(code).json(obj); }
export function needStorage(res) {
  if (hasStorage()) return false;
  send(res, 503, { error: 'User storage is not connected. In Vercel open Storage -> your Blob store -> Projects -> Connect Project, then redeploy.' });
  return true;
}
// Wraps a handler: storage check, auth (unless open), admin check, error handling
export function handler(fn, { open = false, admin = false } = {}) {
  return async (req, res) => {
    try {
      if (needStorage(res)) return;
      let me = null;
      if (!open) {
        me = await tokenUser(req);
        if (!me) return send(res, 401, { error: 'Please sign in again.' });
        if (admin && me.role !== 'admin') return send(res, 403, { error: 'Only an admin can manage users.' });
      }
      await fn(req, res, me);
    } catch (e) {
      send(res, 500, { error: 'Server error: ' + (e && e.message ? e.message : e) });
    }
  };
}
