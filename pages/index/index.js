const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function dayKey(date) {
  const d = date || new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

Page({
  data: { dateLabel: '', records: [], summary: {}, hasRecords: false },
  onShow() { this.refresh(); },
  refresh() {
    const userId = getApp().globalData.userId;
    const { drinks } = Store.catalog();
    const all = Store.getRecords();
    const today = dayKey();
    const records = Domain.listRecords(all, userId, today).map((record) => {
      const nutrition = Domain.nutritionForRecord(record, Domain.findDrink(drinks, record.drinkId));
      return { ...record, timeLabel: record.consumedAt.slice(11, 16), nutritionLabel: nutrition.label };
    });
    this.setData({
      dateLabel: `${new Date().getMonth() + 1}月${new Date().getDate()}日`,
      records,
      hasRecords: records.length > 0,
      summary: Domain.dailySummary(all, drinks, today, userId)
    });
  },
  addDrink() { wx.navigateTo({ url: '/pages/record/record' }); },
  openHistory() { wx.navigateTo({ url: '/pages/history/history' }); },
  openInsights() { wx.navigateTo({ url: '/pages/insights/insights' }); },
  editRecord(event) { wx.navigateTo({ url: `/pages/record/record?id=${event.currentTarget.dataset.id}` }); }
});
