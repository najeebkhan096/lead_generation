// Run with: cd scripts/rules-test && npm i && npm test   (needs Java for the emulators)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where, serverTimestamp, deleteField } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-rules-test',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
    storage: { rules: fs.readFileSync('storage.rules', 'utf8'), host: '127.0.0.1', port: 9199 },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const u of ['alice', 'bob']) await setDoc(doc(db, 'users', u), { approved: true });
    await setDoc(doc(db, 'users', 'eve'), { approved: false });
    await setDoc(doc(db, 'outreachLeads', 'alice_971501234567'), { ownerId: 'alice', name: 'A', phoneNumber: '+971501234567', unreadCount: 3 });
    await setDoc(doc(db, 'outreachConversations', 'alice_971501234567'), { ownerId: 'alice' });
    await setDoc(doc(db, 'outreachConversations/alice_971501234567/messages/m1'), { body: 'hi', status: 'sent', ownerless: true });
    await setDoc(doc(db, 'whatsappLeads', 'w1'), { business: 'Verified Cafe', phone: '+15125550001', sourceType: 'review' });
    await setDoc(doc(db, 'emailLeads', 'e1'), { business: 'Verified Cafe', email: 'info@cafe.example', sourceType: 'website' });
  });
});
after(() => env?.cleanup());

const L = 'outreachLeads/alice_971501234567';
const M = 'outreachConversations/alice_971501234567/messages/m1';

test('owner reads own lead/conversation/messages; others cannot', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  await assertSucceeds(getDoc(doc(alice, L)));
  await assertSucceeds(getDoc(doc(alice, M)));
  await assertFails(getDoc(doc(bob, L)));
  await assertFails(getDoc(doc(bob, M)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), L)));
});

test('list query is limited to own leads', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  await assertSucceeds(getDocs(query(collection(alice, 'outreachLeads'), where('ownerId', '==', 'alice'))));
  await assertFails(getDocs(query(collection(bob, 'outreachLeads'), where('ownerId', '==', 'alice'))));
});

test('unapproved accounts get nothing', async () => {
  const eve = env.authenticatedContext('eve').firestore();
  await assertFails(getDoc(doc(eve, L)));
});

test('clients cannot create leads, messages or conversations', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertFails(setDoc(doc(alice, 'outreachLeads/alice_971500000000'), { ownerId: 'alice', name: 'x', phoneNumber: '+971500000000', unreadCount: 0 }));
  await assertFails(setDoc(doc(alice, 'outreachConversations/alice_971501234567/messages/m2'), { body: 'forged', direction: 'outbound' }));
  await assertFails(setDoc(doc(alice, 'outreachConversations/x'), { ownerId: 'alice' }));
});

test('lead updates: rename + clear unread ok; message summary / owner / unread>0 rejected', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertSucceeds(updateDoc(doc(alice, L), { unreadCount: 0 }));
  await assertSucceeds(updateDoc(doc(alice, L), { name: 'New', unreadCount: 0 }));
  await assertFails(updateDoc(doc(alice, L), { unreadCount: 5 }));
  await assertFails(updateDoc(doc(alice, L), { ownerId: 'bob', unreadCount: 0 }));
  await assertFails(updateDoc(doc(alice, L), { lastMessage: 'spoof', unreadCount: 0 }));
  await assertFails(updateDoc(doc(env.authenticatedContext('bob').firestore(), L), { unreadCount: 0 }));
  await assertFails(deleteDoc(doc(alice, L)));
});

test('messages: only deletedAt may be changed by the owner; no status forging', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertFails(updateDoc(doc(alice, M), { status: 'read' }));
  await assertFails(updateDoc(doc(alice, M), { reactions: { alice: '👍' } })); // reactions go through the backend
  await assertSucceeds(updateDoc(doc(alice, M), { deletedAt: new Date() }));
  await assertFails(updateDoc(doc(env.authenticatedContext('bob').firestore(), M), { deletedAt: new Date() }));
  await assertFails(deleteDoc(doc(alice, M)));
});

const png = new Uint8Array([1, 2, 3, 4]);
const P = (uid, f = 'a.png') => `outreach_media/${uid}/conv1/msg1/${f}`;

