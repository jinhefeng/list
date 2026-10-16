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

// Intentional broad defaults for personal intake awareness, not brand recipe data.
const ROUGH_NUTRITION_PROFILES = {
  water: { label: '无糖水饮', baseEnergyKcal: 0, baseSugarG: 0, addedSugarG: 0, caffeineMg: 0 },
  blackTea: { label: '纯茶', baseEnergyKcal: 0, baseSugarG: 0, addedSugarG: 7, caffeineMg: 15 },
  fruitTea: { label: '果茶', baseEnergyKcal: 10, baseSugarG: 2, addedSugarG: 7, caffeineMg: 10 },
  milkTea: { label: '奶茶', baseEnergyKcal: 38, baseSugarG: 5, addedSugarG: 6, caffeineMg: 12 },
  blackCoffee: { label: '黑咖啡', baseEnergyKcal: 2, baseSugarG: 0, addedSugarG: 2, caffeineMg: 35 },
  milkCoffee: { label: '奶咖', baseEnergyKcal: 45, baseSugarG: 4, addedSugarG: 3, caffeineMg: 18 },
  smoothie: { label: '奶昔/冰沙', baseEnergyKcal: 50, baseSugarG: 7, addedSugarG: 4, caffeineMg: 0 },
  other: { label: '其他饮品', baseEnergyKcal: 25, baseSugarG: 3, addedSugarG: 5, caffeineMg: 10 }
};

