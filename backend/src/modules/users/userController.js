import { listUsers, setUserApproved, setUserDailyLeadLimit, setUserRole } from './userStore.js';
import { clampDays, loadSalesmanStats } from './salesmanStats.js';
import { listContactedLeads, moveLeadBack } from './contactedLeads.js';

export async function getUsers(req, res) {
  try {
    const { role } = req.query || {};
    const users = await listUsers({ role: role ? String(role) : undefined });
    return res.json({ users });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load users' });
  }
}

/** GET /api/users/stats?days=14 — each salesman's contacts, per day and in total. */
export async function getSalesmanStats(req, res) {
  try {
    const stats = await loadSalesmanStats({ days: clampDays(req.query?.days) });
    return res.json(stats);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load salesman stats' });
  }
}

/** GET /api/users/:id/contacted-leads — the 1-star leads this salesman has contacted. */
export async function getSalesmanContactedLeads(req, res) {
  try {
    return res.json({ leads: await listContactedLeads(req.params.id) });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load contacted leads' });
  }
}

/** POST /api/users/:id/contacted-leads/:leadId/move-back — the admin puts the lead back in New. */
export async function moveContactedLeadBack(req, res) {
  try {
    return res.json(await moveLeadBack(req.params.id, req.params.leadId));
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to move the lead back' });
  }
}

export async function editUser(req, res) {
  try {
    const { approved, role, dailyLeadLimit } = req.body || {};
    console.log('[DEBUG dailyLeadLimit] PATCH /api/users/%s body=%j', req.params.id, req.body);
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
