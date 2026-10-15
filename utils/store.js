const seed = require('../data/catalog');
const catalogConfig = require('../data/catalog-config');
const CatalogContract = require('./catalog-contract');

const KEYS = { records: 'drink-log:records', brands: 'drink-log:brands', drinks: 'drink-log:drinks', cupSizes: 'drink-log:global-cup-sizes', deletedDrinkIds: 'drink-log:deleted-catalog-drink-ids', catalogVersion: 'drink-log:catalog-version', catalogUpdatedAt: 'drink-log:catalog-updated-at', bundledCatalogVersion: 'drink-log:bundled-catalog-version' };
const DEFAULT_CUP_SIZES = ['小杯', '中杯', '大杯', '超大杯'].map((cupType) => ({ cupType, sizeMl: '' }));
let syncPromise = null;
let lastSyncAt = 0;
const SYNC_INTERVAL_MS = 5 * 60 * 1000;

function read(key, fallback) {
  const value = wx.getStorageSync(key);
  return value === '' || value === undefined || value === null ? fallback : value;
}

function refreshBundledCatalog(currentBrands, currentDrinks) {
  const brandsInStorage = Array.isArray(currentBrands) ? currentBrands : [];
  const drinksInStorage = Array.isArray(currentDrinks) ? currentDrinks : [];
  const localBrandById = new Map(brandsInStorage
    .filter((brand) => brand && brand.localOverride)
    .map((brand) => [brand.id, brand]));
  const localDrinkById = new Map(drinksInStorage
    .filter((drink) => drink && (drink.localOverride || drink.custom))
    .map((drink) => [drink.id, drink]));
  const deletedDrinkIds = new Set(read(KEYS.deletedDrinkIds, []));
  const bundledDrinkIds = new Set(seed.drinks.map((drink) => drink.id));

  const brands = seed.brands.map((brand) => localBrandById.get(brand.id) || brand);
  const knownBrandIds = new Set(brands.map((brand) => brand.id));
  brandsInStorage.forEach((brand) => {
    if (brand && !knownBrandIds.has(brand.id)) {
      brands.push(brand);
      knownBrandIds.add(brand.id);
    }
  });

  const drinks = seed.drinks
    .filter((drink) => !deletedDrinkIds.has(drink.id))
    .map((drink) => localDrinkById.get(drink.id) || drink);
  const knownDrinkIds = new Set(drinks.map((drink) => drink.id));
  drinksInStorage.forEach((drink) => {
    if (drink && !deletedDrinkIds.has(drink.id) && !bundledDrinkIds.has(drink.id) && !knownDrinkIds.has(drink.id)) {
      drinks.push(drink);
      knownDrinkIds.add(drink.id);
    }
  });

  return { brands, drinks };
}

function catalog() {
  let brands = read(KEYS.brands, null);
  let drinks = read(KEYS.drinks, null);
  const version = read(KEYS.catalogVersion, 'bundled');
  const remoteConfigured = String(catalogConfig.remoteUrl || '').trim();
  const canRefreshBundled = version === 'bundled' || !remoteConfigured;
  const bundledVersion = read(KEYS.bundledCatalogVersion, '');

  if (canRefreshBundled && (!Array.isArray(brands) || !Array.isArray(drinks) || bundledVersion !== seed.version)) {
    const updated = refreshBundledCatalog(brands, drinks);
    brands = updated.brands;
    drinks = updated.drinks;
    wx.setStorageSync(KEYS.brands, brands);
    wx.setStorageSync(KEYS.drinks, drinks);
    wx.setStorageSync(KEYS.bundledCatalogVersion, seed.version);
    wx.setStorageSync(KEYS.catalogVersion, 'bundled');
    wx.setStorageSync(KEYS.catalogUpdatedAt, seed.updatedAt || '');
  }

  if (!Array.isArray(brands)) brands = seed.brands;
  if (!Array.isArray(drinks)) drinks = seed.drinks;
  return { brands, drinks, version: read(KEYS.catalogVersion, 'bundled') };
}

function getRecords() { return read(KEYS.records, []); }
function saveRecords(records) { wx.setStorageSync(KEYS.records, records); }
function normalizeCupSizes(cupSizes) {
  return (Array.isArray(cupSizes) ? cupSizes : []).map((item) => {
    const cupType = String(item && item.cupType || '').trim();
    const sizeText = String(item && item.sizeMl !== undefined ? item.sizeMl : '').trim();
    const size = Number(sizeText);
    return cupType ? { cupType, sizeMl: sizeText && Number.isInteger(size) && size > 0 ? size : '' } : null;
  }).filter(Boolean);
}
function getCupSizes() {
  const stored = read(KEYS.cupSizes, null);
  if (Array.isArray(stored)) return normalizeCupSizes(stored);
  wx.setStorageSync(KEYS.cupSizes, DEFAULT_CUP_SIZES);
  return DEFAULT_CUP_SIZES.map((item) => ({ ...item }));
}
function saveCupSizes(cupSizes) {
  const normalized = normalizeCupSizes(cupSizes);
  wx.setStorageSync(KEYS.cupSizes, normalized);
  return normalized;
}
function saveCatalog(data) {
  wx.setStorageSync(KEYS.brands, data.brands);
  wx.setStorageSync(KEYS.drinks, data.drinks);
}

