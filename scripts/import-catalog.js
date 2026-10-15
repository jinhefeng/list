#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const Contract = require('../utils/catalog-contract');

const SOURCE_TYPES = ['official_brand', 'public_menu', 'authorized_platform', 'manual_platform', 'user_report', 'pending'];
const DEFAULT_INPUT = path.join(__dirname, '..', 'data', 'catalog-import-template.csv');
const DEFAULT_OUTPUT = path.join(__dirname, '..', 'data', 'catalog-release.json');

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"' && field === '') quoted = true;
    else if (char === ',') {
      row.push(field);
      field = '';
    } else if (char === '\n') {
      row.push(field.replace(/\r$/, ''));
      if (row.some((value) => value.trim())) rows.push(row);
      row = [];
      field = '';
    } else field += char;
  }
  if (quoted) throw new Error('CSV has an unclosed quoted field.');
  row.push(field.replace(/\r$/, ''));
  if (row.some((value) => value.trim())) rows.push(row);
  return rows;
}

function splitList(value) {
  return String(value || '').split('|').map((item) => item.trim()).filter(Boolean);
}

function unique(values) {
  const seen = new Set();
  return values.filter((value) => {
    const normalized = String(value || '').trim();
    if (!normalized || seen.has(normalized)) return false;
    seen.add(normalized);
    return true;
  });
}

function parseCupSizes(value, rowNumber) {
  if (!String(value || '').trim()) return [];
  let cupSizes;
  try { cupSizes = JSON.parse(value); } catch (error) {
    throw new Error(`Row ${rowNumber}: cup_sizes_json is not valid JSON.`);
  }
  if (!Array.isArray(cupSizes)) throw new Error(`Row ${rowNumber}: cup_sizes_json must be a JSON array.`);
  return cupSizes.map((item, index) => {
    if (!item || typeof item !== 'object' || Array.isArray(item) || !String(item.cupType || '').trim()) {
      throw new Error(`Row ${rowNumber}: cup size ${index + 1} needs a cupType.`);
    }
    if (item.sizeMl !== undefined && (!Number.isInteger(Number(item.sizeMl)) || Number(item.sizeMl) <= 0)) {
      throw new Error(`Row ${rowNumber}: cup size ${index + 1} sizeMl must be a positive whole number.`);
    }
    return { cupType: String(item.cupType).trim(), ...(item.sizeMl === undefined ? {} : { sizeMl: Number(item.sizeMl) }) };
  });
}

function parseNutritionVariants(value, rowNumber) {
  if (!String(value || '').trim()) return [];
  let variants;
  try { variants = JSON.parse(value); } catch (error) {
    throw new Error(`Row ${rowNumber}: nutrition_variants_json is not valid JSON.`);
  }
  if (!Array.isArray(variants)) throw new Error(`Row ${rowNumber}: nutrition_variants_json must be a JSON array.`);
  variants.forEach((variant, index) => {
    if (!variant || typeof variant !== 'object' || Array.isArray(variant)) throw new Error(`Row ${rowNumber}: nutrition variant ${index + 1} must be an object.`);
    if (variant.sourceType && !['official', 'estimated'].includes(variant.sourceType)) {
      throw new Error(`Row ${rowNumber}: nutrition variant ${index + 1} sourceType must be official or estimated.`);
    }
  });
  return variants;
}

