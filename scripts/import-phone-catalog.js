#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const overridePath = path.join(root, 'data', 'catalog-phone-overrides.json');
const assetsRoot = path.join(root, 'ios', 'GanfanHandbook', 'Assets.xcassets');
const exportIOSPath = path.join(__dirname, 'export-ios-catalog.js');

function normalizeName(value) {
  return String(value || '').normalize('NFC').trim().replace(/\s+/g, '').toLocaleLowerCase();
}

function readJSON(filePath, description) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`Cannot read ${description}: ${error.message}`);
  }
}

function mergeByID(rows, updates) {
  const result = new Map((rows || []).map((row) => [row.id, row]));
  (updates || []).forEach((row) => result.set(row.id, row));
  return Array.from(result.values());
}

function assetNameForBrand(brandID) {
  const hash = crypto.createHash('sha256').update(brandID).digest('hex').slice(0, 12);
  return `BrandIconUser${hash}`;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function nextVersion(current) {
  const date = today();
  const match = String(current || '').match(/^(\d{4}-\d{2}-\d{2})(?:\.(\d+))?$/);
  if (match && match[1] === date) return `${date}.${Number(match[2] || 0) + 1}`;
  return `${date}.1`;
}

function parseArguments(argv) {
  const result = { input: '', apply: false };
  for (const value of argv) {
    if (value === '--apply') result.apply = true;
    else if (value.startsWith('--')) throw new Error(`Unknown option: ${value}`);
    else if (result.input) throw new Error('Supply one phone export file at a time.');
    else result.input = value;
  }
  if (!result.input) {
    throw new Error('Usage: npm run catalog:import-phone -- <phone-export.json> [--apply]');
  }
  return result;
}

function validateTransfer(transfer, currentCatalog) {
  if (!transfer || transfer.schemaVersion !== 1) {
    throw new Error('Unsupported phone catalog export. Expected schemaVersion 1.');
  }
  if (!Array.isArray(transfer.brands) || !Array.isArray(transfer.drinks) || !Array.isArray(transfer.logoAssets)) {
    throw new Error('Phone export must contain brands, drinks, and logoAssets arrays.');
  }

  const incomingBrandIDs = new Set();
  const allBrandIDs = new Set((currentCatalog?.brands || []).map((brand) => brand.id));
  for (const brand of transfer.brands) {
    if (!brand || typeof brand.id !== 'string' || !brand.id.trim() || typeof brand.name !== 'string' || !brand.name.trim()) {
      throw new Error('Every exported brand needs a non-empty id and name.');
    }
    if (incomingBrandIDs.has(brand.id)) throw new Error(`Duplicate exported brand id: ${brand.id}`);
    incomingBrandIDs.add(brand.id);
    allBrandIDs.add(brand.id);
  }

  const logoIDs = new Set();
  for (const logo of transfer.logoAssets) {
    if (!logo || typeof logo.id !== 'string' || typeof logo.data !== 'string') {
      throw new Error('Every logo asset needs an id and base64 PNG data.');
    }
    if (logoIDs.has(logo.id)) throw new Error(`Duplicate logo asset id: ${logo.id}`);
    logoIDs.add(logo.id);
    const bytes = Buffer.from(logo.data, 'base64');
    if (bytes.length < 8 || bytes.length > 20_000_000 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
      throw new Error(`Logo ${logo.id} is not a valid PNG or is too large.`);
    }
  }

  const incomingDrinkIDs = new Set();
  for (const drink of transfer.drinks) {
    if (!drink || typeof drink.id !== 'string' || !drink.id.trim() || typeof drink.name !== 'string' || !drink.name.trim()) {
      throw new Error('Every exported drink needs a non-empty id and name.');
    }
    if (incomingDrinkIDs.has(drink.id)) throw new Error(`Duplicate exported drink id: ${drink.id}`);
    incomingDrinkIDs.add(drink.id);
    if (!allBrandIDs.has(drink.brandId)) throw new Error(`Drink “${drink.name}” refers to unknown brand id ${drink.brandId}.`);
  }

  for (const brand of transfer.brands) {
    if (brand.logoImageID && !logoIDs.has(brand.logoImageID)) {
      throw new Error(`Brand “${brand.name}” refers to missing Logo file ${brand.logoImageID}.`);
    }
  }
}

function uniqueStrings(values) {
  const seen = new Set();
  return values.filter((value) => {
    const key = normalizeName(value);
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function mergeNutritionPerUnit(preferred, fallback) {
  if (!preferred) return fallback || null;
  if (!fallback || preferred.amount !== fallback.amount || normalizeName(preferred.unit) !== normalizeName(fallback.unit)) {
    return preferred;
  }
  const merged = { ...fallback, ...preferred };
  for (const field of ['energyKcal', 'sugarG', 'caffeineMg', 'proteinG', 'fatG', 'carbohydrateG', 'sourceType', 'source', 'updatedAt']) {
    if (preferred[field] == null || preferred[field] === '') merged[field] = fallback[field] ?? null;
  }
  return merged;
}

function matchBrand(brand, currentCatalog, bundledBrandIDs) {
  const bundledBrands = currentCatalog.brands.filter((item) => bundledBrandIDs.has(item.id));
  const exactBundled = bundledBrands.find((item) => item.id === brand.id);
  if (exactBundled) return { brand: exactBundled, candidates: [] };
  const names = new Set([brand.name, ...(brand.aliases || [])].map(normalizeName));
  const bundledMatches = bundledBrands.filter((item) =>
    [item.name, ...(item.aliases || [])].some((name) => names.has(normalizeName(name))));
  if (bundledMatches.length === 1) return { brand: bundledMatches[0], candidates: [] };
  if (bundledMatches.length > 1) return { brand: null, candidates: bundledMatches };

  const exactExisting = currentCatalog.brands.find((item) => item.id === brand.id);
  if (exactExisting) return { brand: exactExisting, candidates: [] };
  const allMatches = currentCatalog.brands.filter((item) =>
    [item.name, ...(item.aliases || [])].some((name) => names.has(normalizeName(name))));
  if (allMatches.length === 1) return { brand: allMatches[0], candidates: [] };
  return { brand: null, candidates: allMatches.length > 1 ? allMatches : [] };
}

function mergeDrink(preferred, fallback, canonicalBrand) {
  const union = (first, second) => uniqueStrings([...(first || []), ...(second || [])]);
  const preferredEntries = preferred.menuEntries || [];
  const fallbackEntries = (fallback.menuEntries || []).filter((entry) => !preferredEntries.some((item) => JSON.stringify(item) === JSON.stringify(entry)));
  const legacyIds = union([...(preferred.legacyIds || []), ...(fallback.legacyIds || []), ...(preferred.id === fallback.id ? [] : [fallback.id])])
    .filter((id) => id !== preferred.id);
  return {
    ...fallback,
    ...preferred,
    id: preferred.id,
    legacyIds,
    brandId: canonicalBrand.id,
    brandName: canonicalBrand.name,
    name: preferred.name || fallback.name,
    aliases: union([...(preferred.aliases || []), ...(fallback.aliases || []), ...(preferred.name === fallback.name ? [] : [fallback.name])]),
    category: preferred.category || fallback.category || '',
    source: preferred.source || fallback.source || '',
    sourceType: preferred.sourceType || fallback.sourceType || '',
    sourceName: preferred.sourceName || fallback.sourceName || '',
    sourceUrl: preferred.sourceUrl || fallback.sourceUrl || '',
    updatedAt: preferred.updatedAt || fallback.updatedAt || '',
    cupTypes: union(preferred.cupTypes, fallback.cupTypes),
    cupSizes: [...(preferred.cupSizes || []), ...(fallback.cupSizes || []).filter((item) =>
      !(preferred.cupSizes || []).some((first) => normalizeName(first.cupType) === normalizeName(item.cupType)))],
    sizesMl: [...new Set([...(preferred.sizesMl || []), ...(fallback.sizesMl || [])])],
    sweetnessOptions: union(preferred.sweetnessOptions, fallback.sweetnessOptions),
    servingOptions: union(preferred.servingOptions, fallback.servingOptions),
    nutritionPerUnit: mergeNutritionPerUnit(preferred.nutritionPerUnit, fallback.nutritionPerUnit),
    nutritionVariants: [...(preferred.nutritionVariants || []), ...(fallback.nutritionVariants || []).filter((item) => !(preferred.nutritionVariants || []).some((first) => JSON.stringify(first) === JSON.stringify(item)))],
    menuEntries: preferredEntries.concat(fallbackEntries)
  };
}

function normalizeBrand(brand, existingBrand, logoAssets, canonicalBrand) {
  const merged = { ...(canonicalBrand || existingBrand || {}), ...(existingBrand || {}), ...brand };
  merged.id = canonicalBrand.id;
  merged.name = canonicalBrand.name;
  merged.aliases = uniqueStrings([
    ...(canonicalBrand.aliases || []), ...(brand.aliases || []),
    ...(brand.name === canonicalBrand.name ? [] : [brand.name])
  ]).filter((name) => normalizeName(name) !== normalizeName(canonicalBrand.name));
  const imageID = brand.logoImageID;
  if (imageID && logoAssets.has(imageID)) {
    merged.logoAssetName = assetNameForBrand(canonicalBrand.id);
    merged.logoSourceUrl = brand.logoSourceUrl || brand.logoUrl || existingBrand?.logoSourceUrl || '';
  } else {
    merged.logoAssetName = canonicalBrand.logoAssetName || existingBrand?.logoAssetName || null;
    merged.logoSourceUrl = brand.logoSourceUrl || existingBrand?.logoSourceUrl || '';
  }
  delete merged.logoImageID;
  delete merged.logoIsOverridden;
  delete merged.localOverride;
  delete merged.logoUrl;
  return merged;
}

function normalizeDrink(drink, existingDrink) {
  const merged = { ...(existingDrink || {}), ...drink };
  if (existingDrink && existingDrink.id !== drink.id) {
    merged.legacyIds = uniqueStrings([...(drink.legacyIds || []), ...(existingDrink.legacyIds || []), existingDrink.id])
      .filter((id) => id !== drink.id);
  } else {
    merged.legacyIds = (drink.legacyIds || []).filter((id) => id !== drink.id);
  }
  delete merged.localOverride;
  delete merged.custom;
  return merged;
}

function prepareImport(transfer, currentCatalog, currentOverrides) {
  validateTransfer(transfer, currentCatalog);
  const logoAssets = new Map(transfer.logoAssets.map((logo) => [logo.id, logo]));
  const brandsByID = new Map(currentCatalog.brands.map((brand) => [brand.id, brand]));
  const bundledBrandIDs = new Set(currentCatalog._bundledBrandIDs || currentCatalog.brands.map((brand) => brand.id));
  const brandIDMap = new Map();
  const ambiguities = [];
  const logoBrands = [];
  const newBrands = transfer.brands.map((brand) => {
    const match = matchBrand(brand, currentCatalog, bundledBrandIDs);
    if (match.candidates.length) {
      ambiguities.push({ name: brand.name, candidates: match.candidates.map(({ id, name }) => ({ id, name })) });
    }
    const canonicalBrand = match.brand || brand;
    brandIDMap.set(brand.id, canonicalBrand.id);
    if (brand.logoImageID && logoAssets.has(brand.logoImageID)) {
      logoBrands.push({ ...brand, id: canonicalBrand.id });
    }
    return normalizeBrand(brand, brandsByID.get(canonicalBrand.id), logoAssets, canonicalBrand);
  });

  const canonicalBrandByID = new Map(currentCatalog.brands.map((brand) => [brand.id, brand]));
  const drinksByID = new Map(currentCatalog.drinks.map((drink) => [drink.id, drink]));
  const normalizedIncomingDrinks = transfer.drinks.map((drink) => {
    const canonicalBrandID = brandIDMap.get(drink.brandId) || drink.brandId;
    const canonicalBrand = canonicalBrandByID.get(canonicalBrandID) || newBrands.find((brand) => brand.id === canonicalBrandID) || {
      id: canonicalBrandID,
      name: drink.brandName
    };
    const normalized = { ...drink, brandId: canonicalBrandID, brandName: canonicalBrand.name };
    const sameName = currentCatalog.drinks.filter((candidate) =>
      candidate.brandId === canonicalBrandID && normalizeName(candidate.name) === normalizeName(drink.name));
    const identityMatch = sameName.length === 1 ? sameName[0] : null;
    const existingDrink = drinksByID.get(drink.id) || identityMatch;
    return normalizeDrink(mergeDrink(normalized, existingDrink || {}, canonicalBrand), existingDrink);
  });
  const groupedDrinks = new Map();
  for (const drink of normalizedIncomingDrinks) {
    const key = `${drink.brandId}|${normalizeName(drink.name)}`;
    const existing = groupedDrinks.get(key);
    groupedDrinks.set(key, existing ? mergeDrink(existing, drink, canonicalBrandByID.get(drink.brandId) || drink) : drink);
  }
  const newDrinks = Array.from(groupedDrinks.values());

  const remappedOldBrandIDs = new Set(Array.from(brandIDMap).filter(([oldID, newID]) => oldID !== newID).map(([oldID]) => oldID));
  const retainedExistingBrands = (currentOverrides.brands || []).filter((brand) => !remappedOldBrandIDs.has(brand.id));
  const brandOverrides = mergeByID(retainedExistingBrands, newBrands);
  const remappedExistingDrinks = (currentOverrides.drinks || []).map((drink) => ({
    ...drink,
    brandId: brandIDMap.get(drink.brandId) || drink.brandId
  }));
  const drinkOverrides = mergeByID(remappedExistingDrinks, newDrinks);
  const nextOverrides = {
    schemaVersion: 1,
    version: nextVersion(currentCatalog.version),
    updatedAt: today(),
    brands: brandOverrides,
    drinks: drinkOverrides
  };
  const newCount = (incoming, existing) => incoming.filter((row) => !existing.has(row.id)).length;
  const existingBrandIDs = new Set(currentCatalog.brands.map((brand) => brand.id));
  const existingDrinkIDs = new Set(currentCatalog.drinks.map((drink) => drink.id));
  return {
    nextOverrides,
    logoAssets,
    logoBrands,
    newBrandCount: newCount(newBrands, existingBrandIDs),
    updatedBrandCount: newBrands.length - newCount(newBrands, existingBrandIDs),
    newDrinkCount: newCount(newDrinks, existingDrinkIDs),
    updatedDrinkCount: newDrinks.length - newCount(newDrinks, existingDrinkIDs),
    newLogoCount: transfer.logoAssets.length,
    ambiguities,
    mergedDrinkCount: normalizedIncomingDrinks.filter((drink) => drink.legacyIds.length > 0).length
  };
}

function writeLogoAssets(brands, logoAssets) {
  const assetsByID = new Map(brands.filter((brand) => brand.logoImageID).map((brand) => [brand.id, brand.logoImageID]));
  for (const brand of brands) {
    const imageID = assetsByID.get(brand.id);
    if (!imageID) continue;
    const logo = logoAssets.get(imageID);
    if (!logo) continue;
    const assetName = assetNameForBrand(brand.id);
    const directory = path.join(assetsRoot, `${assetName}.imageset`);
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, `${assetName}.png`), Buffer.from(logo.data, 'base64'));
    fs.writeFileSync(path.join(directory, 'Contents.json'), `${JSON.stringify({
      images: [{ filename: `${assetName}.png`, idiom: 'universal' }],
      info: { author: 'xcode', version: 1 }
    }, null, 2)}\n`);
  }
}

function main(argv) {
  const args = parseArguments(argv);
  const input = path.resolve(args.input);
  const transfer = readJSON(input, 'phone export');
  const currentOverrides = readJSON(overridePath, 'existing phone overrides');
  const currentCatalog = require('../data/catalog');
  const plan = prepareImport(transfer, currentCatalog, currentOverrides);

  process.stdout.write(`Phone catalog export: ${input}\n`);
  process.stdout.write(`Brands: ${plan.newBrandCount} new, ${plan.updatedBrandCount} updated\n`);
  process.stdout.write(`Drinks: ${plan.newDrinkCount} new, ${plan.updatedDrinkCount} updated\n`);
  process.stdout.write(`Logo images: ${plan.newLogoCount}\n`);
  process.stdout.write(`Merged same-name menus: ${plan.mergedDrinkCount}\n`);
  for (const ambiguity of plan.ambiguities) {
    const options = ambiguity.candidates.map((item) => `${item.name} (${item.id})`).join(', ');
    process.stdout.write(`Ambiguous brand “${ambiguity.name}”: ${options}; kept as a separate entry.\n`);
  }
  process.stdout.write(`Next catalog version: ${plan.nextOverrides.version}\n`);

  if (!args.apply) {
    process.stdout.write('Preview only. Add --apply to merge the phone data into project sources.\n');
    return;
  }

  if (plan.ambiguities.length) {
    throw new Error('Resolve ambiguous brand matches before applying this import.');
  }

  writeLogoAssets(plan.logoBrands, plan.logoAssets);
  fs.writeFileSync(overridePath, `${JSON.stringify(plan.nextOverrides, null, 2)}\n`, 'utf8');
  execFileSync(process.execPath, [exportIOSPath], { cwd: root, stdio: 'inherit' });
  process.stdout.write('Imported phone-maintained catalog data and refreshed the bundled iOS catalog.\n');
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { prepareImport, nextVersion, normalizeName };