// Verified leads (validator output): approved salespeople read, nobody writes.
for (const name of ['whatsappLeads', 'emailLeads']) {
  const id = name === 'whatsappLeads' ? 'w1' : 'e1';

  test(`${name}: approved users read; unapproved and signed-out cannot`, async () => {
    await assertSucceeds(getDoc(doc(env.authenticatedContext('alice').firestore(), `${name}/${id}`)));
    await assertSucceeds(getDocs(collection(env.authenticatedContext('alice').firestore(), name)));
    await assertFails(getDoc(doc(env.authenticatedContext('eve').firestore(), `${name}/${id}`)));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `${name}/${id}`)));
  });

  test(`${name}: clients can never create or delete, nor change contact details`, async () => {
    const alice = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, `${name}/forged`), { business: 'x', phone: '+1' }));
    await assertFails(updateDoc(doc(alice, `${name}/${id}`), { business: 'renamed' }));
    await assertFails(updateDoc(doc(alice, `${name}/${id}`), { phone: '+19990000000' }));
    await assertFails(deleteDoc(doc(alice, `${name}/${id}`)));
  });

  test(`${name}: an approved user can mark a lead contacted and move it back, nothing more`, async () => {
    const alice = env.authenticatedContext('alice').firestore();
    const eve = env.authenticatedContext('eve').firestore();
    const ref = (db) => doc(db, `${name}/${id}`);

    // Contacted: status + timestamp + their own uid.
    await assertSucceeds(updateDoc(ref(alice), { status: 'contacted', contactedAt: serverTimestamp(), contactedBy: 'alice' }));
    // Back to New: status reset and the contact fields removed.
    await assertSucceeds(updateDoc(ref(alice), { status: 'lead', contactedAt: deleteField(), contactedBy: deleteField() }));

    // Not someone else's name, not another status, not without a timestamp.
    await assertFails(updateDoc(ref(alice), { status: 'contacted', contactedAt: serverTimestamp(), contactedBy: 'bob' }));
    await assertFails(updateDoc(ref(alice), { status: 'dealDone', contactedAt: serverTimestamp(), contactedBy: 'alice' }));
    await assertFails(updateDoc(ref(alice), { status: 'contacted', contactedBy: 'alice' }));
    // Not riding extra fields along (updatedAt would reorder every list).
    await assertFails(updateDoc(ref(alice), { status: 'contacted', contactedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(alice), { status: 'contacted', contactedAt: serverTimestamp(), business: 'x' }));
    // Unapproved and signed-out accounts cannot.
    await assertFails(updateDoc(ref(eve), { status: 'contacted', contactedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(env.unauthenticatedContext().firestore()), { status: 'contacted', contactedAt: serverTimestamp() }));
  });
}

test('storage: owner uploads/reads own media, others cannot', async () => {
  const alice = env.authenticatedContext('alice').storage();
  const bob = env.authenticatedContext('bob').storage();
  await assertSucceeds(uploadBytes(ref(alice, P('alice')), png, { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(alice, P('alice'))));
  await assertFails(getBytes(ref(bob, P('alice'))));
  await assertFails(uploadBytes(ref(bob, P('alice', 'b.png')), png, { contentType: 'image/png' }));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), P('alice'))));
});

test('storage: rejects disallowed types, zip, oversize, overwrite', async () => {
  const alice = env.authenticatedContext('alice').storage();
  await assertFails(uploadBytes(ref(alice, P('alice', 'x.zip')), png, { contentType: 'application/zip' }));
  await assertSucceeds(uploadBytes(ref(alice, P('alice', 'v.m4a')), png, { contentType: 'audio/mp4' })); // voice recording
  await assertFails(uploadBytes(ref(alice, P('alice', 'x.html')), png, { contentType: 'text/html' }));
  await assertSucceeds(uploadBytes(ref(alice, P('alice', 'ok.pdf')), png, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(alice, P('alice', 'ok.pdf')), png, { contentType: 'application/pdf' })); // update denied
  const big = new Uint8Array(16 * 1024 * 1024 + 1);
  await assertFails(uploadBytes(ref(alice, P('alice', 'big.mp4')), big, { contentType: 'video/mp4' }));
});

test('storage: template images folder still works', async () => {
  const alice = env.authenticatedContext('alice').storage();
  await assertSucceeds(uploadBytes(ref(alice, 'outreach_images/alice/1.jpg'), png, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(alice, 'outreach_images/bob/1.jpg'), png, { contentType: 'image/jpeg' }));
});

// ── Admin console (phone and web): admins read and manage sales, salesmen and clients.

async function seedAdmin() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', 'root'), { approved: true, role: 'admin', name: 'Root' });
    await setDoc(doc(db, 'sales', 'sA'), { salesmanId: 'alice', businessName: 'Alpha Sale', leadStatus: 'new', clientPaymentStatus: 'pending', employeePaymentStatus: 'pending', priceChargedToClient: 100 });
    await setDoc(doc(db, 'sales', 'sB'), { salesmanId: 'bob', businessName: 'Bravo Sale', leadStatus: 'new' });
    await setDoc(doc(db, 'clients', 'c1'), { businessName: 'Client One', mapsUrl: 'https://maps.app.goo.gl/one' });
    await setDoc(doc(db, 'whatsappValidatedScans', 'v1'), { storagePath: 'whatsapp-validated-scans/v1.xlsx' });
    await setDoc(doc(db, 'whatsappValidatedScans', 'v2'), { storagePath: 'whatsapp-validated-scans/v2.xlsx' });
    await uploadBytes(ref(ctx.storage(), 'whatsapp-validated-scans/v1.xlsx'), new Uint8Array([1, 2, 3]));
  });
}

