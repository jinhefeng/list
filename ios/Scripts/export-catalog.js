#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const source = require('../../data/catalog');

const brands = source.brands.map((brand) => ({
  id: String(brand.id || ''),
  name: String(brand.name || ''),
  aliases: Array.isArray(brand.aliases) ? brand.aliases.map(String) : [],
  category: String(brand.category || ''),
  source: String(brand.source || ''),
  sourceName: String(brand.sourceName || ''),
  sourceUrl: String(brand.sourceUrl || ''),
  updatedAt: String(brand.updatedAt || source.updatedAt || ''),
  status: String(brand.status || 'pending'),
  active: brand.active !== false
}));

const drinks = source.drinks.map((drink) => {
  const firstMenu = Array.isArray(drink.menuEntries) ? (drink.menuEntries[0] || {}) : {};
  return {
    id: String(drink.id || ''),
    brandId: String(drink.brandId || ''),
    brandName: String(drink.brandName || ''),
    name: String(drink.name || ''),
    aliases: Array.isArray(drink.aliases) ? drink.aliases.map(String) : [],
    category: String(drink.category || ''),
    source: String(drink.source || ''),
    sourceType: String(drink.sourceType || firstMenu.sourceType || ''),
    sourceName: String(firstMenu.sourceName || ''),
    sourceUrl: String(firstMenu.sourceUrl || ''),
    updatedAt: String(drink.updatedAt || source.updatedAt || ''),
    status: String(drink.status || firstMenu.status || 'pending'),
    active: drink.active !== false
  };
});

const catalog = { version: source.version, updatedAt: source.updatedAt, brands, drinks };
const outputPath = path.resolve(__dirname, '../GanfanHandbook/Resources/catalog.json');
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(catalog)}\n`);
process.stdout.write(`Exported ${brands.length} brands and ${drinks.length} drinks to ${outputPath}\n`);
