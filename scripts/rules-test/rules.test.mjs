// Run with: cd scripts/rules-test && npm i && npm test   (needs Java for the emulators)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where, serverTimestamp, deleteField } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

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
