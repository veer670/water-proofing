import { handler, readUsers, publicUser, send } from '../../lib/auth.js';
export default handler(async (req, res) => send(res, 200, { users: (await readUsers()).map(publicUser) }), { admin: true });
