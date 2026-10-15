function createRecord(input, userId) {
  if (input && input.type === 'meal') return createMealRecord(input, userId);
  if (!userId) throw new Error('A user is required to create a drink record.');
  if (input && Array.isArray(input.drinks) && input.drinks.length !== 1) {
    throw new Error('A record must contain exactly one drink.');
  }
  if (!input || !input.drinkName || !String(input.drinkName).trim()) {
    throw new Error('A drink is required.');
  }
  if (!input.consumedAt) throw new Error('A consumption time is required.');
  if (!Number.isFinite(new Date(input.consumedAt).getTime())) throw new Error('A valid consumption time is required.');
  if (Number(input.sizeMl) < 0) throw new Error('Drink size cannot be negative.');
  const now = new Date().toISOString();
  const coordinate = (value) => {
    if (value === '' || value === null || value === undefined) return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  };
  return {
    ...input,
    type: 'drink',
    id: input.id || `record-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    userId,
    brandId: input.brandId || '',
    brandName: String(input.brandName || '').trim(),
    drinkId: input.drinkId || '',
    drinkName: String(input.drinkName).trim(),
    sizeMl: Number(input.sizeMl) || 0,
    cupType: String(input.cupType || ''),
    sweetness: input.sweetness || '',
    servingOption: String(input.servingOption || ''),
    temperature: input.temperature || '',
    ice: input.ice || '',
    toppings: Array.isArray(input.toppings) ? input.toppings : [],
    photo: input.photo || '',
    photoThumbnail: input.photoThumbnail || '',
    location: String(input.location || '').trim(),
    locationAddress: String(input.locationAddress || '').trim(),
    locationLatitude: coordinate(input.locationLatitude),
    locationLongitude: coordinate(input.locationLongitude),
    notes: String(input.notes || '').trim(),
    userName: String(input.userName || '我').trim(),
    createdAt: input.createdAt || now,
    updatedAt: now
  };
}

function createMealRecord(input, userId) {
  if (!userId) throw new Error('A user is required to create a meal record.');
  if (!input || !input.consumedAt || !Number.isFinite(new Date(input.consumedAt).getTime())) {
    throw new Error('A valid meal time is required.');
  }
  const dishes = (Array.isArray(input.dishes) ? input.dishes : [])
    .map((dish) => ({
      id: dish.id || `dish-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      name: String(dish.name || '').trim(),
      photo: dish.photo || '',
      photoThumbnail: dish.photoThumbnail || dish.photo || ''
    }))
    .filter((dish) => dish.name);
  if (!dishes.length) throw new Error('At least one named dish is required.');
  const coordinate = (value) => {
    if (value === '' || value === null || value === undefined) return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  };
  const now = new Date().toISOString();
  return {
    ...input,
    id: input.id || `record-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    type: 'meal',
    userId,
    storeName: String(input.storeName || '').trim(),
    locationAddress: String(input.locationAddress || '').trim(),
    locationLatitude: coordinate(input.locationLatitude),
    locationLongitude: coordinate(input.locationLongitude),
    dishes,
    notes: String(input.notes || '').trim(),
    userName: String(input.userName || '我').trim(),
    createdAt: input.createdAt || now,
    updatedAt: now
  };
}

function isMealRecord(record) { return !!record && record.type === 'meal'; }
function isDrinkRecord(record) { return !record || !record.type || record.type === 'drink'; }

function listRecords(records, userId, date) {
  return (records || [])
    .filter((record) => (!userId || record.userId === userId) && (!date || String(record.consumedAt).slice(0, 10) === date))
    .slice()
    .sort((a, b) => new Date(b.consumedAt).getTime() - new Date(a.consumedAt).getTime());
}

function searchBrands(brands, query) {
  const needle = String(query || '').trim().toLowerCase();
  return (brands || []).filter((brand) => brand.active !== false && (!needle
    || [brand.name].concat(Array.isArray(brand.aliases) ? brand.aliases : []).some((value) => String(value || '').toLowerCase().includes(needle))));
}

function searchDrinks(drinks, brandId, query) {
  const needle = String(query || '').trim().toLowerCase();
  return (drinks || []).filter((drink) => drink.active !== false
    && (!brandId || drink.brandId === brandId)
    && (!needle || [drink.name].concat(Array.isArray(drink.aliases) ? drink.aliases : []).some((value) => String(value || '').toLowerCase().includes(needle))));
}

function findDrink(drinks, drinkId) {
  return (drinks || []).find((drink) => drink.id === drinkId);
}

function formatCupLabel(record) {
  const cupType = String(record && record.cupType || '').trim();
  if (cupType) return cupType;
  return '杯型未记录';
}

function createCustomDrink(input, userId) {
  if (!userId) throw new Error('A user is required to create a drink.');
  if (!input || !String(input.brandName || '').trim() || !String(input.drinkName || '').trim()) {
    throw new Error('A brand and drink name are required.');
  }
  return {
    id: `custom-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    brandId: '', brandName: String(input.brandName).trim(), name: String(input.drinkName).trim(),
    active: true, custom: true, createdBy: userId,
    source: '用户自定义', sourceType: 'user', updatedAt: new Date().toISOString(), nutritionVariants: []
  };
}

