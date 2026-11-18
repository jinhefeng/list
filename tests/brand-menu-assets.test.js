const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const catalog = require('../data/catalog');
const bundledCatalog = require('../ios/GanfanHandbook/Resources/catalog.json');

const assetsRoot = path.join(__dirname, '../ios/GanfanHandbook/Assets.xcassets');
const brandSystem = fs.readFileSync(path.join(__dirname, '../ios/GanfanHandbook/BrandSystem.swift'), 'utf8');
const ownBackgroundAssets = brandSystem.match(/assetsWithOwnBackground: Set<String> = \[([\s\S]*?)\]/)?.[1] || '';

test('bundled catalog includes requested brands and brand logo assets', () => {
  const expected = [
    ['brand-coca-cola', '可口可乐', 'BrandIconCocaCola'],
    ['brand-juan-cha', '眷茶', 'BrandIconJuanCha'],
    ['brand-sui-yin-ji-liang', '碎银几两', 'BrandIconSuiYinJiLiang'],
    ['brand-mcdonalds', '麦当劳', 'BrandIconMcDonalds'],
    ['brand-kfc', '肯德基', 'BrandIconKFC'],
    ['brand-quchashan', '去茶山', 'BrandIconQuchashan', '去茶山茶饮'],
    ['brand-red-tea-company', '红茶公司', 'BrandIconCharlieTown', 'Charlie Town Tea Company'],
    ['brand-tai-ben-niu', '太犇牛', 'BrandIconTaiBenNiu', 'TAI BEN NIU'],
    ['brand-chun-tian', '椿田熟成茶行', 'BrandIconChunTian'],
    ['brand-yihetang', '益禾堂', 'BrandIconYihetang']
  ];

  for (const [id, name, assetName, expectedAlias] of expected) {
    const brand = catalog.brands.find((item) => item.id === id);
    const bundledBrand = bundledCatalog.brands.find((item) => item.id === id);
    assert.ok(brand, `missing brand ${name}`);
    assert.ok(bundledBrand, `${name} missing from the iOS bundled catalog`);
    assert.equal(brand.name, name);
    assert.equal(brand.logoAssetName, assetName);
    assert.equal(bundledBrand.name, name);
    assert.equal(bundledBrand.logoAssetName, assetName);
    if (expectedAlias) {
      assert.ok(brand.aliases.includes(expectedAlias), `missing ${expectedAlias} alias for ${name}`);
      assert.ok(bundledBrand.aliases.includes(expectedAlias), `${expectedAlias} alias missing from the iOS catalog`);
    }

    const assetPath = path.join(assetsRoot, `${assetName}.imageset`);
    const manifestPath = path.join(assetPath, 'Contents.json');
    assert.ok(fs.existsSync(manifestPath), `missing ${assetName} asset manifest`);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const image = manifest.images.find((entry) => entry.filename);
    assert.ok(image, `missing bundled image for ${assetName}`);
    assert.ok(fs.existsSync(path.join(assetPath, image.filename)), `missing ${image.filename}`);
  }

  const taiBenNiu = catalog.brands.find((item) => item.id === 'brand-tai-ben-niu');
  assert.ok(taiBenNiu.aliases.includes('太奔牛'), 'the manually used phone name should map to 太犇牛');
  assert.ok(bundledCatalog.brands.find((item) => item.id === 'brand-tai-ben-niu').aliases.includes('太奔牛'));

  for (const id of ['brand-quchashan', 'brand-red-tea-company', 'brand-tai-ben-niu']) {
    assert.equal(catalog.drinks.some((drink) => drink.brandId === id), false, `${id} should not have unverified menu drinks`);
  }
});

test('益禾堂 keeps its existing menu and uses the supplied logo image', () => {
  const brands = catalog.brands.filter((item) => item.id === 'brand-yihetang');
  const drinks = catalog.drinks.filter((item) => item.brandId === 'brand-yihetang');
  assert.equal(brands.length, 1);
  assert.ok(drinks.some((item) => item.name === '杨枝甘露'));
  assert.equal(brands[0].logoAssetName, 'BrandIconYihetang');

  const manifestPath = path.join(assetsRoot, 'BrandIconYihetang.imageset/Contents.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  assert.equal(manifest.images[0].filename, 'BrandIconYihetang.png');
});

test('椿田熟成茶行 menu entries retain page sources and pending status', () => {
  const drink = catalog.drinks.find((item) => item.brandId === 'brand-chun-tian' && item.name === '黄油朗姆饼干牛乳茶');
  assert.ok(drink);
  assert.equal(drink.status, 'pending');
  assert.ok(drink.menuEntries.some((entry) => entry.sourceUrl.includes('chun-tian-shu-cheng-cha-xing/menu/available')));
  for (const name of ['黑武士芋泥熟成薯丸', '香草籽芋泥熟成薯丸', '黑武士熟成薯丸']) {
    assert.ok(catalog.drinks.some((item) => item.brandId === 'brand-chun-tian' && item.name === name), `missing ${name}`);
  }
});

test('red tea company logo uses a white backing with a small inset', () => {
  assert.match(ownBackgroundAssets, /"BrandIconQuchashan"/);
  assert.doesNotMatch(ownBackgroundAssets, /"BrandIconCharlieTown"/);
  assert.match(brandSystem, /private var logoContentInset: CGFloat \{\s*resolvedAssetName == "BrandIconCharlieTown" \? dimension \* 0\.06 : 0\s*\}/);
  assert.match(brandSystem, /\.padding\(logoContentInset\)[\s\S]*?\.background\(needsWhiteBacking \? Color\.white : Color\.clear\)/);
});

test('Tai Ben Niu logo keeps its supplied tan background', () => {
  assert.match(ownBackgroundAssets, /"BrandIconTaiBenNiu"/);
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
