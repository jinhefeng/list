const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function currentDateTime() {
  const d = new Date();
  return {
    date: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`,
    time: `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  };
}

function saveLocalFile(tempFilePath) {
  return new Promise((resolve) => {
    try {
      const fileSystemManager = wx.getFileSystemManager();
      if (!fileSystemManager || !fileSystemManager.saveFile) return resolve('');
      fileSystemManager.saveFile({ tempFilePath,
        success: (result) => resolve(result.savedFilePath || ''), fail: () => resolve('') });
    } catch (error) {
      resolve('');
    }
  });
}

function createThumbnail(page, filePath) {
  return new Promise((resolve) => {
    try {
      wx.createSelectorQuery().in(page).select('#mealThumbnailCanvas').fields({ node: true }).exec((result) => {
        const canvas = result && result[0] && result[0].node;
        if (!canvas) return resolve('');
        canvas.width = 360;
        canvas.height = 360;
        const context = canvas.getContext('2d');
        const image = canvas.createImage();
        image.onload = () => {
          const side = Math.min(image.width, image.height);
          const sourceX = (image.width - side) / 2;
          const sourceY = (image.height - side) / 2;
          try {
            context.clearRect(0, 0, 360, 360);
            context.drawImage(image, sourceX, sourceY, side, side, 0, 0, 360, 360);
            wx.canvasToTempFilePath({
              canvas, x: 0, y: 0, width: 360, height: 360, destWidth: 360, destHeight: 360,
              fileType: 'jpg', quality: 0.82,
              success: (exported) => resolve(exported.tempFilePath), fail: () => resolve('')
            }, page);
          } catch (error) {
            resolve('');
          }
        };
        image.onerror = () => resolve('');
        image.src = filePath;
      });
    } catch (error) {
      resolve('');
    }
  });
}

