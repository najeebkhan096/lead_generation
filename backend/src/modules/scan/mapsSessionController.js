import { getSessionSnapshot, startLogin } from '../../scraper/mapsSessionManager.js';

/** GET /api/maps-session/status[?refresh=1] */
export async function getStatus(req, res) {
  try {
    const snapshot = await getSessionSnapshot({ refresh: req.query?.refresh === '1' });
    return res.json({ ...snapshot, ready: snapshot.status === 'signed_in' || (snapshot.inUseByScan && snapshot.status !== 'signed_out') });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to check the Google session' });
  }
}

/** POST /api/maps-session/login — opens the sign-in window on the backend computer. */
export async function login(_req, res) {
  try {
    const result = await startLogin();
    return res.status(202).json({
      ...result,
      message: 'A Google window opened on the computer running the backend. Sign in there, then close the window.',
    });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to open the sign-in window' });
  }
}
