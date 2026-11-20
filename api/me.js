import { handler, publicUser, send } from '../lib/auth.js';
export default handler(async (req, res, me) => send(res, 200, { user: publicUser(me) }));
