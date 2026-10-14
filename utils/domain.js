function createRecord(input, userId) {
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
  return {
    ...input,
    id: input.id || `record-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    userId,
    brandId: input.brandId || '',
    brandName: String(input.brandName || '').trim(),
    drinkId: input.drinkId || '',
    drinkName: String(input.drinkName).trim(),
    sizeMl: Number(input.sizeMl) || 0,
    sweetness: input.sweetness || '',
    ice: input.ice || '',
    toppings: Array.isArray(input.toppings) ? input.toppings : [],
    photo: input.photo || '',
    location: String(input.location || '').trim(),
    notes: String(input.notes || '').trim(),
    createdAt: input.createdAt || now,
    updatedAt: now
  };
}

function listRecords(records, userId, date) {
  return (records || [])
    .filter((record) => record.userId === userId && (!date || String(record.consumedAt).slice(0, 10) === date))
    .slice()
    .sort((a, b) => new Date(b.consumedAt).getTime() - new Date(a.consumedAt).getTime());
}

function searchBrands(brands, query) {
  const needle = String(query || '').trim().toLowerCase();
  return (brands || []).filter((brand) => brand.active !== false && (!needle || brand.name.toLowerCase().includes(needle)));
}

function searchDrinks(drinks, brandId, query) {
  const needle = String(query || '').trim().toLowerCase();
  return (drinks || []).filter((drink) => drink.active !== false
    && (!brandId || drink.brandId === brandId)
    && (!needle || drink.name.toLowerCase().includes(needle)));
}

function findDrink(drinks, drinkId) {
  return (drinks || []).find((drink) => drink.id === drinkId);
}

function createCustomDrink(input, userId) {
  if (!userId) throw new Error('A user is required to create a drink.');
  if (!input || !String(input.brandName || '').trim() || !String(input.drinkName || '').trim()) {
    throw new Error('A brand and drink name are required.');
  }
  return {
    id: `custom-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    brandId: '', brandName: String(input.brandName).trim(), name: String(input.drinkName).trim(),
    sizeMl: Number(input.sizeMl) || 0, active: true, custom: true, createdBy: userId,
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

function nutritionForRecord(record, drink) {
  const variants = (drink && drink.nutritionVariants) || [];
  const toppings = (record.toppings || []).slice().sort().join('|');
  const variant = variants.find((item) => Number(item.sizeMl) === Number(record.sizeMl)
    && (item.sweetness || '') === (record.sweetness || '')
    && (item.ice || '') === (record.ice || '')
    && (item.toppings || []).slice().sort().join('|') === toppings);
  if (!variant) return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
  const values = ['energyKcal', 'sugarG', 'caffeineMg'].map((key) => numericOrNull(variant[key]));
  if (!values.some((value) => value !== null && value >= 0)) return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
  const status = variant.sourceType === 'official' ? 'official' : 'estimated';
  return {
    status,
    label: status === 'official' ? '官方数据' : '估算值',
    energyKcal: values[0] !== null && values[0] >= 0 ? values[0] : null,
    sugarG: values[1] !== null && values[1] >= 0 ? values[1] : null,
    caffeineMg: values[2] !== null && values[2] >= 0 ? values[2] : null,
    source: variant.source || '',
    updatedAt: variant.updatedAt || ''
  };
}

function numericOrNull(value) {
  return value === '' || value === null || value === undefined || !Number.isFinite(Number(value)) ? null : Number(value);
}

function dailySummary(records, drinks, date, userId) {
  const rows = (records || []).filter((record) => String(record.consumedAt).slice(0, 10) === date
    && (!userId || record.userId === userId));
  const byId = new Map((drinks || []).map((drink) => [drink.id, drink]));
  const summary = { drinkCount: rows.length, energyKcal: 0, sugarG: 0, caffeineMg: 0, officialCount: 0, estimatedCount: 0, unavailableCount: 0,
    energyCount: 0, sugarCount: 0, caffeineCount: 0 };
  rows.forEach((record) => {
    const data = nutritionForRecord(record, byId.get(record.drinkId));
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

module.exports = { createRecord, listRecords, searchBrands, searchDrinks, findDrink, createCustomDrink, updateRecord, deleteRecord, nutritionForRecord, dailySummary };
