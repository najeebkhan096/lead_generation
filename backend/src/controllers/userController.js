import { listUsers, setUserApproved } from '../services/userStore.js';

export async function getUsers(req, res) {
  try {
    const { role } = req.query || {};
    const users = await listUsers({ role: role ? String(role) : undefined });
    return res.json({ users });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load users' });
  }
}

export async function editUser(req, res) {
  try {
    const user = await setUserApproved(req.params.id, req.body?.approved);
    return res.json({ user });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to update user' });
  }
}
