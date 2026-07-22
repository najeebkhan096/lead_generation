/**
 * In-memory session store. Data is lost when the server restarts.
 * No database — results live only for the current session.
 */

const store = {
  leads: [],
  lastSearch: null,
  status: 'idle', // idle | searching | done | error
  error: null,
  progress: {
    message: '',
    found: 0,
    processed: 0,
  },
};

export function getStore() {
  return store;
}

export function setLeads(leads) {
  store.leads = leads;
  store.status = 'done';
  store.error = null;
}

export function clearLeads() {
  store.leads = [];
  store.lastSearch = null;
  store.status = 'idle';
  store.error = null;
  store.progress = { message: '', found: 0, processed: 0 };
}

export function setStatus(status, error = null) {
  store.status = status;
  store.error = error;
}

export function setProgress(progress) {
  store.progress = { ...store.progress, ...progress };
}

export function setLastSearch(params) {
  store.lastSearch = params;
}
