import { listUsers } from '../services/userStore.js';

export async function getUsers(req, res) {
  try {
    const { role } = req.query || {};
    const users = await listUsers({ role: role ? String(role) : undefined });
    return res.json({ users });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load users' });
  }
}
