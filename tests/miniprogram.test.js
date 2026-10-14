const test = require('node:test');
const assert = require('node:assert/strict');

const storage = new Map();
let pageDefinition;
global.Page = (definition) => { pageDefinition = definition; };
global.getApp = () => ({ globalData: { userId: 'test-user' } });
global.wx = {
  getStorageSync(key) { return storage.has(key) ? storage.get(key) : ''; },
  setStorageSync(key, value) { storage.set(key, value); },
  chooseMedia(options) { options.success({ tempFiles: [{ tempFilePath: '/tmp/drink.jpg' }] }); },
  saveFile(options) { options.success({ savedFilePath: 'wxfile://drink.jpg' }); },
  showToast() {},
  navigateBack() {},
  showModal() {}
};
require('../pages/record/record');

function createPage() {
  return Object.assign({
    data: JSON.parse(JSON.stringify(pageDefinition.data)),
    setData(changes) { Object.assign(this.data, changes); }
  }, pageDefinition);
}

test('native mini program form selects a menu item, saves a photo and one personalized drink', () => {
  storage.clear();
  const page = createPage();
  page.onLoad({});
  page.selectBrand({ currentTarget: { dataset: { id: 'brand-heytea' } } });
  page.selectDrink({ currentTarget: { dataset: { id: 'brand-heytea-drink-1' } } });
  page.updateField({ currentTarget: { dataset: { field: 'sizeMl' } }, detail: { value: '500' } });
  page.updateField({ currentTarget: { dataset: { field: 'sweetness' } }, detail: { value: '半糖' } });
  page.updateField({ currentTarget: { dataset: { field: 'ice' } }, detail: { value: '少冰' } });
  page.updateField({ currentTarget: { dataset: { field: 'toppings' } }, detail: { value: '珍珠' } });
  page.updateField({ currentTarget: { dataset: { field: 'location' } }, detail: { value: '公司楼下' } });
  page.updateField({ currentTarget: { dataset: { field: 'notes' } }, detail: { value: '少糖刚好' } });
  page.choosePhoto();
  const previousSetTimeout = global.setTimeout;
  global.setTimeout = (callback) => { callback(); return 1; };
  try { page.save(); } finally { global.setTimeout = previousSetTimeout; }
  const records = storage.get('drink-log:records');
  assert.equal(records.length, 1);
  assert.equal(records[0].userId, 'test-user');
  assert.equal(records[0].drinkName, '多肉葡萄');
  assert.match(records[0].consumedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00$/);
  assert.equal(records[0].sizeMl, 500);
  assert.deepEqual(records[0].toppings, ['珍珠']);
  assert.equal(records[0].location, '公司楼下');
  assert.equal(records[0].notes, '少糖刚好');
  assert.equal(records[0].photo, 'wxfile://drink.jpg');
});

test('native mini program form creates custom drinks and marks entered nutrition as estimated', () => {
  storage.clear();
  const page = createPage();
  page.onLoad({});
  page.enableCustom();
  const setField = (field, value) => page.updateField({ currentTarget: { dataset: { field } }, detail: { value } });
  setField('brandName', '巷口茶铺');
  setField('drinkName', '桂花乌龙');
  setField('sizeMl', '450');
  setField('sweetness', '三分糖');
  setField('ice', '去冰');
  setField('energyKcal', '180');
  setField('sugarG', '22');
  setField('caffeineMg', '36');
  const previousSetTimeout = global.setTimeout;
  global.setTimeout = (callback) => { callback(); return 1; };
  try { page.save(); } finally { global.setTimeout = previousSetTimeout; }
  const catalog = storage.get('drink-log:drinks');
  const custom = catalog.find((drink) => drink.custom);
  assert.equal(custom.name, '桂花乌龙');
  assert.equal(custom.nutritionVariants[0].sourceType, 'estimated');
  assert.equal(custom.nutritionVariants[0].energyKcal, '180');
  assert.equal(storage.get('drink-log:records')[0].drinkId, custom.id);
});
