const seed = require('../data/catalog');

const KEYS = { records: 'drink-log:records', brands: 'drink-log:brands', drinks: 'drink-log:drinks' };

function read(key, fallback) {
  const value = wx.getStorageSync(key);
  return value === '' || value === undefined || value === null ? fallback : value;
}

function catalog() {
  const brands = read(KEYS.brands, seed.brands);
  const drinks = read(KEYS.drinks, seed.drinks);
  if (read(KEYS.brands, null) === null) wx.setStorageSync(KEYS.brands, brands);
  if (read(KEYS.drinks, null) === null) wx.setStorageSync(KEYS.drinks, drinks);
  return { brands, drinks };
}

function getRecords() { return read(KEYS.records, []); }
function saveRecords(records) { wx.setStorageSync(KEYS.records, records); }
function saveCatalog(data) {
  wx.setStorageSync(KEYS.brands, data.brands);
  wx.setStorageSync(KEYS.drinks, data.drinks);
}

module.exports = { catalog, getRecords, saveRecords, saveCatalog };