function parseNutritionPerUnit(value, rowNumber) {
  if (!String(value || '').trim()) return null;
  let nutrition;
  try { nutrition = JSON.parse(value); } catch (error) {
    throw new Error(`Row ${rowNumber}: nutrition_per_unit_json is not valid JSON.`);
  }
  if (!nutrition || typeof nutrition !== 'object' || Array.isArray(nutrition)) {
    throw new Error(`Row ${rowNumber}: nutrition_per_unit_json must be a JSON object.`);
  }
  const amount = Number(nutrition.amount);
  if (!Number.isFinite(amount) || amount <= 0) throw new Error(`Row ${rowNumber}: nutrition per unit amount must be positive.`);
  if (!['ml', '杯'].includes(nutrition.unit)) throw new Error(`Row ${rowNumber}: nutrition per unit unit must be ml or 杯.`);
  const result = { amount, unit: nutrition.unit };
  ['sugarG', 'energyKcal', 'caffeineMg'].forEach((key) => {
    const raw = nutrition[key];
    if (raw === undefined || raw === null || raw === '') result[key] = null;
    else {
      const number = Number(raw);
      if (!Number.isFinite(number) || number < 0) throw new Error(`Row ${rowNumber}: nutrition per unit ${key} must be non-negative.`);
      result[key] = number;
    }
  });
  result.sourceType = nutrition.sourceType || 'estimated';
  if (!['official', 'estimated'].includes(result.sourceType)) throw new Error(`Row ${rowNumber}: nutrition per unit sourceType must be official or estimated.`);
  result.source = String(nutrition.source || '').trim();
  result.updatedAt = String(nutrition.updatedAt || '').trim();
  if (result.sourceType === 'official' && [result.sugarG, result.energyKcal, result.caffeineMg].some((item) => item !== null) && !result.source) {
    throw new Error(`Row ${rowNumber}: official nutrition per unit data needs a source.`);
  }
  return result;
}

function parseBoolean(value, fallback, rowNumber) {
  if (!String(value || '').trim()) return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (['true', '1', 'yes'].includes(normalized)) return true;
  if (['false', '0', 'no'].includes(normalized)) return false;
  throw new Error(`Row ${rowNumber}: expected true or false.`);
}

function mergeStatus(current, next) {
  if (!current || current === next) return next;
  if (current === 'pending' || next === 'pending') return 'pending';
  if (current === 'verified' || next === 'verified') return 'verified';
  return 'unavailable';
}