function updateRecord(records, recordId, userId, changes) {
  let found = false;
  const updated = (records || []).map((record) => {
    if (record.id !== recordId || record.userId !== userId) return record;
    found = true;
    return createRecord({ ...record, ...changes, id: record.id, createdAt: record.createdAt }, userId);
  });
  if (!found) throw new Error('Record not found.');
  return updated;
}

function deleteRecord(records, recordId, userId) {
  const exists = (records || []).some((record) => record.id === recordId && record.userId === userId);
  if (!exists) throw new Error('Record not found.');
  return records.filter((record) => !(record.id === recordId && record.userId === userId));
}

function nutritionForRecord(record, drink, cupSizes) {
  const snapshot = record && record.nutritionSnapshot;
  const keys = ['energyKcal', 'sugarG', 'caffeineMg'];
  if (snapshot && snapshot.complete) {
    const values = keys.map((key) => numericOrNull(snapshot[key]));
    if (!values.some((value) => value !== null && value >= 0)) {
      return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
    }
    const status = snapshot.sourceType === 'official' ? 'official' : 'estimated';
    return {
      status,
      label: status === 'official' ? '官方数据' : '估算值',
      energyKcal: values[0] !== null && values[0] >= 0 ? values[0] : null,
      sugarG: values[1] !== null && values[1] >= 0 ? values[1] : null,
      caffeineMg: values[2] !== null && values[2] >= 0 ? values[2] : null,
      source: snapshot.source || '',
      updatedAt: snapshot.updatedAt || ''
    };
  }
  const variants = (drink && drink.nutritionVariants) || [];
  const toppings = (record.toppings || []).slice().sort().join('|');
  const serving = resolveTemperatureIce(record);
  const resolvedSizeMl = resolveCupSizeMl(record, cupSizes);
  const matchesSize = (item) => {
    const itemSize = numericOrNull(item.sizeMl);
    if (resolvedSizeMl !== null) return itemSize === resolvedSizeMl
      && (!item.cupType || !record.cupType || item.cupType === record.cupType);
    return (!itemSize || itemSize <= 0) && !!record.cupType && item.cupType === record.cupType;
  };
  const variant = variants.find((item) => matchesSize(item)
    && (item.sweetness || '') === (record.sweetness || '')
    && resolveTemperatureIce(item).temperature === serving.temperature
    && resolveTemperatureIce(item).ice === serving.ice
    && (item.toppings || []).slice().sort().join('|') === toppings)
    || variants.find((item) => matchesSize(item)
      && !item.sweetness && !item.servingOption && !item.temperature && !item.ice
      && !(Array.isArray(item.toppings) && item.toppings.length));
  const perUnit = nutritionFromUnit(record, drink && drink.nutritionPerUnit, cupSizes);
  const used = keys.map((key) => {
    const variantValue = variant && numericOrNull(variant[key]);
    if (variantValue !== null && variantValue >= 0 && variant.sourceType === 'official') {
      return { value: variantValue, sourceType: 'official', source: variant.source || '', updatedAt: variant.updatedAt || '' };
    }
    const snapshotValue = snapshot && numericOrNull(snapshot[key]);
    if (snapshotValue !== null && snapshotValue >= 0) {
      return { value: snapshotValue, sourceType: snapshot.sourceType === 'official' ? 'official' : 'estimated', source: snapshot.source || '', updatedAt: snapshot.updatedAt || '' };
    }
    if (variantValue !== null && variantValue >= 0) {
      return { value: variantValue, sourceType: variant.sourceType === 'official' ? 'official' : 'estimated', source: variant.source || '', updatedAt: variant.updatedAt || '' };
    }
    return perUnit && perUnit[key] !== null ? perUnit[key] : null;
  });
  if (!used.some((item) => item && item.value !== null && item.value >= 0)) {
    return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
  }
  const status = used.some((item) => item && item.sourceType === 'estimated') ? 'estimated' : 'official';
  return {
    status,
    label: status === 'official' ? '官方数据' : '估算值',
    energyKcal: used[0] && used[0].value !== null ? used[0].value : null,
    sugarG: used[1] && used[1].value !== null ? used[1].value : null,
    caffeineMg: used[2] && used[2].value !== null ? used[2].value : null,
    source: Array.from(new Set(used.filter(Boolean).map((item) => item.source).filter(Boolean))).join('；'),
    updatedAt: (used.filter(Boolean).map((item) => item.updatedAt).filter(Boolean).sort().slice(-1)[0]) || ''
  };
}