function roughDrinkProfile(record, drink) {
  const name = String((record && record.drinkName) || (drink && drink.name) || '');
  const brandName = String((record && record.brandName) || (drink && drink.brandName) || '');
  const category = String((drink && drink.category) || '');
  const brandCategory = String((drink && drink.brandCategory) || '');
  const productText = `${name} ${category}`.toLowerCase();
  const coffeeContext = /(咖啡|coffee)/i.test(`${brandName} ${category} ${brandCategory}`);
  const explicitCoffee = /(咖啡|coffee|美式|冷萃|浓缩|espresso|americano|black coffee|摩卡|卡布奇诺|馥芮白|dirty)/i.test(productText);
  const coffeeLatte = /(拿铁|latte)/i.test(productText) && coffeeContext;

  if (/(矿泉水|纯净水|白开水|饮用水|无糖苏打|无糖气泡水)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.water;
  if (/(美式|冷萃|浓缩|espresso|americano|black coffee)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.blackCoffee;
  if (explicitCoffee || coffeeLatte) return ROUGH_NUTRITION_PROFILES.milkCoffee;
  if (/(冰沙|奶昔|果昔|沙冰|smoothie|酸奶)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.smoothie;
  if (/(奶茶|奶盖|奶绿|奶青|鲜奶|牛乳|厚乳|珍珠|波霸|芋泥|椰乳|椰奶|芝士)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.milkTea;
  if (/(果茶|柠檬|杨枝甘露|百香果|葡萄|青提|芒果|草莓|西瓜|蜜桃|桃子|橙子|凤梨|果汁)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.fruitTea;
  if (/(纯茶|原叶|乌龙|茉莉|龙井|红茶|绿茶|普洱|大红袍|岩茶|单丛|茶)/i.test(productText)) return ROUGH_NUTRITION_PROFILES.blackTea;
  if (coffeeContext) return ROUGH_NUTRITION_PROFILES.milkCoffee;
  return ROUGH_NUTRITION_PROFILES.other;
}

function roughSweetnessFactor(value) {
  const sweetness = String(value || '').trim().toLowerCase().replace(/\s/g, '');
  if (!sweetness) return 0.5;
  if (/(不另外加糖|不加糖|无糖|零糖|0糖)/.test(sweetness)) return 0;
  if (/(三分|3分|少糖|微糖)/.test(sweetness)) return 0.3;
  if (/(五分|5分|半糖)/.test(sweetness)) return 0.5;
  if (/(七分|7分)/.test(sweetness)) return 0.7;
  if (/(全糖|正常糖|标准糖)/.test(sweetness)) return 1;
  return 0.5;
}

function roughCupSizeMl(record, drink, cupSizes) {
  const knownSize = resolveCupSizeMl(record, cupSizes);
  if (knownSize !== null && knownSize > 0) return { sizeMl: knownSize, assumed: false };

  const cupType = String((record && record.cupType) || '').trim();
  const legacySizes = ((drink && drink.cupSizes) || [])
    .filter((item) => item && item.cupType === cupType)
    .map((item) => numericOrNull(item.sizeMl))
    .filter((size) => size !== null && size > 0);
  const uniqueLegacySizes = Array.from(new Set(legacySizes));
  if (uniqueLegacySizes.length === 1) return { sizeMl: uniqueLegacySizes[0], assumed: false };

  if (/(超大|特大|加大)/.test(cupType)) return { sizeMl: 750, assumed: true };
  if (/小/.test(cupType)) return { sizeMl: 350, assumed: true };
  if (/大/.test(cupType)) return { sizeMl: 650, assumed: true };
  if (/中/.test(cupType)) return { sizeMl: 500, assumed: true };
  return { sizeMl: 500, assumed: true };
}

function roughNutritionForRecord(record, drink, cupSizes) {
  const profile = roughDrinkProfile(record, drink);
  const capacity = roughCupSizeMl(record, drink, cupSizes);
  const multiplier = capacity.sizeMl / 100;
  const addedSugarG = profile.addedSugarG * roughSweetnessFactor(record && record.sweetness);
  return {
    energyKcal: (profile.baseEnergyKcal + addedSugarG * 4) * multiplier,
    sugarG: (profile.baseSugarG + addedSugarG) * multiplier,
    caffeineMg: profile.caffeineMg * multiplier,
    profileLabel: profile.label,
    sizeMl: capacity.sizeMl,
    sizeAssumed: capacity.assumed,
    sweetnessAssumed: !(record && record.sweetness)
  };
}

function nutritionForRecord(record, drink, cupSizes) {
  const snapshot = record && record.nutritionSnapshot;
  const keys = ['energyKcal', 'sugarG', 'caffeineMg'];
  const rough = roughNutritionForRecord(record, drink, cupSizes);
  if (snapshot && snapshot.complete) {
    const snapshotValues = keys.map((key) => numericOrNull(snapshot[key]));
    const roughUsed = snapshotValues.some((value) => value === null || value < 0);
    const hasSavedValues = snapshotValues.some((value) => value !== null && value >= 0);
    const values = snapshotValues.map((value, index) => value !== null && value >= 0 ? value : rough[keys[index]]);
    if (!values.some((value) => value !== null && value >= 0)) {
      return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
    }
    const status = roughUsed ? 'rough' : snapshot.sourceType === 'official' ? 'official' : 'estimated';
    return {
      status,
      label: status === 'official' ? '官方数据' : status === 'rough' ? (hasSavedValues ? '含粗估' : '粗估') : '估算值',
      energyKcal: values[0] !== null && values[0] >= 0 ? values[0] : null,
      sugarG: values[1] !== null && values[1] >= 0 ? values[1] : null,
      caffeineMg: values[2] !== null && values[2] >= 0 ? values[2] : null,
      source: roughUsed ? [snapshot.source || '', '按饮品类别、甜度和杯型粗估'].filter(Boolean).join('；') : (snapshot.source || ''),
      updatedAt: snapshot.updatedAt || '',
      roughEstimate: roughUsed,
      assumptions: roughUsed ? roughAssumptions(rough) : ''
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
  let roughUsed = false;
  const completed = used.map((item, index) => {
    if (item && item.value !== null && item.value >= 0) return item;
    roughUsed = true;
    return { value: rough[keys[index]], sourceType: 'rough', source: '按饮品类别、甜度和杯型粗估', updatedAt: '' };
  });
  if (!completed.some((item) => item && item.value !== null && item.value >= 0)) {
    return { status: 'unavailable', label: '暂无数据', energyKcal: null, sugarG: null, caffeineMg: null };
  }
  const status = roughUsed ? 'rough' : completed.some((item) => item && item.sourceType === 'estimated') ? 'estimated' : 'official';
  return {
    status,
    label: status === 'official' ? '官方数据' : status === 'rough'
      ? (completed.some((item) => item && item.sourceType !== 'rough') ? '含粗估' : '粗估') : '估算值',
    energyKcal: completed[0] && completed[0].value !== null ? completed[0].value : null,
    sugarG: completed[1] && completed[1].value !== null ? completed[1].value : null,
    caffeineMg: completed[2] && completed[2].value !== null ? completed[2].value : null,
    source: Array.from(new Set(completed.filter(Boolean).map((item) => item.source).filter(Boolean))).join('；'),
    updatedAt: (completed.filter(Boolean).map((item) => item.updatedAt).filter(Boolean).sort().slice(-1)[0]) || '',
    roughEstimate: roughUsed,
    assumptions: roughUsed ? roughAssumptions(rough) : ''
  };
}

function roughAssumptions(rough) {
  const sizeLabel = rough.sizeAssumed ? `容量按约 ${rough.sizeMl} ml` : `${rough.sizeMl} ml`;
  const sweetnessLabel = rough.sweetnessAssumed ? '甜度未记录，按五分糖' : '按记录甜度';
  return `${rough.profileLabel}类，${sizeLabel}，${sweetnessLabel}`;
}

function formatNutritionAmounts(nutrition) {
  if (!nutrition) return '';
  const approximate = nutrition.status === 'rough' || nutrition.status === 'estimated';
  const roundTo = (value, step) => Math.round(Number(value) / step) * step;
  const parts = [];
  if (nutrition.energyKcal !== null && nutrition.energyKcal !== undefined) {
    parts.push(`${roundTo(nutrition.energyKcal, approximate ? 10 : 1)} kcal`);
  }
  if (nutrition.sugarG !== null && nutrition.sugarG !== undefined) {
    const sugar = approximate ? roundTo(nutrition.sugarG, 5) : Math.round(nutrition.sugarG * 10) / 10;
    parts.push(`${sugar}g 糖`);
  }
  if (nutrition.caffeineMg !== null && nutrition.caffeineMg !== undefined) {
    parts.push(`${roundTo(nutrition.caffeineMg, approximate ? 10 : 1)}mg 咖啡因`);
  }
  if (!parts.length) return '暂无数据';
  return parts.join(' · ');
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
  const summary = { drinkCount: rows.length, energyKcal: 0, sugarG: 0, caffeineMg: 0, officialCount: 0, estimatedCount: 0, roughCount: 0, unavailableCount: 0,
    energyCount: 0, sugarCount: 0, caffeineCount: 0 };
  rows.forEach((record) => {
    const data = nutritionForRecord(record, byId.get(record.drinkId), cupSizes);
    if (data.status === 'official') summary.officialCount += 1;
    else if (data.status === 'estimated') summary.estimatedCount += 1;
    else if (data.status === 'rough') summary.roughCount += 1;
    else summary.unavailableCount += 1;
    ['energyKcal', 'sugarG', 'caffeineMg'].forEach((key) => {
      if (data[key] !== null) {
        summary[key] += data[key];
        summary[`${key.replace('Kcal', '').replace('G', '').replace('Mg', '')}Count`] += 1;
      }
    });
  });
  const hasRoughValues = summary.roughCount > 0 || summary.estimatedCount > 0;
  summary.energyLabel = summary.energyCount
    ? String(hasRoughValues ? Math.round(summary.energyKcal / 10) * 10 : Math.round(summary.energyKcal)) : '—';
  summary.sugarLabel = summary.sugarCount
    ? `${hasRoughValues ? Math.round(summary.sugarG / 5) * 5 : Math.round(summary.sugarG * 10) / 10}g` : '—';
  summary.caffeineLabel = summary.caffeineCount
    ? `${hasRoughValues ? Math.round(summary.caffeineMg / 10) * 10 : Math.round(summary.caffeineMg)}mg` : '—';
  return summary;
}

module.exports = { createRecord, createMealRecord, isMealRecord, isDrinkRecord, listRecords, searchBrands, searchDrinks, findDrink, formatCupLabel, createCustomDrink, updateRecord, deleteRecord, resolveTemperatureIce, formatServingLabel, resolveCupSizeMl, nutritionForRecord, formatNutritionAmounts, dailySummary };
