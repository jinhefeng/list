const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

Page({
  data: { records: [], hasRecords: false, filterDate: '' },
  onShow() { this.refresh(); },
  refresh() {
    const { drinks } = Store.catalog();
    const userId = getApp().globalData.userId;
    const records = Domain.listRecords(Store.getRecords(), userId, this.data.filterDate || undefined).map((record) => {
      const date = new Date(record.consumedAt);
      const nutrition = Domain.nutritionForRecord(record, Domain.findDrink(drinks, record.drinkId));
      return { ...record, dateLabel: `${date.getMonth() + 1}月${date.getDate()}日`, timeLabel: record.consumedAt.slice(11, 16), nutritionLabel: nutrition.label };
    });
    this.setData({ records, hasRecords: records.length > 0 });
  },
  onDateChange(event) { this.setData({ filterDate: event.detail.value }); this.refresh(); },
  clearDate() { this.setData({ filterDate: '' }); this.refresh(); },
  addDrink() { wx.navigateTo({ url: '/pages/record/record' }); },
  editRecord(event) { wx.navigateTo({ url: `/pages/record/record?id=${event.currentTarget.dataset.id}` }); },
  openHome() { wx.switchTab ? wx.reLaunch({ url: '/pages/index/index' }) : wx.navigateBack(); },
  openInsights() { wx.navigateTo({ url: '/pages/insights/insights' }); }
});
