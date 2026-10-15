const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function buildPhotos(dishes) {
  return (dishes || []).filter((dish) => dish.photo || dish.photoThumbnail).map((dish, index) => {
    const photo = dish.photo || dish.photoThumbnail;
    return {
      id: dish.id || `dish-photo-${index}`,
      name: String(dish.name || '').trim() || `菜品 ${index + 1}`,
      photo,
      thumbnail: dish.photoThumbnail || photo,
      thumbId: `meal-photo-thumb-${index}`
    };
  });
}

Page({
  data: { photos: [], currentIndex: 0, currentPhoto: null, activeThumbId: '' },
  onLoad(query) {
    let dishes = [];
    if (query.previewKey) {
      dishes = wx.getStorageSync(query.previewKey) || [];
      wx.removeStorageSync(query.previewKey);
    } else if (query.recordId) {
      const record = Store.getRecords().find((item) => String(item.id) === String(query.recordId) && Domain.isMealRecord(item));
      dishes = record && record.dishes || [];
    }
    const photos = buildPhotos(dishes);
    if (!photos.length) {
      wx.showToast({ title: '没有可查看的照片', icon: 'none' });
      setTimeout(() => wx.navigateBack({ delta: 1 }), 350);
      return;
    }
    const requestedIndex = Number(query.index);
    const currentIndex = Number.isInteger(requestedIndex) ? Math.max(0, Math.min(requestedIndex, photos.length - 1)) : 0;
    this.setData({ photos, currentIndex, currentPhoto: photos[currentIndex], activeThumbId: photos[currentIndex].thumbId });
  },
  onSwiperChange(event) {
    const currentIndex = Number(event.detail.current);
    const currentPhoto = this.data.photos[currentIndex];
    if (!currentPhoto) return;
    this.setData({ currentIndex, currentPhoto, activeThumbId: currentPhoto.thumbId });
  },
  selectPhoto(event) {
    const currentIndex = Number(event.currentTarget.dataset.index);
    const currentPhoto = this.data.photos[currentIndex];
    if (!currentPhoto) return;
    this.setData({ currentIndex, currentPhoto, activeThumbId: currentPhoto.thumbId });
  },
  closeViewer() {
    wx.navigateBack({ delta: 1, fail: () => wx.reLaunch({ url: '/pages/index/index' }) });
  }
});
