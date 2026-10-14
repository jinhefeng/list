const test = require('node:test');
const assert = require('node:assert/strict');
const domain = require('../utils/domain');

const base = {
  id: 'r1', userId: 'u1', brandId: 'b1', brandName: '茶铺', drinkId: 'd1',
  drinkName: '青茶', consumedAt: '2026-10-13T09:15:00.000Z', sizeMl: 500,
  sweetness: '半糖', ice: '少冰', toppings: ['珍珠'], photo: '', location: '', notes: ''
};

test('creates one owned drink record and rejects multiple drinks per record', () => {
  const record = domain.createRecord(base, 'u1');
  assert.equal(record.userId, 'u1');
  assert.equal(record.drinkId, 'd1');
  const repeated = domain.createRecord({ ...base, id: 'r2' }, 'u1');
  assert.notEqual(record.id, repeated.id);
  assert.throws(() => domain.createRecord({ ...base, drinks: ['d1', 'd2'] }, 'u1'), /one drink/i);
  assert.throws(() => domain.createRecord(base, ''), /user/i);
  assert.throws(() => domain.createRecord({ ...base, sizeMl: -1 }, 'u1'), /size/i);
});

test('isolates and sorts records for their owner', () => {
  const rows = [base, { ...base, id: 'r2', userId: 'u2' }, { ...base, id: 'r3', consumedAt: '2026-10-13T12:00:00.000Z' }];
  assert.deepEqual(domain.listRecords(rows, 'u1').map((row) => row.id), ['r3', 'r1']);
  assert.deepEqual(domain.listRecords(rows, 'u2').map((row) => row.id), ['r2']);
  assert.deepEqual(domain.listRecords(rows, 'u1', '2026-10-13').map((row) => row.id), ['r3', 'r1']);
});

test('allows unknown optional choices, photo, location and notes', () => {
  const record = domain.createRecord({ ...base, sweetness: '', ice: '', toppings: [], photo: '', location: '', notes: '' }, 'u1');
  assert.equal(record.sweetness, '');
  assert.deepEqual(record.toppings, []);
});

test('searches brands and drinks, including discontinued catalog items', () => {
  const catalog = {
    brands: [{ id: 'b1', name: '茶铺', source: '店铺菜单', updatedAt: '2026-10-01', active: true }],
    drinks: [
      { id: 'd1', brandId: 'b1', name: '青茶', active: true },
      { id: 'd2', brandId: 'b1', name: '旧款红茶', active: false }
    ]
  };
  assert.equal(domain.searchBrands(catalog.brands, '茶')[0].id, 'b1');
  assert.deepEqual(domain.searchDrinks(catalog.drinks, 'b1', '茶').map((row) => row.id), ['d1']);
  assert.equal(domain.findDrink(catalog.drinks, 'd2').active, false);
});

test('seed catalog retains source, region, update date and nutrition variant fields', () => {
  const catalog = require('../data/catalog');
  assert.ok(catalog.brands.length > 0);
  assert.ok(catalog.brands.every((brand) => brand.source && brand.updatedAt));
  assert.ok(catalog.drinks.every((drink) => drink.source && drink.region && drink.updatedAt && Array.isArray(drink.nutritionVariants)));
});

test('creates custom drink catalog entries', () => {
  const item = domain.createCustomDrink({ brandName: '自定义店', drinkName: '桂花乌龙', sizeMl: 450 }, 'u1');
  assert.equal(item.custom, true);
  assert.equal(item.brandName, '自定义店');
  assert.equal(item.name, '桂花乌龙');
  assert.equal(item.sizeMl, 450);
});

test('updates and deletes only the current user records', () => {
  const rows = [base, { ...base, id: 'r2', userId: 'u2' }];
  assert.equal(domain.updateRecord(rows, 'r1', 'u1', { notes: '已修改' })[0].notes, '已修改');
  assert.throws(() => domain.updateRecord(rows, 'r2', 'u1', { notes: '越权' }), /not found/i);
  assert.equal(domain.deleteRecord(rows, 'r1', 'u1').length, 1);
  assert.throws(() => domain.deleteRecord(rows, 'r2', 'u1'), /not found/i);
});

test('applies only an exact nutrition variant and preserves provenance labels', () => {
  const drink = {
    nutritionVariants: [
      { sizeMl: 500, sweetness: '半糖', ice: '少冰', toppings: ['珍珠'], sourceType: 'official', energyKcal: 210, sugarG: 28, caffeineMg: 45 },
      { sizeMl: 500, sweetness: '全糖', ice: '少冰', toppings: ['珍珠'], sourceType: 'estimated', energyKcal: 280, sugarG: 44, caffeineMg: 45 }
    ]
  };
  const official = domain.nutritionForRecord({ ...base, sizeMl: 500 }, drink);
  assert.equal(official.status, 'official');
  assert.equal(official.label, '官方数据');
  assert.equal(official.energyKcal, 210);
  const estimate = domain.nutritionForRecord({ ...base, sweetness: '全糖' }, drink);
  assert.equal(estimate.status, 'estimated');
  assert.equal(estimate.label, '估算值');
  const unavailable = domain.nutritionForRecord({ ...base, ice: '去冰' }, drink);
  assert.equal(unavailable.status, 'unavailable');
  assert.equal(unavailable.label, '暂无数据');
});

test('summarizes available nutrition without treating missing values as zero', () => {
  const records = [base, { ...base, id: 'r2', drinkId: 'd2' }, { ...base, id: 'r3', drinkId: 'd3' }];
  const drinks = [
    { id: 'd1', nutritionVariants: [{ sizeMl: 500, sweetness: '半糖', ice: '少冰', toppings: ['珍珠'], sourceType: 'official', energyKcal: 200, sugarG: 25, caffeineMg: 40 }] },
    { id: 'd2', nutritionVariants: [{ sizeMl: 500, sweetness: '半糖', ice: '少冰', toppings: ['珍珠'], sourceType: 'estimated', energyKcal: 100, sugarG: 10, caffeineMg: 0 }] },
    { id: 'd3', nutritionVariants: [] }
  ];
  const summary = domain.dailySummary(records, drinks, '2026-10-13');
  assert.equal(summary.drinkCount, 3);
  assert.equal(summary.energyKcal, 300);
  assert.equal(summary.sugarG, 35);
  assert.equal(summary.caffeineMg, 40);
  assert.equal(summary.officialCount, 1);
  assert.equal(summary.estimatedCount, 1);
  assert.equal(summary.unavailableCount, 1);
  assert.equal(summary.energyLabel, '300');
});
