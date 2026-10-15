const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function dayKey(date) {
  const d = date || new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function isCoordinateLabel(value) {
  return /^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/.test(String(value || ''));
}

function mealPhotoStack(dishes, imageSize, layerOffset) {
  const photos = (dishes || []).filter((dish) => dish.photo || dish.photoThumbnail);
  const visiblePhotos = photos.slice(0, 4);
  return {
    photoCount: photos.length,
    photoCountLabel: `共 ${photos.length} 张`,
    photoStackWidth: imageSize + Math.max(0, visiblePhotos.length - 1) * layerOffset,
    photoStackHeight: imageSize,
    photoDishes: visiblePhotos.map((dish, index) => ({
      ...dish,
      photoThumbnail: dish.photoThumbnail || dish.photo || '',
      stackLeft: index * layerOffset,
      stackZIndex: visiblePhotos.length - index
    }))
  };
}

Page({
  data: { dateLabel: '', records: [], summary: {}, hasRecords: false },
  onShow() { this.refresh(); },
  refresh() {
    const userId = getApp().globalData.userId;
    const { drinks } = Store.catalog();
    const cupSizes = Store.getCupSizes();
    const all = Store.getRecords();
    const today = dayKey();
    const records = Domain.listRecords(all, userId, today).map((record) => {
      if (Domain.isMealRecord(record)) {
        const dishes = record.dishes || [];
        return { ...record, kind: 'meal', timeLabel: record.consumedAt.slice(11, 16), dishCount: dishes.length,
          dishNames: dishes.map((dish) => dish.name).filter(Boolean).join('、'),
          ...mealPhotoStack(dishes, 132, 22) };
      }
      const timeLabel = String(record.consumedAt || '').slice(11, 16);
      if (Domain.isDrinkRecord(record)) {
        const nutrition = Domain.nutritionForRecord(record, Domain.findDrink(drinks, record.drinkId), cupSizes);
        const servingLabel = Domain.formatServingLabel(record);
        const locationLabel = isCoordinateLabel(record.location)
          ? (record.locationAddress || '')
          : (record.location || record.locationAddress || '');
        return { ...record, kind: 'drink', timeLabel, cupLabel: Domain.formatCupLabel(record), servingLabel, nutritionLabel: nutrition.label, locationLabel };
      }
      return { ...record, kind: 'other', timeLabel,
        displayName: record.title || record.name || record.displayName || record.typeLabel || record.type || '记录',
        displayDetails: record.description || record.details || record.note || record.notes || '' };
    });
    this.setData({
      dateLabel: `${new Date().getMonth() + 1}月${new Date().getDate()}日`,
      records,
      hasRecords: records.length > 0,
      summary: Domain.dailySummary(all, drinks, today, userId, cupSizes)
    });
  },
  addDrink() { wx.navigateTo({ url: '/pages/record/record' }); },
  addMeal() { wx.navigateTo({ url: '/pages/meal/meal' }); },
  openCatalog() { wx.navigateTo({ url: '/pages/catalog/catalog' }); },
  openHistory() { wx.navigateTo({ url: '/pages/history/history' }); },
  previewPhoto(event) {
    const { recordId, photoIndex } = event.currentTarget.dataset;
    if (recordId) wx.navigateTo({ url: `/pages/meal-preview/meal-preview?recordId=${encodeURIComponent(recordId)}&index=${Number(photoIndex) || 0}` });
  },
  openRecord(event) {
    const record = Store.getRecords().find((item) => item.id === event.currentTarget.dataset.id);
    if (!record) return;
    wx.navigateTo({ url: `/pages/record-detail/record-detail?id=${encodeURIComponent(record.id)}` });
  }
});
