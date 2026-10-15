const MENU_STATUSES = ['verified', 'pending', 'unavailable'];

function validateCatalog(catalog) {
  const errors = [];
  if (!catalog || typeof catalog !== 'object' || Array.isArray(catalog)) {
    return { valid: false, errors: ['catalog must be an object'] };
  }
  if (!String(catalog.version || '').trim()) errors.push('version is required');
  if (!String(catalog.generatedAt || '').trim()) errors.push('generatedAt is required');
  if (!Array.isArray(catalog.brands)) errors.push('brands must be an array');
  if (!Array.isArray(catalog.drinks)) errors.push('drinks must be an array');
  if (errors.length) return { valid: false, errors };

  const brandIds = new Set();
  catalog.brands.forEach((brand, index) => {
    const label = `brands[${index}]`;
    if (!brand || typeof brand !== 'object') {
      errors.push(`${label} must be an object`);
      return;
    }
    if (typeof brand.id !== 'string' || !brand.id.trim()) errors.push(`${label}.id is required`);
    else if (brandIds.has(brand.id)) errors.push(`${label}.id duplicates ${brand.id}`);
    else brandIds.add(brand.id);
    if (typeof brand.name !== 'string' || !brand.name.trim()) errors.push(`${label}.name is required`);
    if (!Array.isArray(brand.aliases)) errors.push(`${label}.aliases must be an array`);
    if (!MENU_STATUSES.includes(brand.status)) errors.push(`${label}.status is invalid`);
    if (typeof brand.active !== 'boolean') errors.push(`${label}.active must be a boolean`);
  });

  const drinkIds = new Set();
  catalog.drinks.forEach((drink, index) => {
    const label = `drinks[${index}]`;
    if (!drink || typeof drink !== 'object') {
      errors.push(`${label} must be an object`);
      return;
    }
    if (typeof drink.id !== 'string' || !drink.id.trim()) errors.push(`${label}.id is required`);
    else if (drinkIds.has(drink.id)) errors.push(`${label}.id duplicates ${drink.id}`);
    else drinkIds.add(drink.id);
    if (typeof drink.name !== 'string' || !drink.name.trim()) errors.push(`${label}.name is required`);
    if (!brandIds.has(drink.brandId)) errors.push(`${label}.brandId does not match a brand`);
    if (!Array.isArray(drink.aliases)) errors.push(`${label}.aliases must be an array`);
    if (!MENU_STATUSES.includes(drink.status)) errors.push(`${label}.status is invalid`);
    if (typeof drink.active !== 'boolean') errors.push(`${label}.active must be a boolean`);
    ['cupTypes', 'cupSizes', 'sizesMl', 'sweetnessOptions', 'servingOptions', 'nutritionVariants', 'menuEntries'].forEach((key) => {
      if (!Array.isArray(drink[key])) errors.push(`${label}.${key} must be an array`);
    });
    if (drink.nutritionPerUnit !== undefined && drink.nutritionPerUnit !== null) {
      const unitNutrition = drink.nutritionPerUnit;
      if (!unitNutrition || typeof unitNutrition !== 'object' || Array.isArray(unitNutrition)) {
        errors.push(`${label}.nutritionPerUnit must be an object`);
      } else {
        if (!Number.isFinite(Number(unitNutrition.amount)) || Number(unitNutrition.amount) <= 0) errors.push(`${label}.nutritionPerUnit.amount must be positive`);
        if (!['ml', '杯'].includes(unitNutrition.unit)) errors.push(`${label}.nutritionPerUnit.unit is invalid`);
        ['sugarG', 'energyKcal', 'caffeineMg'].forEach((key) => {
          const value = unitNutrition[key];
          if (value !== null && value !== '' && value !== undefined && (!Number.isFinite(Number(value)) || Number(value) < 0)) {
            errors.push(`${label}.nutritionPerUnit.${key} must be null or a non-negative number`);
          }
        });
        if (unitNutrition.sourceType && !['official', 'estimated'].includes(unitNutrition.sourceType)) {
          errors.push(`${label}.nutritionPerUnit.sourceType is invalid`);
        }
        const hasNutrition = ['sugarG', 'energyKcal', 'caffeineMg'].some((key) => unitNutrition[key] !== null && unitNutrition[key] !== '' && unitNutrition[key] !== undefined);
        if (hasNutrition && unitNutrition.sourceType === 'official' && !String(unitNutrition.source || '').trim()) {
          errors.push(`${label}.nutritionPerUnit official data needs a source`);
        }
      }
    }
    (Array.isArray(drink.cupSizes) ? drink.cupSizes : []).forEach((item, itemIndex) => {
      if (!item || typeof item !== 'object' || typeof item.cupType !== 'string' || !item.cupType.trim()) {
        errors.push(`${label}.cupSizes[${itemIndex}] needs a cupType`);
      } else if (item.sizeMl !== undefined && (!Number.isInteger(Number(item.sizeMl)) || Number(item.sizeMl) <= 0)) {
        errors.push(`${label}.cupSizes[${itemIndex}].sizeMl must be a positive whole number`);
      }
    });
    (Array.isArray(drink.menuEntries) ? drink.menuEntries : []).forEach((entry, entryIndex) => {
      if (!entry || typeof entry !== 'object') errors.push(`${label}.menuEntries[${entryIndex}] must be an object`);
      else {
        if (!['brand', 'city', 'store'].includes(entry.scope)) errors.push(`${label}.menuEntries[${entryIndex}].scope is invalid`);
        if (!MENU_STATUSES.includes(entry.status)) errors.push(`${label}.menuEntries[${entryIndex}].status is invalid`);
        ['cupTypes', 'cupSizes', 'sizesMl', 'sweetnessOptions', 'servingOptions'].forEach((key) => {
          if (!Array.isArray(entry[key])) errors.push(`${label}.menuEntries[${entryIndex}].${key} must be an array`);
        });
        if (!['official_brand', 'public_menu', 'authorized_platform', 'manual_platform', 'user_report', 'pending'].includes(entry.sourceType)) {
          errors.push(`${label}.menuEntries[${entryIndex}].sourceType is invalid`);
        }
        if (entry.sourceType === 'public_menu' && entry.status !== 'pending') {
          errors.push(`${label}.menuEntries[${entryIndex}] public menu references must remain pending until confirmed in the local platform menu`);
        }
        if (entry.status !== 'pending' && entry.sourceType === 'pending') {
          errors.push(`${label}.menuEntries[${entryIndex}] needs a source_type for a non-pending status`);
        }
        if (entry.status === 'pending' && entry.sourceType !== 'pending' && !entry.sourceName && !entry.sourceUrl) {
          errors.push(`${label}.menuEntries[${entryIndex}] needs a source or pending source_type`);
        }
        if (entry.status !== 'pending' && (!/^\d{4}-\d{2}-\d{2}$/.test(entry.checkedAt || '') || (!entry.sourceName && !entry.sourceUrl))) {
          errors.push(`${label}.menuEntries[${entryIndex}] needs a source and checkedAt for a non-pending status`);
        }
        if (entry.scope === 'store' && !entry.city) errors.push(`${label}.menuEntries[${entryIndex}] needs a city for store scope`);
      }
    });
  });

  return { valid: errors.length === 0, errors };
}

module.exports = { MENU_STATUSES, validateCatalog };
