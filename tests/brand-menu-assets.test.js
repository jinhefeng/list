const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const catalog = require('../data/catalog');

const assetsRoot = path.join(__dirname, '../ios/GanfanHandbook/Assets.xcassets');
const brandSystem = fs.readFileSync(path.join(__dirname, '../ios/GanfanHandbook/BrandSystem.swift'), 'utf8');

test('bundled catalog includes requested brands and brand logo assets', () => {
  const expected = [
    ['brand-coca-cola', '可口可乐', 'BrandIconCocaCola'],
    ['brand-juan-cha', '眷茶', 'BrandIconJuanCha'],
    ['brand-sui-yin-ji-liang', '碎银几两', 'BrandIconSuiYinJiLiang'],
    ['brand-mcdonalds', '麦当劳', 'BrandIconMcDonalds'],
    ['brand-kfc', '肯德基', 'BrandIconKFC']
  ];

  for (const [id, name, assetName] of expected) {
    const brand = catalog.brands.find((item) => item.id === id);
    assert.ok(brand, `missing brand ${name}`);
    assert.equal(brand.name, name);
    assert.equal(brand.logoAssetName, assetName);
    assert.ok(fs.existsSync(path.join(assetsRoot, `${assetName}.imageset`, 'Contents.json')));
  }
});

test('眷茶 and 碎银几两 public menu candidates are searchable by brand', () => {
  for (const [brandID, expectedName] of [
    ['brand-juan-cha', '满庭芳'],
    ['brand-sui-yin-ji-liang', '满江红·茶布奇诺']
  ]) {
    const brand = catalog.brands.find((item) => item.id === brandID);
    assert.ok(brand, `missing menu brand ${brandID}`);
    const drink = catalog.drinks.find((item) => item.brandId === brandID && item.name === expectedName);
    assert.ok(drink, `missing ${expectedName}`);
    assert.equal(drink.status, 'pending');
    assert.ok(drink.menuEntries.some((entry) => entry.sourceUrl));
  }
});

test('shared brand logo renderer uses one visible rounded corner rule for every logo', () => {
  assert.match(brandSystem, /clipShape\(RoundedRectangle\(cornerRadius: dimension \* 0\.24, style: \.continuous\)\)/);
  assert.doesNotMatch(brandSystem, /\.padding\(1\)/);
});
