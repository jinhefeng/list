const Store = require('../../utils/store');
const PAGE_SIZE = 30;

function parseOptionalNumber(value) {
  const text = String(value === undefined || value === null ? '' : value).trim();
  if (!text) return { valid: true, value: null };
  const number = Number(text);
  return { valid: Number.isFinite(number) && number >= 0, value: number };
}

function unique(values) {
  return Array.from(new Set(values.map((value) => String(value || '').trim()).filter(Boolean)));
}

function dateStamp() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function preparedDrink(drink) {
  const nutrition = drink.nutritionPerUnit || {};
  const unitSugar = nutrition.sugarG === null || nutrition.sugarG === undefined || nutrition.sugarG === ''
    ? '' : `${nutrition.sugarG} g / ${nutrition.amount || 100}${nutrition.unit || 'ml'}`;
  const exactSugarValues = (Array.isArray(drink.nutritionVariants) ? drink.nutritionVariants : [])
    .filter((variant) => variant.sugarG !== null && variant.sugarG !== undefined && variant.sugarG !== '')
    .map((variant) => `${variant.cupType || '规格'} ${variant.sugarG}g`);
  const statusLabels = { verified: '已核验', pending: '待核验', unavailable: '暂不供应' };
  return {
    ...drink,
    displayBrand: drink.brandName || '自定义品牌',
    displayCategory: drink.category || '未分类',
    sugarLabel: unitSugar ? `基准 ${unitSugar}` : (exactSugarValues.length ? `规格数据 ${exactSugarValues.slice(0, 2).join(' · ')}` : '单位含糖量待补'),
    menuStatusLabel: statusLabels[drink.status] || '待核验',
    activeLabel: drink.active === false ? '已隐藏' : '使用中',
    activeClass: drink.active === false ? 'inactive' : ''
  };
}

function newForm(brands, brandIndex) {
  const selectedBrand = brandIndex > 0 ? brands[brandIndex - 1] : null;
  return {
    id: '', brandId: selectedBrand ? selectedBrand.id : '', brandName: selectedBrand ? selectedBrand.name : '',
    brandIndex: Number(brandIndex) || 0, customBrand: !selectedBrand, name: '', category: selectedBrand && selectedBrand.category || '',
    aliasesText: '',
    sugarG: '', energyKcal: '', caffeineMg: '', nutritionSourceType: 'estimated', nutritionSourceTypeIndex: 0,
    nutritionSource: '用户维护', unitNutritionEdited: false, legacyCupNutrition: false, legacyNutritionLabel: '',
    active: true, menuStatusLabel: '新增条目默认待核验'
  };
}

