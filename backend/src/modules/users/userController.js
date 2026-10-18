import { listUsers, setUserApproved, setUserDailyLeadLimit, setUserRole } from './userStore.js';

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
    const { approved, role, dailyLeadLimit } = req.body || {};
    let user;
    if (approved !== undefined) {
      user = await setUserApproved(req.params.id, approved);
    }
    if (role !== undefined) {
      user = await setUserRole(req.params.id, role);
    }
    if (dailyLeadLimit !== undefined) {
      user = await setUserDailyLeadLimit(req.params.id, dailyLeadLimit);
    }
    if (!user) {
      const existing = await listUsers();
      user = existing.find((u) => u.id === req.params.id);
    }
    return res.json({ user });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to update user' });
  }
}
