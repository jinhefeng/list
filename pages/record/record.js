const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

Page({
  data: {
    editing: false, recordId: '', custom: false, brands: [], drinks: [], selectedBrand: {}, selectedDrink: {},
    brandQuery: '', drinkQuery: '', drinkName: '', brandName: '', date: today(), time: '12:00',
    sizeMl: '', sweetness: '', ice: '', toppings: '', location: '', notes: '', photo: '',
    energyKcal: '', sugarG: '', caffeineMg: '', showBrandPicker: false, showDrinkPicker: false
  },
  onLoad(query) {
    const catalog = Store.catalog();
    this.catalog = catalog;
    this.setData({ brands: Domain.searchBrands(catalog.brands, '') });
    if (query.id) this.loadRecord(query.id);
  },
  loadRecord(id) {
    const record = Store.getRecords().find((item) => item.id === id && item.userId === getApp().globalData.userId);
    if (!record) return wx.showToast({ title: '记录不存在', icon: 'none' });
    const brand = this.catalog.brands.find((item) => item.id === record.brandId) || {};
    const drink = Domain.findDrink(this.catalog.drinks, record.drinkId) || {};
    this.setData({ editing: true, recordId: id, custom: !drink || drink.custom, selectedBrand: brand, selectedDrink: drink,
      brandName: record.brandName, drinkName: record.drinkName, date: record.consumedAt.slice(0, 10), time: record.consumedAt.slice(11, 16),
      sizeMl: record.sizeMl ? String(record.sizeMl) : '', sweetness: record.sweetness, ice: record.ice,
      toppings: (record.toppings || []).join('，'), location: record.location, notes: record.notes, photo: record.photo });
  },
  updateField(event) { this.setData({ [event.currentTarget.dataset.field]: event.detail.value }); },
  toggleBrandPicker() { this.setData({ showBrandPicker: !this.data.showBrandPicker, showDrinkPicker: false }); },
  toggleDrinkPicker() { this.setData({ showDrinkPicker: !this.data.showDrinkPicker, showBrandPicker: false }); },
  onBrandSearch(event) {
    const query = event.detail.value;
    this.setData({ brandQuery: query, brands: Domain.searchBrands(this.catalog.brands, query) });
  },
  selectBrand(event) {
    const brand = this.catalog.brands.find((item) => item.id === event.currentTarget.dataset.id);
    this.setData({ selectedBrand: brand, selectedDrink: null, brandName: brand.name, drinkName: '', drinkQuery: '',
      drinks: Domain.searchDrinks(this.catalog.drinks, brand.id, ''), showBrandPicker: false, custom: false });
  },
  onDrinkSearch(event) {
    const query = event.detail.value;
    this.setData({ drinkQuery: query, drinks: Domain.searchDrinks(this.catalog.drinks, this.data.selectedBrand && this.data.selectedBrand.id, query) });
  },
  selectDrink(event) {
    const drink = Domain.findDrink(this.catalog.drinks, event.currentTarget.dataset.id);
    this.setData({ selectedDrink: drink, drinkName: drink.name, sizeMl: drink.sizes && drink.sizes.length ? String(drink.sizes[1] || drink.sizes[0]) : '', showDrinkPicker: false, custom: false });
  },
  enableCustom() { this.setData({ custom: true, selectedDrink: null, selectedBrand: null, brandName: '', drinkName: '', showDrinkPicker: false, showBrandPicker: false }); },
  choosePhoto() {
    wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['album', 'camera'], success: (res) => {
      const tempFilePath = res.tempFiles[0].tempFilePath;
      wx.saveFile({ tempFilePath, success: (saved) => this.setData({ photo: saved.savedFilePath }), fail: () => this.setData({ photo: tempFilePath }) });
    } });
  },
  removePhoto() { this.setData({ photo: '' }); },
  onDateChange(event) { this.setData({ date: event.detail.value }); },
  onTimeChange(event) { this.setData({ time: event.detail.value }); },
  save() {
    const userId = getApp().globalData.userId;
    let brandName = this.data.custom ? this.data.brandName.trim() : (this.data.selectedBrand && this.data.selectedBrand.name) || this.data.brandName.trim();
    let drinkName = this.data.custom ? this.data.drinkName.trim() : (this.data.selectedDrink && this.data.selectedDrink.name) || this.data.drinkName.trim();
    if (!brandName || !drinkName) return wx.showToast({ title: '请选择或填写品牌和饮品', icon: 'none' });
    const consumedAt = `${this.data.date}T${this.data.time}:00`;
    let drink = this.data.selectedDrink;
    if (this.data.custom) {
      const previousCustom = this.catalog.drinks.find((item) => item.custom && item.createdBy === userId && item.brandName === brandName && item.name === drinkName);
      drink = previousCustom || Domain.createCustomDrink({ brandName, drinkName, sizeMl: this.data.sizeMl }, userId);
      const nutritionEntered = [this.data.energyKcal, this.data.sugarG, this.data.caffeineMg].some((value) => value !== '');
      if (nutritionEntered) {
        drink.nutritionVariants = (drink.nutritionVariants || []).filter((item) => !(Number(item.sizeMl) === Number(this.data.sizeMl) && item.sweetness === this.data.sweetness && item.ice === this.data.ice && item.toppings.join('|') === this.toppingsArray().join('|')));
        drink.nutritionVariants.push({ sizeMl: Number(this.data.sizeMl) || 0, sweetness: this.data.sweetness, ice: this.data.ice,
          toppings: this.toppingsArray(), sourceType: 'estimated', source: '用户估算', updatedAt: today(),
          energyKcal: this.data.energyKcal, sugarG: this.data.sugarG, caffeineMg: this.data.caffeineMg });
      }
      if (!previousCustom) this.catalog.drinks.push(drink);
      Store.saveCatalog(this.catalog);
    }
    const existing = this.data.editing ? Store.getRecords().find((item) => item.id === this.data.recordId && item.userId === userId) : null;
    const payload = Domain.createRecord({ ...(existing || {}), id: this.data.recordId || undefined, brandId: (this.data.selectedBrand && this.data.selectedBrand.id) || drink.brandId || '',
      brandName, drinkId: drink.id, drinkName, consumedAt, sizeMl: this.data.sizeMl, sweetness: this.data.sweetness, ice: this.data.ice,
      toppings: this.toppingsArray(), photo: this.data.photo, location: this.data.location, notes: this.data.notes }, userId);
    const records = Store.getRecords();
    if (this.data.editing) Store.saveRecords(Domain.updateRecord(records, this.data.recordId, userId, payload));
    else Store.saveRecords([payload, ...records]);
    wx.showToast({ title: this.data.editing ? '已保存修改' : '记录完成', icon: 'success' });
    setTimeout(() => wx.navigateBack(), 450);
  },
  toppingsArray() { return String(this.data.toppings || '').split(/[，,、]/).map((item) => item.trim()).filter(Boolean); },
  deleteRecord() {
    wx.showModal({ title: '删除这条记录？', content: '删除后无法恢复。', confirmColor: '#a14a3b', success: (result) => {
      if (!result.confirm) return;
      const records = Domain.deleteRecord(Store.getRecords(), this.data.recordId, getApp().globalData.userId);
      Store.saveRecords(records);
      wx.navigateBack();
    } });
  }
});
