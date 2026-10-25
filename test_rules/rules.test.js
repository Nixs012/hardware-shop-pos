const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-rules-test';

async function runTests() {
  const rules = fs.readFileSync(path.resolve(__dirname, '../app/firestore.rules'), 'utf8');

  const testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules,
      host: '127.0.0.1',
      port: 8080,
    },
  });

  console.log('--- Setting up initial test data ---');
  // Seed baseline data using admin context
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    // Shop A
    await setDoc(doc(db, 'shops', 'shopA'), {
      name: 'Shop A',
      owner_uid: 'adminA',
      join_code: 'CODE_A',
      created_at: new Date(),
    });
    await setDoc(doc(db, 'joinCodes', 'CODE_A'), {
      shopId: 'shopA',
    });
    await setDoc(doc(db, 'users', 'adminA'), {
      uid: 'adminA',
      shop_id: 'shopA',
      role: 'admin',
      name: 'Admin A',
      email: 'adminA@test.com',
      active: true,
    });
    await setDoc(doc(db, 'shops', 'shopA', 'staff', 'adminA'), {
      id: 'adminA',
      name: 'Admin A',
      role: 'admin',
      email: 'adminA@test.com',
      active: true,
      auth_uid: 'adminA',
      shop_id: 'shopA',
    });
    await setDoc(doc(db, 'shops', 'shopA', 'products', 'prodA1'), {
      name: 'Hammer',
      selling_price: 500,
      quantity_on_hand: 10,
    });

    // Shop B
    await setDoc(doc(db, 'shops', 'shopB'), {
      name: 'Shop B',
      owner_uid: 'adminB',
      join_code: 'CODE_B',
      created_at: new Date(),
    });
    await setDoc(doc(db, 'joinCodes', 'CODE_B'), {
      shopId: 'shopB',
    });
    await setDoc(doc(db, 'users', 'adminB'), {
      uid: 'adminB',
      shop_id: 'shopB',
      role: 'admin',
      name: 'Admin B',
      email: 'adminB@test.com',
      active: true,
    });
    await setDoc(doc(db, 'users', 'cashierB'), {
      uid: 'cashierB',
      shop_id: 'shopB',
      role: 'cashier',
      name: 'Cashier B',
      email: 'cashierB@test.com',
      active: true,
    });
    await setDoc(doc(db, 'shops', 'shopB', 'staff', 'cashierB'), {
      id: 'cashierB',
      name: 'Cashier B',
      role: 'cashier',
      email: 'cashierB@test.com',
      active: true,
      auth_uid: 'cashierB',
      shop_id: 'shopB',
    });
  });

  let passed = 0;
  let failed = 0;

  async function test(name, fn) {
    try {
      await fn();
      console.log(`  [PASS] ${name}`);
      passed++;
    } catch (err) {
      console.error(`  [FAIL] ${name}:`, err.message || err);
      failed++;
    }
  }

  console.log('\n--- Running Security Rules Tests ---');

  // 1. A stranger cannot list shops or joinCodes
  await test('a stranger cannot list shops', async () => {
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(unauthDb, 'shops')));
  });

  await test('a stranger cannot list joinCodes', async () => {
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(unauthDb, 'joinCodes')));
  });

  await test('a stranger can get a specific joinCode by key', async () => {
    const unauthDb = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(unauthDb, 'joinCodes', 'CODE_A')));
  });

  // 2. A wrong code is rejected
  await test('a wrong join code is rejected when joining as cashier (staff doc)', async () => {
    const newCashierDb = testEnv.authenticatedContext('cashier_new_wrong').firestore();
    await assertFails(
      setDoc(doc(newCashierDb, 'shops', 'shopA', 'staff', 'cashier_new_wrong'), {
        id: 'cashier_new_wrong',
        name: 'Attacker',
        role: 'cashier',
        email: 'attacker@test.com',
        active: true,
        auth_uid: 'cashier_new_wrong',
        shop_id: 'shopA',
        join_code: 'WRONG_CODE_999',
      })
    );
  });

  await test('a wrong join code is rejected when joining as cashier (users doc)', async () => {
    const newCashierDb = testEnv.authenticatedContext('cashier_new_wrong').firestore();
    await assertFails(
      setDoc(doc(newCashierDb, 'users', 'cashier_new_wrong'), {
        uid: 'cashier_new_wrong',
        shop_id: 'shopA',
        role: 'cashier',
        name: 'Attacker',
        email: 'attacker@test.com',
        active: true,
        join_code: 'WRONG_CODE_999',
      })
    );
  });

  await test('a valid join code succeeds when joining as cashier', async () => {
    const validCashierDb = testEnv.authenticatedContext('cashier_valid').firestore();
    // In actual app, users and staff docs are written in a batch
    await assertSucceeds(
      setDoc(doc(validCashierDb, 'users', 'cashier_valid'), {
        uid: 'cashier_valid',
        shop_id: 'shopA',
        role: 'cashier',
        name: 'Valid Cashier',
        email: 'cashier@test.com',
        active: true,
        join_code: 'CODE_A',
      })
    );
    await assertSucceeds(
      setDoc(doc(validCashierDb, 'shops', 'shopA', 'staff', 'cashier_valid'), {
        id: 'cashier_valid',
        name: 'Valid Cashier',
        role: 'cashier',
        email: 'cashier@test.com',
        active: true,
        auth_uid: 'cashier_valid',
        shop_id: 'shopA',
        join_code: 'CODE_A',
      })
    );
  });

  // 3. A cashier cannot become admin
  await test('a cashier cannot create user doc with role admin for existing shop', async () => {
    const rogueUserDb = testEnv.authenticatedContext('rogue_user').firestore();
    await assertFails(
      setDoc(doc(rogueUserDb, 'users', 'rogue_user'), {
        uid: 'rogue_user',
        shop_id: 'shopA',
        role: 'admin',
        name: 'Rogue Admin',
        email: 'rogue@test.com',
        active: true,
        join_code: 'CODE_A',
      })
    );
  });

  await test('an existing cashier cannot update their role to admin', async () => {
    const cashierDb = testEnv.authenticatedContext('cashierB').firestore();
    await assertFails(
      updateDoc(doc(cashierDb, 'users', 'cashierB'), {
        role: 'admin',
      })
    );
  });

  // 4. Shop B\'s user cannot read Shop A\'s data
  await test('shop B cashier cannot read shop A document', async () => {
    const cashierBDb = testEnv.authenticatedContext('cashierB').firestore();
    await assertFails(getDoc(doc(cashierBDb, 'shops', 'shopA')));
  });

  await test('shop B cashier cannot read shop A products', async () => {
    const cashierBDb = testEnv.authenticatedContext('cashierB').firestore();
    await assertFails(getDocs(collection(cashierBDb, 'shops', 'shopA', 'products')));
  });

  await test('shop A admin CAN read shop A document and products', async () => {
    const adminADb = testEnv.authenticatedContext('adminA').firestore();
    await assertSucceeds(getDoc(doc(adminADb, 'shops', 'shopA')));
    await assertSucceeds(getDocs(collection(adminADb, 'shops', 'shopA', 'products')));
  });

  console.log(`\nResults: ${passed} passed, ${failed} failed\n`);

  await testEnv.cleanup();

  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch((err) => {
  console.error('Test run failed:', err);
  process.exit(1);
});
