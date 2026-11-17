const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareImport } = require('../scripts/import-phone-catalog');

function baseCatalog() {
  return {
    version: '2026-11-16.4',
    brands: [{
      id: 'brand-tai-ben-niu',
      name: '太犇牛',
      aliases: ['TAI BEN NIU', '太奔牛'],
      logoAssetName: 'BrandIconTaiBenNiu'
    }],
    drinks: [{
      id: 'brand-tai-ben-niu-drink-1',
      brandId: 'brand-tai-ben-niu',
      brandName: '太犇牛',
      name: '厚乳拿铁',
      cupTypes: ['中杯'],
      nutritionPerUnit: { amount: 100, unit: 'ml', sugarG: 3, source: '软件包营养' },
      menuEntries: [{ scope: 'brand', sourceName: '软件包菜单' }]
    }]
  };
}

function transfer({ withLogo = true } = {}) {
  const logoImageID = '2ecba6ca-94c9-4bb5-9eb3-5595f2556231';
  return {
    schemaVersion: 1,
    brands: [{
      id: 'local-brand-phone',
      name: '太奔牛',
      aliases: [],
      logoImageID: withLogo ? logoImageID : null,
      logoIsOverridden: withLogo
    }],
    drinks: [{
      id: 'local-drink-phone',
      brandId: 'local-brand-phone',
      brandName: '太奔牛',
      name: '厚乳拿铁',
      cupTypes: ['大杯'],
      nutritionPerUnit: { amount: 100, unit: 'ml', energyKcal: 90, source: '手机营养' },
      sourceName: '手机维护',
      menuEntries: [{ scope: 'brand', sourceName: '手机菜单' }]
    }],
    logoAssets: withLogo ? [{
      id: logoImageID,
      data: Buffer.from('89504e470d0a1a0a', 'hex').toString('base64')
    }] : []
  };
}

test('phone import maps old brand IDs, merges same-name menus, and keeps the custom logo', () => {
  const plan = prepareImport(transfer(), baseCatalog(), { schemaVersion: 1, brands: [], drinks: [] });

  assert.equal(plan.ambiguities.length, 0);
  assert.equal(plan.nextOverrides.brands.length, 1);
  assert.equal(plan.nextOverrides.brands[0].id, 'brand-tai-ben-niu');
  assert.equal(plan.nextOverrides.brands[0].name, '太犇牛');
  assert.match(plan.nextOverrides.brands[0].logoAssetName, /^BrandIconUser/);
  assert.equal(plan.logoBrands[0].id, 'brand-tai-ben-niu');
  assert.equal(plan.nextOverrides.drinks.length, 1);
  assert.equal(plan.nextOverrides.drinks[0].id, 'local-drink-phone');
  assert.equal(plan.nextOverrides.drinks[0].brandId, 'brand-tai-ben-niu');
  assert.deepEqual(plan.nextOverrides.drinks[0].legacyIds, ['brand-tai-ben-niu-drink-1']);
  assert.deepEqual(plan.nextOverrides.drinks[0].cupTypes, ['大杯', '中杯']);
  assert.equal(plan.nextOverrides.drinks[0].nutritionPerUnit.energyKcal, 90);
  assert.equal(plan.nextOverrides.drinks[0].nutritionPerUnit.sugarG, 3);
  assert.deepEqual(plan.nextOverrides.drinks[0].menuEntries.map((entry) => entry.sourceName), ['手机菜单', '软件包菜单']);
});

test('phone import inherits packaged logo when no custom logo was exported', () => {
  const plan = prepareImport(transfer({ withLogo: false }), baseCatalog(), { schemaVersion: 1, brands: [], drinks: [] });
  assert.equal(plan.nextOverrides.brands[0].logoAssetName, 'BrandIconTaiBenNiu');
  assert.equal(plan.newLogoCount, 0);
});

test('phone re-import replaces its old duplicate brand override with the packaged ID', () => {
  const oldBrand = { id: 'local-brand-phone', name: '太奔牛', aliases: [] };
  const currentCatalog = {
    ...baseCatalog(),
    brands: [...baseCatalog().brands, oldBrand],
    _bundledBrandIDs: ['brand-tai-ben-niu']
  };
  const currentOverrides = {
    schemaVersion: 1,
    brands: [oldBrand],
    drinks: [{ id: 'local-drink-phone', brandId: 'local-brand-phone', name: '厚乳拿铁' }]
  };

  const plan = prepareImport(transfer({ withLogo: false }), currentCatalog, currentOverrides);

  assert.deepEqual(plan.nextOverrides.brands.map((brand) => brand.id), ['brand-tai-ben-niu']);
  assert.equal(plan.nextOverrides.drinks[0].brandId, 'brand-tai-ben-niu');
});

test('phone import reports ambiguous aliases without choosing a packaged brand', () => {
  const ambiguousCatalog = {
    version: 'v1',
    brands: [
      { id: 'brand-a', name: '品牌甲', aliases: ['旧名称'] },
      { id: 'brand-b', name: '品牌乙', aliases: ['旧名称'] }
    ],
    drinks: []
  };
  const ambiguousTransfer = {
    schemaVersion: 1,
    brands: [{ id: 'local-old', name: '旧名称', aliases: [] }],
    drinks: [],
    logoAssets: []
  };

  const plan = prepareImport(ambiguousTransfer, ambiguousCatalog, { schemaVersion: 1, brands: [], drinks: [] });

  assert.equal(plan.ambiguities.length, 1);
  assert.equal(plan.nextOverrides.brands[0].id, 'local-old');
});