Page({
  data: {
    visibleDrinks: [], brands: [], brandOptions: [],
    brandFilterOptions: ['全部品牌'], categoryFilterOptions: ['全部分类'],
    brandFilterIndex: 0, categoryFilterIndex: 0, query: '', totalCount: 0, matchedCount: 0,
    displayCount: 0, canLoadMore: false, remainingCount: 0, hasSearchContext: false,
    showAllCatalog: false, globalCupSizes: [], showCupSettings: false,
    showEditor: false, editingIsNew: false,
    sourceTypeOptions: ['估算值', '官方数据'],
    form: newForm([], 0)
  },

  onLoad() { this.refresh(); },
  onShow() { this.refresh(); },

  refresh(options) {
    const preservePagination = !!(options && options.preservePagination);
    const catalog = Store.catalog();
    const brands = (catalog.brands || []).slice();
    const allDrinks = (catalog.drinks || []).map(preparedDrink);
    const globalCupSizes = Store.getCupSizes();
    this.allDrinks = allDrinks;
    const brandNames = unique(brands.map((brand) => brand.name).concat(allDrinks.map((drink) => drink.brandName)));
    const categoryNames = unique(allDrinks.map((drink) => drink.category).concat(brands.map((brand) => brand.category)));
    const brandFilterOptions = ['全部品牌'].concat(brandNames);
    const categoryFilterOptions = ['全部分类'].concat(categoryNames);
    const brandFilterIndex = Math.min(this.data.brandFilterIndex || 0, brandFilterOptions.length - 1);
    const categoryFilterIndex = Math.min(this.data.categoryFilterIndex || 0, categoryFilterOptions.length - 1);
    this.setData({
      brands,
      brandOptions: ['自定义品牌 / 其他'].concat(brands.map((brand) => brand.name)),
      brandFilterOptions,
      categoryFilterOptions,
      globalCupSizes,
      brandFilterIndex,
      categoryFilterIndex,
      totalCount: allDrinks.length
    });
    this.applyFilters({ brandFilterIndex, categoryFilterIndex, showAllCatalog: this.data.showAllCatalog,
      resetPagination: !preservePagination, preservePagination });
  },

  applyFilters(changes) {
    const next = changes || {};
    const query = next.query === undefined ? this.data.query : next.query;
    const brandFilterIndex = next.brandFilterIndex === undefined ? this.data.brandFilterIndex : next.brandFilterIndex;
    const categoryFilterIndex = next.categoryFilterIndex === undefined ? this.data.categoryFilterIndex : next.categoryFilterIndex;
    const filterChanged = next.query !== undefined || next.brandFilterIndex !== undefined || next.categoryFilterIndex !== undefined;
    const showAllCatalog = next.showAllCatalog === undefined
      ? (filterChanged ? false : !!this.data.showAllCatalog) : !!next.showAllCatalog;
    const brandName = this.data.brandFilterOptions[brandFilterIndex] || '全部品牌';
    const categoryName = this.data.categoryFilterOptions[categoryFilterIndex] || '全部分类';
    const needle = String(query || '').trim().toLowerCase();
    const hasSearchContext = showAllCatalog || !!needle || brandFilterIndex > 0 || categoryFilterIndex > 0;
    const matchedDrinks = hasSearchContext ? (this.allDrinks || []).filter((drink) => {
      const matchesBrand = brandName === '全部品牌' || drink.displayBrand === brandName;
      const matchesCategory = categoryName === '全部分类' || drink.displayCategory === categoryName;
      const searchFields = [drink.name, drink.brandName, drink.category].concat(Array.isArray(drink.aliases) ? drink.aliases : []);
      const matchesQuery = !needle || searchFields.some((value) => String(value || '').toLowerCase().includes(needle));
      return matchesBrand && matchesCategory && matchesQuery;
    }) : [];
    const shouldReset = !next.preservePagination && (!!next.resetPagination || next.showAllCatalog !== undefined || next.query !== undefined
      || next.brandFilterIndex !== undefined || next.categoryFilterIndex !== undefined);
    const requestedCount = shouldReset ? PAGE_SIZE : Math.max(PAGE_SIZE, this.data.displayCount || PAGE_SIZE);
    const displayCount = Math.min(requestedCount, matchedDrinks.length);
    this.matchedDrinks = matchedDrinks;
    this.setData({ query, brandFilterIndex, categoryFilterIndex, showAllCatalog, hasSearchContext, matchedCount: matchedDrinks.length,
      displayCount, visibleDrinks: matchedDrinks.slice(0, displayCount), canLoadMore: displayCount < matchedDrinks.length,
      remainingCount: Math.max(0, matchedDrinks.length - displayCount) });
  },

  onReachBottom() { this.loadMore(); },

  loadMore() {
    if (!this.data.canLoadMore) return;
    const matchedDrinks = this.matchedDrinks || [];
    const displayCount = Math.min(this.data.matchedCount, this.data.displayCount + PAGE_SIZE);
    this.setData({ displayCount, visibleDrinks: matchedDrinks.slice(0, displayCount),
      canLoadMore: displayCount < matchedDrinks.length,
      remainingCount: Math.max(0, matchedDrinks.length - displayCount) });
  },

  onSearch(event) { this.applyFilters({ query: event.detail.value }); },
  onBrandFilterChange(event) { this.applyFilters({ brandFilterIndex: Number(event.detail.value) || 0 }); },
  onCategoryFilterChange(event) { this.applyFilters({ categoryFilterIndex: Number(event.detail.value) || 0 }); },
  showAllDrinks() {
    this.applyFilters({ query: '', brandFilterIndex: 0, categoryFilterIndex: 0, showAllCatalog: true, resetPagination: true });
  },

  toggleCupSettings() { this.setData({ showCupSettings: !this.data.showCupSettings }); },

  addGlobalCupType() {
    this.setData({ globalCupSizes: (this.data.globalCupSizes || []).concat([{ cupType: '', sizeMl: '' }]) });
  },

  onGlobalCupSizeInput(event) {
    const index = Number(event.currentTarget.dataset.index);
    const field = event.currentTarget.dataset.field;
    if (!Number.isInteger(index) || !['cupType', 'sizeMl'].includes(field)) return;
    const globalCupSizes = (this.data.globalCupSizes || []).map((item) => ({ ...item }));
    if (!globalCupSizes[index]) return;
    globalCupSizes[index][field] = event.detail.value;
    this.setData({ globalCupSizes });
  },

  removeGlobalCupType(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (!Number.isInteger(index)) return;
    this.setData({ globalCupSizes: (this.data.globalCupSizes || []).filter((item, itemIndex) => itemIndex !== index) });
  },

  saveGlobalCupSizes() {
    const rows = (this.data.globalCupSizes || []).map((item) => ({
      cupType: String(item.cupType || '').trim(), sizeText: String(item.sizeMl === undefined ? '' : item.sizeMl).trim()
    })).filter((item) => item.cupType || item.sizeText);
    if (!rows.length || rows.some((item) => !item.cupType)) {
      wx.showToast({ title: '请至少保留一个完整的杯型名称', icon: 'none' });
      return;
    }
    if (rows.some((item) => item.sizeText && (!Number.isInteger(Number(item.sizeText)) || Number(item.sizeText) <= 0))) {
      wx.showToast({ title: '容量请填写大于 0 的整数，暂不设置可留空', icon: 'none' });
      return;
    }
    const names = rows.map((item) => item.cupType.toLowerCase());
    if (new Set(names).size !== names.length) {
      wx.showToast({ title: '杯型名称不能重复', icon: 'none' });
      return;
    }
    const cupSizes = Store.saveCupSizes(rows.map((item) => ({ cupType: item.cupType, sizeMl: item.sizeText ? Number(item.sizeText) : '' })));
    this.setData({ globalCupSizes: cupSizes });
    wx.showToast({ title: '全局杯型设置已保存', icon: 'success' });
  },

  addDrink() {
    const selectedFilterBrand = this.data.brandFilterOptions[this.data.brandFilterIndex];
    const selectedBrandIndex = this.data.brands.findIndex((brand) => brand.name === selectedFilterBrand);
    const form = newForm(this.data.brands, selectedBrandIndex >= 0 ? selectedBrandIndex + 1 : 0);
    if (!form.brandId && selectedFilterBrand && selectedFilterBrand !== '全部品牌') form.brandName = selectedFilterBrand;
    this.setData({ showEditor: true, editingIsNew: true, form });
    wx.pageScrollTo({ scrollTop: 0, duration: 180 });
  },

  editDrink(event) {
    const drink = (this.allDrinks || []).find((item) => item.id === event.currentTarget.dataset.id);
    if (!drink) return;
    const source = drink.nutritionPerUnit || {};
    const brandIndex = Math.max(0, this.data.brands.findIndex((brand) => brand.id === drink.brandId) + 1);
    const capacities = Array.from(new Set((drink.cupSizes || []).map((item) => Number(item && item.sizeMl))
      .concat(drink.sizesMl || [], (drink.nutritionVariants || []).map((item) => Number(item && item.sizeMl)))
      .filter((value) => Number.isFinite(value) && value > 0)));
    const uniqueCapacity = capacities.length === 1 ? capacities[0] : null;
    const legacyCupNutrition = source.unit === '杯' && !uniqueCapacity;
    const sourceAmount = Number(source.amount) > 0 ? Number(source.amount) : (source.unit === '杯' ? 1 : 100);
    const scaleTo100Ml = source.unit === '杯' && uniqueCapacity
      ? 100 / (sourceAmount * uniqueCapacity)
      : source.unit === 'ml' ? 100 / sourceAmount : 1;
    const convertValue = (value) => value === null || value === undefined || value === '' || legacyCupNutrition
      ? '' : String(Math.round(Number(value) * scaleTo100Ml * 100) / 100);
    const legacyNutritionLabel = legacyCupNutrition
      ? [`旧基准：每 ${sourceAmount} 杯`].concat(['糖', '能量', '咖啡因'].map((label, index) => {
        const key = ['sugarG', 'energyKcal', 'caffeineMg'][index];
        return source[key] === null || source[key] === undefined || source[key] === '' ? '' : `${label} ${source[key]}${key === 'sugarG' ? 'g' : key === 'energyKcal' ? 'kcal' : 'mg'}`;
      })).filter(Boolean).join(' · ')
      : '';
    const sourceType = source.sourceType === 'official' ? 'official' : 'estimated';
    this.setData({
      showEditor: true,
      editingIsNew: false,
      form: {
        id: drink.id,
        brandId: drink.brandId || '',
        brandName: drink.brandName || '',
        brandIndex,
        customBrand: brandIndex === 0,
        name: drink.name || '',
        category: drink.category || '',
        aliasesText: (drink.aliases || []).join('，'),
        sugarG: convertValue(source.sugarG),
        energyKcal: convertValue(source.energyKcal),
        caffeineMg: convertValue(source.caffeineMg),
        nutritionSourceType: sourceType,
        nutritionSourceTypeIndex: sourceType === 'official' ? 1 : 0,
        nutritionSource: source.source || '',
        unitNutritionEdited: false,
        legacyCupNutrition,
        legacyNutritionLabel,
        active: drink.active !== false,
        menuStatusLabel: ({ verified: '已核验', pending: '待核验', unavailable: '暂不供应' })[drink.status] || '待核验'
      }
    });
  },

  closeEditor() { this.setData({ showEditor: false }); },

  noop() {},

  onFormInput(event) {
    const field = event.currentTarget.dataset.field;
    if (!field) return;
    const changes = { [`form.${field}`]: event.detail.value };
    if (['sugarG', 'energyKcal', 'caffeineMg'].includes(field)) changes['form.unitNutritionEdited'] = true;
    this.setData(changes);
  },

  onBrandChange(event) {
    const index = Number(event.detail.value) || 0;
    const brand = index > 0 ? this.data.brands[index - 1] : null;
    this.setData({
      'form.brandIndex': index,
      'form.brandId': brand ? brand.id : '',
      'form.brandName': brand ? brand.name : this.data.form.brandName,
      'form.category': brand && brand.category ? brand.category : this.data.form.category,
      'form.customBrand': !brand
    });
  },

  onNutritionSourceTypeChange(event) {
    const index = Number(event.detail.value) || 0;
    const nutritionSourceType = index === 1 ? 'official' : 'estimated';
    this.setData({ 'form.nutritionSourceTypeIndex': index, 'form.nutritionSourceType': nutritionSourceType });
  },

  onActiveChange(event) { this.setData({ 'form.active': !!event.detail.value }); },

  saveDrink() {
    const form = this.data.form;
    const selectedBrand = form.brandIndex > 0 ? this.data.brands[form.brandIndex - 1] : null;
    let brandId = selectedBrand ? selectedBrand.id : '';
    let brandName = selectedBrand ? selectedBrand.name : String(form.brandName || '').trim();
    const name = String(form.name || '').trim();
    const category = String(form.category || '').trim();
    if (!brandName || !name) {
      wx.showToast({ title: '请填写品牌和饮品名称', icon: 'none' });
      return;
    }
    const nutritionValues = {
      sugarG: parseOptionalNumber(form.sugarG),
      energyKcal: parseOptionalNumber(form.energyKcal),
      caffeineMg: parseOptionalNumber(form.caffeineMg)
    };
    if (Object.keys(nutritionValues).some((key) => !nutritionValues[key].valid)) {
      wx.showToast({ title: '营养数值须为 0 或更大的数字', icon: 'none' });
      return;
    }
    const hasNutrition = Object.keys(nutritionValues).some((key) => nutritionValues[key].value !== null);
    const nutritionSource = String(form.nutritionSource || '').trim();
    if (hasNutrition && form.nutritionSourceType === 'official' && !nutritionSource) {
      wx.showToast({ title: '官方数据请填写来源', icon: 'none' });
      return;
    }

    const catalog = Store.catalog();
    let newBrand = null;
    if (!brandId) {
      const existingBrand = catalog.brands.find((brand) => String(brand.name || '').trim().toLowerCase() === brandName.toLowerCase());
      if (existingBrand) {
        brandId = existingBrand.id;
        brandName = existingBrand.name;
      } else {
        brandId = `brand-user-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
        newBrand = {
          id: brandId, name: brandName, aliases: [], category, active: true, status: 'pending',
          source: '用户维护，品牌和菜单待核验', sourceType: 'user_report', updatedAt: new Date().toISOString(), localOverride: true
        };
      }
    }
    const current = form.id ? catalog.drinks.find((drink) => drink.id === form.id) : null;
    const previousNutrition = current && current.nutritionPerUnit;
    if (form.legacyCupNutrition && form.unitNutritionEdited && previousNutrition) {
      const missingLegacyValue = ['sugarG', 'energyKcal', 'caffeineMg'].some((key) => {
        const hadOldValue = previousNutrition[key] !== null && previousNutrition[key] !== undefined && previousNutrition[key] !== '';
        return hadOldValue && nutritionValues[key].value === null;
      });
      if (missingLegacyValue) {
        wx.showToast({ title: '请先补齐原有营养项的每100ml数值，旧的每杯数据才会替换', icon: 'none' });
        return;
      }
    }
    const duplicate = catalog.drinks.some((drink) => drink.id !== form.id
      && (drink.brandId ? drink.brandId === brandId
        : String(drink.brandName || '').trim().toLowerCase() === brandName.toLowerCase())
      && String(drink.name || '').trim().toLowerCase() === name.toLowerCase());
    if (duplicate) {
      wx.showToast({ title: '这个品牌下已有同名饮品', icon: 'none' });
      return;
    }

    const now = new Date().toISOString();
    if (newBrand) catalog.brands.push(newBrand);
    const aliases = Array.from(new Set(String(form.aliasesText || '').split(/[,，、;；\n]+/).map((value) => value.trim()).filter(Boolean)));
    const cupTypes = current && Array.isArray(current.cupTypes) ? current.cupTypes.slice() : [];
    const cupSizes = current && Array.isArray(current.cupSizes) ? current.cupSizes.map((item) => ({ ...item })) : [];
    const sizesMl = Array.from(new Set((current && Array.isArray(current.sizesMl) ? current.sizesMl : []))).sort((a, b) => a - b);
    const nutritionVariants = (current && Array.isArray(current.nutritionVariants) ? current.nutritionVariants : []).slice();
    const preserveLegacyCup = form.legacyCupNutrition && !form.unitNutritionEdited && previousNutrition && previousNutrition.unit === '杯';
    const nutritionPerUnit = preserveLegacyCup ? previousNutrition : {
      ...(previousNutrition || {}),
      amount: 100,
      unit: 'ml',
      sugarG: nutritionValues.sugarG.value,
      energyKcal: nutritionValues.energyKcal.value,
      caffeineMg: nutritionValues.caffeineMg.value,
      sourceType: form.nutritionSourceType === 'official' ? 'official' : 'estimated',
      source: nutritionSource,
      updatedAt: now
    };
    const drink = {
      ...(current || {}),
      id: current ? current.id : `catalog-drink-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      brandId,
      brandName,
      name,
      category,
      aliases,
      active: !!form.active,
      updatedAt: now,
      nutritionPerUnit,
      cupTypes,
      cupSizes,
      sizesMl,
      nutritionVariants,
      localOverride: true
    };
    if (!current) {
      drink.status = 'pending';
      drink.sourceType = 'user_report';
      drink.source = '用户维护，菜单待核验';
      drink.sweetnessOptions = [];
      drink.servingOptions = [];
      drink.menuEntries = [{
        scope: 'brand', status: 'pending', sourceType: 'user_report', sourceName: '用户维护', sourceUrl: '', checkedAt: dateStamp(),
        sizesMl, sweetnessOptions: [], servingOptions: []
      }];
      catalog.drinks.push(drink);
    } else {
      catalog.drinks = catalog.drinks.map((item) => item.id === current.id ? drink : item);
    }
    Store.saveCatalog(catalog);
    this.setData({ showEditor: false });
    this.refresh({ preservePagination: !!current });
    wx.showToast({ title: current ? '饮品数据已保存' : '饮品已加入清单', icon: 'success' });
  },

  drinkReferences(drinkId, drink) {
    const normalize = (value) => String(value || '').trim().toLowerCase();
    return Store.getRecords().filter((record) => record.drinkId === drinkId
      || (!record.drinkId && normalize(record.brandName) === normalize(drink.brandName)
        && normalize(record.drinkName) === normalize(drink.name)));
  },

  deleteDrink(event) {
    const drinkId = event.currentTarget.dataset.id;
    const currentCatalog = Store.catalog();
    const drink = currentCatalog.drinks.find((item) => item.id === drinkId);
    if (!drink) return wx.showToast({ title: '饮品不存在或已删除', icon: 'none' });
    const references = this.drinkReferences(drinkId, drink);
    if (references.length) {
      return wx.showModal({ title: '暂不能删除', content: `已有 ${references.length} 条饮品记录引用「${drink.name}」。请先保留该清单项，或将它设为隐藏。`, showCancel: false });
    }
    wx.showModal({ title: '确认删除饮品？', content: `删除「${drink.name}」后无法恢复。`, confirmText: '删除', cancelText: '保留', confirmColor: '#a14a3b', success: (result) => {
      if (!result.confirm) return;
      const latestCatalog = Store.catalog();
      const latestDrink = latestCatalog.drinks.find((item) => item.id === drinkId);
      if (!latestDrink) return this.refresh();
      const latestReferences = this.drinkReferences(drinkId, latestDrink);
      if (latestReferences.length) {
        wx.showModal({ title: '暂不能删除', content: `已有 ${latestReferences.length} 条饮品记录引用「${latestDrink.name}」。`, showCancel: false });
        return;
      }
      if (!Store.deleteCatalogDrink(drinkId)) return this.refresh();
      this.refresh();
      wx.showToast({ title: '饮品已删除', icon: 'success' });
    } });
  }
});