function newDish() {
  return { id: `dish-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, name: '', photo: '', photoThumbnail: '' };
}

function mealEditSnapshot(data) {
  return JSON.stringify({
    storeName: data.storeName, locationAddress: data.locationAddress,
    locationLatitude: data.locationLatitude, locationLongitude: data.locationLongitude,
    date: data.date, time: data.time, dishes: data.dishes, notes: data.notes
  });
}

Page({
  data: {
    editing: false, fromDetail: false, recordId: '', ...currentDateTime(), storeName: '', locationAddress: '',
    locationLatitude: '', locationLongitude: '', dishes: [], notes: '', dragIndex: -1,
    timeHint: '默认使用打开记录页时的时间；可手动调整',
    locationHint: '请在地图中搜索并确认用餐地址'
  },
  onLoad(query) {
    this.setData({ fromDetail: query.fromDetail === '1' });
    if (query.id) this.loadRecord(query.id);
    else {
      this.setData(currentDateTime());
      this.requestCurrentLocation();
    }
  },
  loadRecord(id) {
    const record = Store.getRecords().find((item) => item.id === id && item.userId === getApp().globalData.userId);
    if (!record || !Domain.isMealRecord(record)) return wx.showToast({ title: '用餐记录不存在', icon: 'none' });
    const latitude = record.locationLatitude === null || record.locationLatitude === undefined ? NaN : Number(record.locationLatitude);
    const longitude = record.locationLongitude === null || record.locationLongitude === undefined ? NaN : Number(record.locationLongitude);
    if (Number.isFinite(latitude) && Number.isFinite(longitude)) this.currentMapCenter = { latitude, longitude };
    this.setData({ editing: true, recordId: id, storeName: record.storeName || '', locationAddress: record.locationAddress || '',
      locationLatitude: record.locationLatitude === null ? '' : record.locationLatitude,
      locationLongitude: record.locationLongitude === null ? '' : record.locationLongitude,
      date: String(record.consumedAt || '').slice(0, 10), time: String(record.consumedAt || '').slice(11, 16),
      dishes: (record.dishes || []).map((dish) => ({ ...dish, photoThumbnail: dish.photoThumbnail || dish.photo || '' })),
      notes: record.notes || '', timeHint: '已保存的用餐时间，可手动调整',
      locationHint: record.locationAddress ? '已保存地图地址；可重新搜索并确认' : '请在地图中搜索并确认用餐地址' }, () => {
      this.editSnapshot = mealEditSnapshot(this.data);
    });
  },
  cancelEdit() {
    const leave = () => wx.navigateBack();
    if (mealEditSnapshot(this.data) === this.editSnapshot) return leave();
    wx.showModal({ title: '放弃修改？', content: '尚未保存的内容会丢失。', confirmText: '放弃修改', confirmColor: '#9b5148',
      success: (result) => { if (result.confirm) leave(); } });
  },
  requestCurrentLocation() {
    if (!wx.getLocation) return;
    try {
      wx.getLocation({ type: 'gcj02', success: (result) => {
        this.currentMapCenter = { latitude: result.latitude, longitude: result.longitude };
      } });
    } catch (error) {
      // Map search remains available without an initial center.
    }
  },
  choosePlace() {
    if (!wx.chooseLocation) {
      this.setData({ locationHint: '当前环境不支持地图选点，请在微信中打开后选择地址' });
      return;
    }
    const center = this.currentMapCenter;
    const options = { success: (result) => {
      const storeName = result.name || this.data.storeName;
      const locationAddress = result.address || result.name || '';
      this.currentMapCenter = { latitude: result.latitude, longitude: result.longitude };
      this.setData({ storeName, locationAddress, locationLatitude: result.latitude,
        locationLongitude: result.longitude, locationHint: '已在地图中确认地址；店名可以修改' });
    }, fail: (error) => {
      if (error && String(error.errMsg || '').includes('cancel')) return;
      this.setData({ locationHint: '地图选点未完成，请重试或留待下次选择' });
    } };
    if (center && Number.isFinite(Number(center.latitude)) && Number.isFinite(Number(center.longitude))) {
      options.latitude = Number(center.latitude);
      options.longitude = Number(center.longitude);
    }
    try { wx.chooseLocation(options); } catch (error) {
      this.setData({ locationHint: '当前环境无法打开地图，请在微信中打开后选择地址' });
    }
  },
  updateField(event) {
    const field = event.currentTarget.dataset.field;
    this.setData({ [field]: event.detail.value });
  },
  onDateChange(event) { this.setData({ date: event.detail.value, timeHint: '已自定义用餐时间' }); },
  onTimeChange(event) { this.setData({ time: event.detail.value, timeHint: '已自定义用餐时间' }); },
  addDish() { this.setData({ dishes: this.data.dishes.concat(newDish()) }); },
  startDishDrag(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (!Number.isInteger(index) || index < 0 || index >= this.data.dishes.length) return;
    this.draggingDishIndex = index;
    this.setData({ dragIndex: index });
    wx.createSelectorQuery().in(this).selectAll('.dish-sort-item').boundingClientRect().exec((result) => {
      this.dragRects = result && result[0] || [];
    });
  },
  moveDishDrag(event) {
    if (this.draggingDishIndex === undefined || !this.dragRects || !this.dragRects.length) return;
    const touch = event.touches && event.touches[0];
    if (!touch) return;
    const from = this.draggingDishIndex;
    const y = touch.clientY;
    let to = this.dragRects.length - 1;
    for (let index = 0; index < this.dragRects.length; index += 1) {
      const rect = this.dragRects[index];
      if (y <= rect.top + rect.height / 2) { to = index; break; }
    }
    if (to === from) return;
    const dishes = this.data.dishes.slice();
    const movedDish = dishes.splice(from, 1)[0];
    dishes.splice(to, 0, movedDish);
    this.draggingDishIndex = to;
    this.setData({ dishes, dragIndex: to });
  },
  endDishDrag() {
    this.draggingDishIndex = undefined;
    this.dragRects = [];
    this.setData({ dragIndex: -1 });
  },
  updateDishName(event) {
    const id = event.currentTarget.dataset.id;
    const value = event.detail.value;
    this.setData({ dishes: this.data.dishes.map((dish) => dish.id === id ? { ...dish, name: value } : dish) });
  },
  removeDish(event) {
    const id = event.currentTarget.dataset.id;
    if (this.photoTokens) delete this.photoTokens[id];
    this.setData({ dishes: this.data.dishes.filter((dish) => dish.id !== id) });
  },
  chooseDishPhoto(event) {
    const id = event.currentTarget.dataset.id;
    wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['album', 'camera'], sizeType: ['original'], success: (res) => {
      const tempFile = res.tempFiles && res.tempFiles[0];
      if (!tempFile || !tempFile.tempFilePath) return;
      const token = `${Date.now()}-${Math.random()}`;
      if (!this.photoTokens) this.photoTokens = {};
      this.photoTokens[id] = token;
      this.setData({ dishes: this.data.dishes.map((dish) => dish.id === id ? { ...dish, photoPending: true } : dish) });
      const work = saveLocalFile(tempFile.tempFilePath).then((photo) => {
        if (!photo) throw new Error('photo-save-failed');
        const previous = this.thumbnailQueue || Promise.resolve('');
        const thumbnailWork = previous.then(() => createThumbnail(this, photo));
        this.thumbnailQueue = thumbnailWork.then(() => '', () => '');
        return thumbnailWork.then((path) => path ? saveLocalFile(path) : '').then((thumbnail) => ({ photo, photoThumbnail: thumbnail || photo }));
      }).then((savedPhoto) => {
        if (this.photoTokens[id] !== token) return;
        this.setData({ dishes: this.data.dishes.map((dish) => dish.id === id
          ? { ...dish, ...savedPhoto, photoPending: false } : dish) });
      }).catch(() => {
        if (this.photoTokens[id] !== token) return;
        this.setData({ dishes: this.data.dishes.map((dish) => dish.id === id ? { ...dish, photoPending: false } : dish) });
        wx.showToast({ title: '照片保存失败，请重试', icon: 'none' });
      });
      if (!this.photoWorks) this.photoWorks = [];
      this.photoWorks.push(work);
    } });
  },
  removeDishPhoto(event) {
    const id = event.currentTarget.dataset.id;
    if (this.photoTokens) this.photoTokens[id] = `${Date.now()}-removed`;
    this.setData({ dishes: this.data.dishes.map((dish) => dish.id === id ? { ...dish, photo: '', photoThumbnail: '', photoPending: false } : dish) });
  },
  previewPhoto(event) {
    const dishId = event.currentTarget.dataset.id;
    const photos = this.data.dishes.filter((dish) => dish.photo || dish.photoThumbnail).map((dish, index) => ({
      id: dish.id || `dish-photo-${index}`,
      name: String(dish.name || '').trim() || `菜品 ${index + 1}`,
      photo: dish.photo || dish.photoThumbnail
    }));
    if (!photos.length) return;
    const index = Math.max(0, photos.findIndex((photo) => photo.id === dishId));
    const previewKey = `meal-preview-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    wx.setStorageSync(previewKey, photos);
    wx.navigateTo({
      url: `/pages/meal-preview/meal-preview?previewKey=${encodeURIComponent(previewKey)}&index=${index}`,
      fail: () => wx.removeStorageSync(previewKey)
    });
  },
  save() {
    if (this.saving) return;
    this.saving = true;
    Promise.all(this.photoWorks || []).then(() => {
      this.saveRecord();
    }, () => {
      this.saveRecord();
    });
  },
  saveRecord() {
    if (!this.data.locationAddress.trim()) {
      this.saving = false;
      return wx.showToast({ title: '请先在地图中搜索并确认用餐地址', icon: 'none' });
    }
    if (!this.data.storeName.trim()) {
      this.saving = false;
      return wx.showToast({ title: '请填写店名', icon: 'none' });
    }
    const dishes = this.data.dishes.filter((dish) => String(dish.name || '').trim());
    if (!dishes.length) {
      this.saving = false;
      return wx.showToast({ title: '请至少添加一道菜品并填写名称', icon: 'none' });
    }
    const userId = getApp().globalData.userId;
    const records = Store.getRecords();
    const existing = this.data.editing ? records.find((item) => item.id === this.data.recordId && item.userId === userId) : null;
    const payload = Domain.createMealRecord({ ...(existing || {}), id: this.data.recordId || undefined,
      storeName: this.data.storeName, locationAddress: this.data.locationAddress,
      locationLatitude: this.data.locationLatitude, locationLongitude: this.data.locationLongitude,
      consumedAt: `${this.data.date}T${this.data.time}:00`, dishes, notes: this.data.notes,
      userName: getApp().globalData.userName || '我' }, userId);
    if (this.data.editing) Store.saveRecords(Domain.updateRecord(records, this.data.recordId, userId, payload));
    else Store.saveRecords([payload, ...records]);
    wx.showToast({ title: this.data.editing ? '已保存修改' : '用餐记录完成', icon: 'success' });
    setTimeout(() => wx.navigateBack(), 450);
  },
  deleteRecord() {
    wx.showModal({ title: '删除这条用餐记录？', content: '删除后无法恢复。', confirmColor: '#a14a3b', success: (result) => {
      if (!result.confirm) return;
      Store.saveRecords(Domain.deleteRecord(Store.getRecords(), this.data.recordId, getApp().globalData.userId));
      wx.navigateBack();
    } });
  }
});