function parseCsvCatalog(text, version, generatedAt) {
  const rows = parseCsv(text);
  if (!rows.length) throw new Error('CSV is empty.');
  const headers = rows[0].map((value, index) => (index === 0 ? value.replace(/^\uFEFF/, '') : value).trim());
  const duplicateHeaders = headers.filter((value, index) => headers.indexOf(value) !== index);
  if (duplicateHeaders.length) throw new Error(`Duplicate CSV header: ${duplicateHeaders[0]}`);
  const headerIndex = new Map(headers.map((name, index) => [name, index]));
  const requiredHeaders = ['brand_id', 'brand_name', 'brand_aliases', 'brand_category', 'drink_id', 'drink_name', 'drink_aliases',
    'city', 'store_id', 'store_name', 'menu_status', 'active', 'cup_sizes_json', 'sweetness_options', 'serving_options',
    'source_type', 'source_name', 'source_url', 'checked_at', 'nutrition_variants_json'];
  const missingHeaders = requiredHeaders.filter((name) => !headerIndex.has(name));
  if (missingHeaders.length) throw new Error(`Missing CSV headers: ${missingHeaders.join(', ')}`);

  const brands = new Map();
  const drinks = new Map();
  const seenEntries = new Set();
  const cell = (row, name) => headerIndex.has(name) ? String(row[headerIndex.get(name)] || '').trim() : '';

  rows.slice(1).forEach((row, index) => {
    const rowNumber = index + 2;
    if (row.length > headers.length) throw new Error(`Row ${rowNumber}: contains more cells than the CSV header.`);
    const brandId = cell(row, 'brand_id');
    const brandName = cell(row, 'brand_name');
    const drinkId = cell(row, 'drink_id');
    const drinkName = cell(row, 'drink_name');
    const status = cell(row, 'menu_status');
    const sourceType = cell(row, 'source_type');
    if (!brandId || !brandName || !drinkId || !drinkName) throw new Error(`Row ${rowNumber}: brand and drink IDs and names are required.`);
    if (!Contract.MENU_STATUSES.includes(status)) throw new Error(`Row ${rowNumber}: menu_status must be verified, pending, or unavailable.`);
    if (!SOURCE_TYPES.includes(sourceType)) throw new Error(`Row ${rowNumber}: source_type is invalid.`);

    const city = cell(row, 'city');
    const storeId = cell(row, 'store_id');
    const storeName = cell(row, 'store_name');
    if ((storeId || storeName) && !city) throw new Error(`Row ${rowNumber}: store-level menu rows need a city.`);
    const entryKey = [drinkId, city, storeId || storeName, (!city && !storeId && !storeName) ? 'brand' : ''].join('\u0000');
    if (seenEntries.has(entryKey)) throw new Error(`Row ${rowNumber}: duplicate menu entry for ${drinkId} at ${storeName || city || 'brand level'}.`);
    seenEntries.add(entryKey);

    const checkedAt = cell(row, 'checked_at');
    const sourceName = cell(row, 'source_name');
    const sourceUrl = cell(row, 'source_url');
    if (status !== 'pending' && (!checkedAt || !/^\d{4}-\d{2}-\d{2}$/.test(checkedAt) || (!sourceName && !sourceUrl))) {
      throw new Error(`Row ${rowNumber}: verified/unavailable rows need checked_at (YYYY-MM-DD) and a source_name or source_url.`);
    }
    if (status !== 'pending' && sourceType === 'pending') {
      throw new Error(`Row ${rowNumber}: verified/unavailable rows need a recorded source_type.`);
    }
    if (status === 'pending' && sourceType !== 'pending' && !sourceName && !sourceUrl) {
      throw new Error(`Row ${rowNumber}: use source_type pending until a source is recorded.`);
    }
    if (sourceType === 'public_menu' && status !== 'pending') {
      throw new Error(`Row ${rowNumber}: public_menu entries must remain pending until confirmed in the local platform menu.`);
    }

    const active = parseBoolean(cell(row, 'active'), status !== 'unavailable', rowNumber);
    let brand = brands.get(brandId);
    if (!brand) {
      brand = { id: brandId, name: brandName, aliases: [], category: cell(row, 'brand_category'), active: false, status: '', updatedAt: '' };
      brands.set(brandId, brand);
    } else if (brand.name !== brandName || brand.category !== cell(row, 'brand_category')) {
      throw new Error(`Row ${rowNumber}: brand_id ${brandId} has inconsistent name or category.`);
    }
    brand.aliases = unique(brand.aliases.concat(splitList(cell(row, 'brand_aliases'))));
    brand.status = mergeStatus(brand.status, status);
    if (checkedAt > brand.updatedAt) brand.updatedAt = checkedAt;
    brand.active = brand.active || active;

    let drink = drinks.get(drinkId);
    if (!drink) {
      drink = { id: drinkId, brandId, brandName, name: drinkName, category: cell(row, 'drink_category') || cell(row, 'brand_category'), aliases: [], active: false, status: '', source: '', sourceType, region: '', updatedAt: '', cupTypes: [], cupSizes: [], sizesMl: [], sweetnessOptions: [], servingOptions: [], nutritionVariants: [], menuEntries: [] };
      drinks.set(drinkId, drink);
    } else if (drink.brandId !== brandId || drink.name !== drinkName
      || drink.category !== (cell(row, 'drink_category') || cell(row, 'brand_category'))) {
      throw new Error(`Row ${rowNumber}: drink_id ${drinkId} has inconsistent brand or name.`);
    }

    const nutritionPerUnit = parseNutritionPerUnit(cell(row, 'nutrition_per_unit_json'), rowNumber);
    if (nutritionPerUnit) {
      if (drink.nutritionPerUnit && JSON.stringify(drink.nutritionPerUnit) !== JSON.stringify(nutritionPerUnit)) {
        throw new Error(`Row ${rowNumber}: drink_id ${drinkId} has inconsistent nutrition_per_unit_json.`);
      }
      drink.nutritionPerUnit = nutritionPerUnit;
    }

    const cupSizes = parseCupSizes(cell(row, 'cup_sizes_json'), rowNumber);
    const cupTypes = unique(cupSizes.map((item) => item.cupType));
    const sizesMl = unique(cupSizes.filter((item) => item.sizeMl).map((item) => item.sizeMl)).sort((a, b) => a - b);
    const sweetnessOptions = splitList(cell(row, 'sweetness_options'));
    const servingOptions = splitList(cell(row, 'serving_options'));
    const entry = {
      scope: storeId || storeName ? 'store' : city ? 'city' : 'brand',
      city,
      storeId,
      storeName,
      status,
      sourceType,
      sourceName,
      sourceUrl,
      checkedAt,
      cupTypes,
      cupSizes,
      sizesMl,
      sweetnessOptions,
      servingOptions
    };
    drink.menuEntries.push(entry);
    drink.aliases = unique(drink.aliases.concat(splitList(cell(row, 'drink_aliases'))));
    drink.cupTypes = unique(drink.cupTypes.concat(cupTypes));
    const cupSizeKeys = new Set(drink.cupSizes.map((item) => `${item.cupType}\u0000${item.sizeMl || ''}`));
    cupSizes.forEach((item) => {
      const key = `${item.cupType}\u0000${item.sizeMl || ''}`;
      if (!cupSizeKeys.has(key)) {
        drink.cupSizes.push(item);
        cupSizeKeys.add(key);
      }
    });
    drink.sizesMl = unique(drink.sizesMl.concat(sizesMl)).sort((a, b) => a - b);
    drink.sweetnessOptions = unique(drink.sweetnessOptions.concat(sweetnessOptions));
    drink.servingOptions = unique(drink.servingOptions.concat(servingOptions));
    drink.nutritionVariants = drink.nutritionVariants.concat(parseNutritionVariants(cell(row, 'nutrition_variants_json'), rowNumber));
    drink.status = mergeStatus(drink.status, status);
    if (checkedAt > drink.updatedAt) drink.updatedAt = checkedAt;
    drink.active = drink.active || active;
    if (!drink.source && (sourceName || sourceUrl || sourceType !== 'pending')) drink.source = sourceName || sourceUrl || sourceType;
    if (!drink.region && city) drink.region = city;
    else if (city && !drink.region.split('、').includes(city)) drink.region = `${drink.region}、${city}`;
  });

  if (!drinks.size) throw new Error('CSV has a header but no beverage rows.');
  brands.forEach((brand) => {
    if (!brand.status) brand.status = 'pending';
    if (!brand.updatedAt) brand.updatedAt = generatedAt.slice(0, 10);
  });
  drinks.forEach((drink) => {
    if (!drink.status) drink.status = 'pending';
    if (!drink.updatedAt) drink.updatedAt = generatedAt.slice(0, 10);
  });
  const catalog = { version, generatedAt, brands: Array.from(brands.values()), drinks: Array.from(drinks.values()) };
  const validation = Contract.validateCatalog(catalog);
  if (!validation.valid) throw new Error(`Catalog validation failed:\n- ${validation.errors.join('\n- ')}`);
  return catalog;
}

function parseArguments(argv) {
  const result = { input: DEFAULT_INPUT, output: DEFAULT_OUTPUT, version: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!['--input', '--output', '--version'].includes(key)) throw new Error(`Unknown argument: ${key}`);
    if (!argv[i + 1]) throw new Error(`Missing value for ${key}`);
    result[key.slice(2)] = argv[i + 1];
    i += 1;
  }
  return result;
}

function main(argv) {
  const args = parseArguments(argv);
  const generatedAt = new Date().toISOString();
  const version = args.version || generatedAt.slice(0, 10);
  const csvText = fs.readFileSync(args.input, 'utf8');
  const catalog = parseCsvCatalog(csvText, version, generatedAt);
  fs.mkdirSync(path.dirname(path.resolve(args.output)), { recursive: true });
  fs.writeFileSync(args.output, `${JSON.stringify(catalog, null, 2)}\n`, 'utf8');
  process.stdout.write(`Wrote ${catalog.drinks.length} drinks from ${catalog.brands.length} brands to ${args.output} (version ${version}).\n`);
}

if (require.main === module) {
  try { main(process.argv.slice(2)); } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { parseCsv, parseCsvCatalog };
