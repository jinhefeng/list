const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function dayKey(date) {
  const d = date || new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

Page({
  data: { date: '', summary: {}, records: [], hasRecords: false },
  onShow() { this.refresh(); },
  refresh() {
    const date = this.data.date || dayKey();
    const userId = getApp().globalData.userId;
    const { drinks } = Store.catalog();
    const cupSizes = Store.getCupSizes();
    const records = Domain.listRecords(Store.getRecords(), userId, date).filter(Domain.isDrinkRecord).map((record) => {
      const nutrition = Domain.nutritionForRecord(record, Domain.findDrink(drinks, record.drinkId), cupSizes);
      return { ...record, timeLabel: record.consumedAt.slice(11, 16), nutrition,
        nutritionAmountsLabel: Domain.formatNutritionAmounts(nutrition) };
    });
    this.setData({ date, summary: Domain.dailySummary(Store.getRecords(), drinks, date, userId, cupSizes), records, hasRecords: records.length > 0 });
  },
  onDateChange(event) { this.setData({ date: event.detail.value }); this.refresh(); }
});
