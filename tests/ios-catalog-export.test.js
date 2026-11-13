const test = require('node:test');
const assert = require('node:assert/strict');
const seed = require('../data/catalog');
const { createIOSCatalog } = require('../scripts/export-ios-catalog');

test('iOS catalog export preserves the complete versioned mini-program catalog contract', () => {
  const catalog = createIOSCatalog(seed);

  assert.equal(catalog.version, seed.version);
  assert.equal(catalog.updatedAt, seed.updatedAt);
  assert.equal(catalog.brands.length, seed.brands.length);
  assert.equal(catalog.drinks.length, seed.drinks.length);
  assert.deepEqual(catalog.brands, seed.brands);
  assert.deepEqual(catalog.drinks, seed.drinks);

  for (const drink of catalog.drinks) {
    for (const field of ['cupTypes', 'cupSizes', 'sizesMl', 'sweetnessOptions', 'servingOptions', 'nutritionVariants', 'menuEntries']) {
      assert.ok(Array.isArray(drink[field]), `${drink.id}.${field} is an array`);
    }
  }
});