function deleteCatalogDrink(drinkId) {
  const data = catalog();
  if (!data.drinks.some((drink) => drink.id === drinkId)) return false;
  saveCatalog({ ...data, drinks: data.drinks.filter((drink) => drink.id !== drinkId) });
  const deletedDrinkIds = new Set(read(KEYS.deletedDrinkIds, []));
  deletedDrinkIds.add(drinkId);
  wx.setStorageSync(KEYS.deletedDrinkIds, Array.from(deletedDrinkIds));
  return true;
}

function saveUserDrink(drink) {
  const data = catalog();
  const normalize = (value) => String(value || '').trim().toLowerCase();
  const brandName = String(drink.brandName || '').trim();
  const name = String(drink.name || '').trim();
  let brand = data.brands.find((item) => normalize(item.name) === normalize(brandName));
  const now = new Date().toISOString();
  if (!brand) {
    brand = {
      id: `brand-user-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      name: brandName, aliases: [], category: drink.category || '', active: true, status: 'pending',
      source: '用户自定义，品牌和菜单待核验', sourceType: 'user_report', updatedAt: now, localOverride: true
    };
    data.brands.push(brand);
  } else if (brand.active === false) {
    brand.active = true;
    brand.localOverride = true;
    brand.updatedAt = now;
  }
  const index = data.drinks.findIndex((item) => item.id === drink.id
    || (item.brandId === brand.id && normalize(item.name) === normalize(name))
    || (!item.brandId && normalize(item.brandName) === normalize(brand.name) && normalize(item.name) === normalize(name)));
  const existing = index >= 0 ? data.drinks[index] : null;
  const savedDrink = {
    ...(existing || {}),
    ...drink,
    id: existing ? existing.id : drink.id,
    brandId: brand.id,
    brandName: brand.name,
    name,
    category: String(drink.category || (existing && existing.category) || ''),
    aliases: Array.isArray(drink.aliases) ? drink.aliases : (existing && existing.aliases) || [],
    active: true,
    status: existing && existing.status ? existing.status : 'pending',
    source: existing && existing.source ? existing.source : '用户自定义，菜单待核验',
    sourceType: existing && existing.sourceType ? existing.sourceType : 'user_report',
    cupTypes: Array.from(new Set(((existing && existing.cupTypes) || []).concat(drink.cupTypes || []).filter(Boolean))),
    cupSizes: (Array.isArray(drink.cupSizes) ? drink.cupSizes : (existing && Array.isArray(existing.cupSizes) ? existing.cupSizes : [])).slice(),
    sizesMl: Array.from(new Set(((existing && existing.sizesMl) || []).concat(drink.sizesMl || []).map(Number).filter((value) => Number.isInteger(value) && value > 0))).sort((a, b) => a - b),
    sweetnessOptions: (existing && existing.sweetnessOptions) || [],
    servingOptions: (existing && existing.servingOptions) || [],
    nutritionVariants: Array.isArray(drink.nutritionVariants) ? drink.nutritionVariants : (existing && existing.nutritionVariants) || [],
    menuEntries: (existing && Array.isArray(existing.menuEntries) && existing.menuEntries.length)
      ? existing.menuEntries : [{ scope: 'brand', status: 'pending', sourceType: 'user_report', sourceName: '用户自定义', sourceUrl: '', checkedAt: '',
        cupTypes: [], cupSizes: [], sizesMl: [], sweetnessOptions: [], servingOptions: [] }],
    custom: existing ? !!(existing.custom || drink.custom) : true,
    localOverride: true,
    updatedAt: now
  };
  const sizeMl = Number(drink.sizeMl) || 0;
  delete savedDrink.cupType;
  delete savedDrink.sizeMl;
  if (sizeMl > 0 && !savedDrink.sizesMl.includes(sizeMl)) savedDrink.sizesMl.push(sizeMl);
  savedDrink.menuEntries = savedDrink.menuEntries.map((entry) => {
    if (entry.scope !== 'brand' || entry.status !== 'pending' || entry.sourceType !== 'user_report') return entry;
    return {
      ...entry,
      sizesMl: Array.from(new Set((entry.sizesMl || []).concat(sizeMl > 0 ? [sizeMl] : [])))
    };
  });
  const deletedDrinkIds = new Set(read(KEYS.deletedDrinkIds, []));
  if (deletedDrinkIds.delete(savedDrink.id)) wx.setStorageSync(KEYS.deletedDrinkIds, Array.from(deletedDrinkIds));
  if (index >= 0) data.drinks[index] = savedDrink;
  else data.drinks.push(savedDrink);
  saveCatalog(data);
  return { catalog: data, drink: savedDrink };
}

function getCatalogInfo() {
  return {
    version: read(KEYS.catalogVersion, 'bundled'),
    updatedAt: read(KEYS.catalogUpdatedAt, '')
  };
}

function applyRemoteCatalog(remote) {
  const currentBrands = read(KEYS.brands, seed.brands);
  const currentDrinks = read(KEYS.drinks, seed.drinks);
  const localBrandById = new Map(currentBrands.filter((brand) => brand && brand.localOverride).map((brand) => [brand.id, brand]));
  const localById = new Map(currentDrinks.filter((drink) => drink && drink.localOverride).map((drink) => [drink.id, drink]));
  const remoteBrandIds = new Set(remote.brands.map((brand) => brand.id));
  const deletedDrinkIds = new Set(read(KEYS.deletedDrinkIds, []));
  const remoteDrinks = remote.drinks.filter((drink) => !deletedDrinkIds.has(drink.id));
  const remoteDrinkIds = new Set(remoteDrinks.map((drink) => drink.id));
  const updatedBrands = remote.brands.map((brand) => localBrandById.get(brand.id) || brand);
  const localOnlyBrands = currentBrands.filter((brand) => brand && brand.localOverride && !remoteBrandIds.has(brand.id));
  const updatedDrinks = remoteDrinks.map((drink) => localById.get(drink.id) || drink);
  const localOnlyDrinks = currentDrinks.filter((drink) => drink && (drink.custom || drink.localOverride) && !remoteDrinkIds.has(drink.id));
  saveCatalog({ brands: updatedBrands.concat(localOnlyBrands), drinks: updatedDrinks.concat(localOnlyDrinks) });
  wx.setStorageSync(KEYS.catalogVersion, remote.version);
  wx.setStorageSync(KEYS.catalogUpdatedAt, remote.generatedAt || remote.updatedAt || '');
}

function syncCatalog() {
  const endpoint = String(catalogConfig.remoteUrl || '').trim();
  if (!endpoint) return Promise.resolve({ updated: false, reason: 'not-configured' });
  if (typeof wx.request !== 'function') return Promise.resolve({ updated: false, reason: 'request-unavailable' });
  if (syncPromise) return syncPromise;
  if (lastSyncAt && Date.now() - lastSyncAt < SYNC_INTERVAL_MS) return Promise.resolve({ updated: false, reason: 'recently-checked' });

  const currentVersion = getCatalogInfo().version;
  lastSyncAt = Date.now();
  const pending = new Promise((resolve) => {
    try {
      wx.request({
        url: endpoint,
        method: 'GET',
        data: { since: currentVersion },
        header: { Accept: 'application/json' },
        timeout: 10000,
        success(response) {
          if (!response || response.statusCode < 200 || response.statusCode >= 300) {
            resolve({ updated: false, reason: 'http-error' });
            return;
          }
          let remote = response.data;
          if (typeof remote === 'string') {
            try { remote = JSON.parse(remote); } catch (error) {
              resolve({ updated: false, reason: 'invalid-json' });
              return;
            }
          }
          const validation = CatalogContract.validateCatalog(remote);
          if (!validation.valid) {
            resolve({ updated: false, reason: 'invalid-catalog', errors: validation.errors });
            return;
          }
          if (remote.version === currentVersion) {
            resolve({ updated: false, reason: 'current' });
            return;
          }
          try {
            applyRemoteCatalog(remote);
            resolve({ updated: true, version: remote.version });
          } catch (error) {
            resolve({ updated: false, reason: 'storage-error' });
          }
        },
        fail() { resolve({ updated: false, reason: 'network-error' }); }
      });
    } catch (error) {
      resolve({ updated: false, reason: 'request-error' });
    }
  });

  syncPromise = pending.then((result) => {
    syncPromise = null;
    return result;
  }, (error) => {
    syncPromise = null;
    throw error;
  });
  return syncPromise;
}

module.exports = { catalog, getRecords, saveRecords, getCupSizes, saveCupSizes, saveCatalog, deleteCatalogDrink, saveUserDrink, getCatalogInfo, syncCatalog };