function resolveCupSizeMl(record, cupSizes) {
  const recordedSize = numericOrNull(record && record.sizeMl);
  if (recordedSize !== null && recordedSize > 0) return recordedSize;
  const cupType = String(record && record.cupType || '').trim();
  if (!cupType) return null;
  const mappedSizes = Array.from(new Set(((cupSizes && cupSizes.cupSizes) || cupSizes || [])
    .filter((item) => item && String(item.cupType || '').trim() === cupType)
    .map((item) => numericOrNull(item.sizeMl))
    .filter((size) => size !== null && size > 0)));
  return mappedSizes.length === 1 ? mappedSizes[0] : null;
}

function nutritionFromUnit(record, nutrition, cupSizes) {
  if (!nutrition || typeof nutrition !== 'object') return null;
  const amount = numericOrNull(nutrition.amount);
  if (amount === null || amount <= 0) return null;
  let multiplier;
  if (nutrition.unit === 'ml') {
    const sizeMl = resolveCupSizeMl(record, cupSizes);
    if (sizeMl === null || sizeMl <= 0) return null;
    multiplier = sizeMl / amount;
  } else if (nutrition.unit === '杯') {
    multiplier = 1 / amount;
  } else {
    return null;
  }
  const sourceType = nutrition.sourceType === 'official' ? 'official' : 'estimated';
  const values = {};
  ['energyKcal', 'sugarG', 'caffeineMg'].forEach((key) => {
    const value = numericOrNull(nutrition[key]);
    values[key] = value !== null && value >= 0
      ? { value: value * multiplier, sourceType, source: nutrition.source || '', updatedAt: nutrition.updatedAt || '' }
      : null;
  });
  return values;
}

function numericOrNull(value) {
  return value === '' || value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Number(value);
}

function resolveTemperatureIce(input) {
  const servingOption = input.servingOption || '';
  if (servingOption) {
    if (['常温', '热', '热饮'].includes(servingOption)) return { temperature: servingOption === '热' ? '热饮' : servingOption, ice: '' };
    if (servingOption === '冰饮') return { temperature: '冰饮', ice: '' };
    if (servingOption.includes('冰')) return { temperature: '冰饮', ice: servingOption };
    return { temperature: servingOption, ice: '' };
  }
  const temperature = input.temperature || '';
  const ice = input.ice || '';
  const legacyTemperature = !temperature && ['常温', '热', '热饮'].includes(ice);
  return {
    temperature: temperature || (legacyTemperature ? ice : (ice ? '冰饮' : '')),
    ice: legacyTemperature ? '' : ice
  };
}

function formatServingLabel(input) {
  const record = input || {};
  const serving = resolveTemperatureIce(record);
  const option = String(record.servingOption || '').trim();
  if (option) return option === '热' ? '热饮' : option;
  if (serving.temperature === '冰饮') return serving.ice || '冰饮';
  return serving.temperature || '';
}

function dailySummary(records, drinks, date, userId, cupSizes) {
  const rows = (records || []).filter((record) => String(record.consumedAt).slice(0, 10) === date
    && (!userId || record.userId === userId) && isDrinkRecord(record));
  const byId = new Map((drinks || []).map((drink) => [drink.id, drink]));
  const summary = { drinkCount: rows.length, energyKcal: 0, sugarG: 0, caffeineMg: 0, officialCount: 0, estimatedCount: 0, unavailableCount: 0,
    energyCount: 0, sugarCount: 0, caffeineCount: 0 };
  rows.forEach((record) => {
    const data = nutritionForRecord(record, byId.get(record.drinkId), cupSizes);
    if (data.status === 'official') summary.officialCount += 1;
    else if (data.status === 'estimated') summary.estimatedCount += 1;
    else summary.unavailableCount += 1;
    ['energyKcal', 'sugarG', 'caffeineMg'].forEach((key) => {
      if (data[key] !== null) {
        summary[key] += data[key];
        summary[`${key.replace('Kcal', '').replace('G', '').replace('Mg', '')}Count`] += 1;
      }
    });
  });
  summary.energyLabel = summary.energyCount ? String(Math.round(summary.energyKcal)) : '—';
  summary.sugarLabel = summary.sugarCount ? `${Math.round(summary.sugarG * 10) / 10}g` : '—';
  summary.caffeineLabel = summary.caffeineCount ? `${Math.round(summary.caffeineMg)}mg` : '—';
  return summary;
}

module.exports = { createRecord, createMealRecord, isMealRecord, isDrinkRecord, listRecords, searchBrands, searchDrinks, findDrink, formatCupLabel, createCustomDrink, updateRecord, deleteRecord, resolveTemperatureIce, formatServingLabel, resolveCupSizeMl, nutritionForRecord, dailySummary };