test('a salesman cannot make themselves an admin, on sign-up or later', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertFails(updateDoc(doc(alice, 'users/alice'), { role: 'admin' }));
  await assertFails(setDoc(doc(alice, 'users/alice'), { role: 'admin' }, { merge: true }));
  const newbie = env.authenticatedContext('newbie').firestore();
  await assertFails(setDoc(doc(newbie, 'users/newbie'), { approved: false, role: 'admin' }));
  await assertSucceeds(setDoc(doc(newbie, 'users/newbie'), { approved: false, role: 'salesman' }));
});

test('an admin reads every user and sale; a salesman reads only their own sales', async () => {
  await seedAdmin();
  const root = env.authenticatedContext('root').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  await assertSucceeds(getDocs(collection(root, 'users')));
  await assertSucceeds(getDocs(collection(root, 'sales')));
  await assertSucceeds(getDoc(doc(alice, 'sales/sA')));
  await assertFails(getDoc(doc(alice, 'sales/sB')));
  await assertFails(getDocs(collection(alice, 'sales')));
  await assertFails(getDoc(doc(alice, 'users/bob')));
});

test('an admin approves a salesman and sets their limit or role, but not their name', async () => {
  await seedAdmin();
  const root = env.authenticatedContext('root').firestore();
  await assertSucceeds(updateDoc(doc(root, 'users/bob'), { approved: true, dailyLeadLimit: 5, role: 'salesman', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(root, 'users/bob'), { dailyLeadLimit: deleteField(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(root, 'users/bob'), { name: 'Renamed' }));
  await assertFails(updateDoc(doc(root, 'users/bob'), { dailyLeadLimit: 5000 }));
  await assertFails(updateDoc(doc(root, 'users/bob'), { role: 'boss' }));
  await assertFails(updateDoc(doc(root, 'users/bob'), { approved: 'yes' }));
});

test('an admin creates, edits and deletes sales with valid stages; a salesman cannot write sales', async () => {
  await seedAdmin();
  const root = env.authenticatedContext('root').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  await assertSucceeds(setDoc(doc(root, 'sales/sNew'), { businessName: 'New', leadStatus: 'payment', clientPaymentStatus: 'paid', employeePaymentStatus: 'pending' }));
  await assertFails(setDoc(doc(root, 'sales/sBad'), { businessName: 'Bad', leadStatus: 'shipped' }));
  await assertSucceeds(updateDoc(doc(root, 'sales/sA'), { paymentsArchived: true, paymentsArchivedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(doc(root, 'sales/sNew')));
  await assertFails(setDoc(doc(alice, 'sales/sX'), { salesmanId: 'alice', businessName: 'Mine' }));
  await assertFails(updateDoc(doc(alice, 'sales/sA'), { leadStatus: 'completed' }));
  await assertFails(deleteDoc(doc(alice, 'sales/sA')));
});

test('clients are admin-only, and need a name and a Maps link', async () => {
  await seedAdmin();
  const root = env.authenticatedContext('root').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  await assertSucceeds(getDoc(doc(root, 'clients/c1')));
  await assertFails(getDoc(doc(alice, 'clients/c1')));
  await assertFails(setDoc(doc(alice, 'clients/c9'), { businessName: 'Nope', mapsUrl: 'https://maps.app.goo.gl/x' }));
  await assertSucceeds(setDoc(doc(root, 'clients/c2'), { businessName: 'Client Two', mapsUrl: 'https://maps.app.goo.gl/two' }));
  await assertFails(setDoc(doc(root, 'clients/c3'), { businessName: 'No link' }));
  // An older client with no link can still be renamed.
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'clients/c4'), { businessName: 'Old Client' }));
  await assertSucceeds(updateDoc(doc(root, 'clients/c4'), { businessName: 'Old Client Renamed' }));
});

test('an admin deletes a verified archive and its file; a salesman cannot', async () => {
  await seedAdmin();
  const root = env.authenticatedContext('root').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  await assertFails(deleteDoc(doc(alice, 'whatsappValidatedScans/v2')));
  await assertFails(setDoc(doc(root, 'whatsappValidatedScans/v3'), { storagePath: 'x' }));
  await assertSucceeds(deleteDoc(doc(root, 'whatsappValidatedScans/v2')));

  const rootStore = env.authenticatedContext('root').storage();
  const aliceStore = env.authenticatedContext('alice').storage();
  await assertFails(deleteObject(ref(aliceStore, 'whatsapp-validated-scans/v1.xlsx')));
  await assertSucceeds(deleteObject(ref(rootStore, 'whatsapp-validated-scans/v1.xlsx')));
});
