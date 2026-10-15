const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function hasValue(value) {
  return value !== undefined && value !== null && String(value).trim() !== '';
}

function addField(fields, label, value) {
  if (hasValue(value)) fields.push({ label, value: String(value) });
}

function firstStoredValue(record, keys) {
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(record, key) && record[key] !== null && record[key] !== undefined) return record[key];
  }
  return '';
}

function normalizePhoto(photo, index) {
  if (typeof photo === 'string') {
    return { id: `photo-${index}`, name: '', photo, photoThumbnail: photo };
  }
  if (!photo || typeof photo !== 'object') return null;
  const source = photo.photo || photo.url || photo.path || photo.src || photo.photoThumbnail || photo.thumbnail || '';
  if (!source) return null;
  return {
    id: photo.id || `photo-${index}`,
    name: photo.name || photo.title || '',
    photo: photo.photo || photo.url || photo.path || photo.src || source,
    photoThumbnail: photo.photoThumbnail || photo.thumbnail || source
  };
}

function recordPhotos(record, kind) {
  if (kind === 'meal') {
    return (Array.isArray(record.dishes) ? record.dishes : []).map((dish, index) => normalizePhoto({
      id: dish.id, name: dish.name, photo: dish.photo, photoThumbnail: dish.photoThumbnail || dish.photo
    }, index)).filter(Boolean);
  }
  const photos = Array.isArray(record.photos) ? record.photos.map(normalizePhoto).filter(Boolean) : [];
  if (record.photo || record.photoThumbnail) {
    photos.unshift(normalizePhoto({ photo: record.photo, photoThumbnail: record.photoThumbnail || record.photo }, photos.length));
  }
  return photos.filter(Boolean);
}

function transformLatitude(x, y) {
  let value = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  value += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  value += (20 * Math.sin(y * Math.PI) + 40 * Math.sin(y / 3 * Math.PI)) * 2 / 3;
  value += (160 * Math.sin(y / 12 * Math.PI) + 320 * Math.sin(y * Math.PI / 30)) * 2 / 3;
  return value;
}

function transformLongitude(x, y) {
  let value = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  value += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  value += (20 * Math.sin(x * Math.PI) + 40 * Math.sin(x / 3 * Math.PI)) * 2 / 3;
  value += (150 * Math.sin(x / 12 * Math.PI) + 300 * Math.sin(x / 30 * Math.PI)) * 2 / 3;
  return value;
}

function wgs84ToGcj02(latitude, longitude) {
  if (longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271) return { latitude, longitude };
  const pi = Math.PI;
  const axis = 6378245.0;
  const eccentricity = 0.00669342162296594323;
  let deltaLatitude = transformLatitude(longitude - 105, latitude - 35);
  let deltaLongitude = transformLongitude(longitude - 105, latitude - 35);
  const radLatitude = latitude / 180 * pi;
  let magic = Math.sin(radLatitude);
  magic = 1 - eccentricity * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  deltaLatitude = deltaLatitude * 180 / ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * pi);
  deltaLongitude = deltaLongitude * 180 / (axis / sqrtMagic * Math.cos(radLatitude) * pi);
  return { latitude: latitude + deltaLatitude, longitude: longitude + deltaLongitude };
}

function storedMapLocation(record, label, address) {
  let latitude = NaN;
  let longitude = NaN;
  if (hasValue(record.locationLatitude) && hasValue(record.locationLongitude)) {
    latitude = Number(record.locationLatitude);
    longitude = Number(record.locationLongitude);
  }
  const canShowMap = Number.isFinite(latitude) && Number.isFinite(longitude)
    && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  const name = label || address || (canShowMap ? '查看地图位置' : '');
  return hasValue(name) ? {
    label: String(name), address: address || '', latitude, longitude, canShowMap
  } : null;
}

function drinkMapLocation(record) {
  const isCoordinateLabel = /^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/.test(String(record.location || ''));
  let latitude = NaN;
  let longitude = NaN;
  let canShowMap = false;
  if (isCoordinateLabel) {
    const parts = String(record.location).split(',').map((value) => Number(value.trim()));
    if (parts.length === 2 && parts.every(Number.isFinite)) {
      const converted = wgs84ToGcj02(parts[0], parts[1]);
      latitude = converted.latitude;
      longitude = converted.longitude;
      canShowMap = latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
    }
  } else if (hasValue(record.locationLatitude) && hasValue(record.locationLongitude)) {
    latitude = Number(record.locationLatitude);
    longitude = Number(record.locationLongitude);
    canShowMap = Number.isFinite(latitude) && Number.isFinite(longitude)
      && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  }
  const label = (isCoordinateLabel ? record.locationAddress : (record.location || record.locationAddress))
    || (canShowMap ? '查看地图位置' : '');
  return hasValue(label) ? {
    label, address: record.locationAddress || '', latitude, longitude, canShowMap
  } : null;
}

function formatUser(record, currentUserId) {
  if (hasValue(record.userId) && hasValue(currentUserId) && String(record.userId) === String(currentUserId)) return record.userName || '我';
  return record.userName || '未命名用户';
}

function buildDetail(record, currentUserId) {
  const fields = [];
  const consumedAt = String(record.consumedAt || '');
  const date = consumedAt.slice(0, 10);
  const time = consumedAt.slice(11, 16);
  let kind = 'other';
  let typeLabel = String(record.typeLabel || record.typeName || record.type || '其他记录');
  let title = String(record.title || record.name || record.displayName || typeLabel);
  let dishes = [];
  let location = null;
  let heroPhoto = '';

  if (Domain.isMealRecord(record)) {
    kind = 'meal';
    typeLabel = '吃饭';
    title = record.storeName || '用餐记录';
    const sourceDishes = Array.isArray(record.dishes) ? record.dishes : [];
    let photoIndex = 0;
    dishes = sourceDishes.map((dish, dishIndex) => {
      const detailPhoto = dish.photo || dish.photoThumbnail || '';
      const imageIndex = detailPhoto ? photoIndex++ : -1;
      return {
        ...dish,
        detailPhoto,
        photoIndex: imageIndex,
        dishNumber: String(dishIndex + 1).padStart(2, '0')
      };
    });
    addField(fields, '备注', record.notes);
    location = storedMapLocation(record, record.locationAddress || record.storeName, record.locationAddress);
  } else if (Domain.isDrinkRecord(record)) {
    kind = 'drink';
    typeLabel = '饮品';
    title = record.drinkName || '饮品记录';
    addField(fields, '品牌', record.brandName);
    addField(fields, '杯型', Domain.formatCupLabel(record));
    addField(fields, '甜度', record.sweetness);
    addField(fields, '冰量 / 温度', Domain.formatServingLabel(record));
    addField(fields, '营养信息', Domain.nutritionForRecord(record, Domain.findDrink(Store.catalog().drinks, record.drinkId), Store.getCupSizes()).label);
    addField(fields, '备注', record.notes);
    location = drinkMapLocation(record);
    heroPhoto = record.photo || record.photoThumbnail || '';
  } else {
    addField(fields, '说明', firstStoredValue(record, ['description', 'details', 'note', 'notes']));
    addField(fields, '地点', firstStoredValue(record, ['locationAddress', 'location']));
    const hiddenKeys = new Set([
      'id', 'type', 'typeLabel', 'typeName', 'userId', 'userName', 'createdAt', 'updatedAt', 'consumedAt',
      'title', 'name', 'displayName', 'description', 'details', 'note', 'notes', 'location', 'locationAddress',
      'locationLatitude', 'locationLongitude', 'photo', 'photoThumbnail', 'photos', 'dishes'
    ]);
    Object.keys(record).forEach((key) => {
      if (hiddenKeys.has(key)) return;
      const value = record[key];
      if (['string', 'number', 'boolean'].includes(typeof value) && hasValue(value)) addField(fields, key, value);
    });
  }

  return {
    id: String(record.id), kind, typeLabel, title, date, time,
    userName: formatUser(record, currentUserId),
    fields, location, heroPhoto, dishCount: dishes.length,
    dishes,
    photos: recordPhotos(record, kind),
    hasDishes: dishes.length > 0
  };
}

function currentDateTime() {
  const value = new Date();
  return {
    date: `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`,
    time: `${String(value.getHours()).padStart(2, '0')}:${String(value.getMinutes()).padStart(2, '0')}`
  };
}

function genericDescription(record) {
  return firstStoredValue(record, ['description', 'details', 'note', 'notes']);
}

function genericLocation(record) {
  return firstStoredValue(record, ['locationAddress', 'location']);
}

Page({
  data: {
    mode: 'view', detail: null, canEdit: false, moreOpen: false,
    genericTitle: '', genericDescription: '', genericLocation: '', date: '', time: ''
  },
  onLoad(query) {
    this.recordId = String(query.id || query.recordId || '');
    this.refresh();
  },
  onShow() {
    if (this.recordId) this.refresh();
  },
  refresh() {
    const currentUserId = getApp().globalData.userId;
    const record = Store.getRecords().find((item) => String(item.id) === this.recordId);
    if (!record) {
      wx.showToast({ title: '记录不存在', icon: 'none' });
      setTimeout(() => wx.navigateBack({ fail: () => wx.reLaunch({ url: '/pages/index/index' }) }), 350);
      return;
    }
    this.record = record;
    this.setData({
      detail: buildDetail(record, currentUserId),
      canEdit: hasValue(record.userId) && hasValue(currentUserId)
        && String(record.userId) === String(currentUserId),
      moreOpen: false
    });
  },
  toggleMore() { this.setData({ moreOpen: !this.data.moreOpen }); },
  closeMore() { if (this.data.moreOpen) this.setData({ moreOpen: false }); },
  editRecord() {
    if (!this.data.detail || !this.data.canEdit) return;
    const id = encodeURIComponent(this.recordId);
    if (this.data.detail.kind === 'meal') {
      wx.navigateTo({ url: `/pages/meal/meal?id=${id}&fromDetail=1` });
      return;
    }
    if (this.data.detail.kind === 'drink') {
      wx.navigateTo({ url: `/pages/record/record?id=${id}&fromDetail=1` });
      return;
    }
    const fallback = currentDateTime();
    this.genericDirty = false;
    this.setData({
      mode: 'edit',
      genericTitle: String(this.record.title || this.record.name || this.record.displayName || this.data.detail.typeLabel),
      genericDescription: String(genericDescription(this.record)),
      genericLocation: String(genericLocation(this.record)),
      date: String(this.record.consumedAt || '').slice(0, 10) || fallback.date,
      time: String(this.record.consumedAt || '').slice(11, 16) || fallback.time,
      moreOpen: false
    });
  },
  updateGenericField(event) {
    const field = event.currentTarget.dataset.field;
    this.genericDirty = true;
    this.setData({ [field]: event.detail.value });
  },
  onDateChange(event) { this.genericDirty = true; this.setData({ date: event.detail.value }); },
  onTimeChange(event) { this.genericDirty = true; this.setData({ time: event.detail.value }); },
  cancelGenericEdit() {
    const leave = () => {
      this.genericDirty = false;
      this.setData({ mode: 'view' });
    };
    if (!this.genericDirty) return leave();
    wx.showModal({
      title: '放弃修改？', content: '尚未保存的内容会丢失。', confirmText: '放弃修改', confirmColor: '#9b5148',
      success: (result) => { if (result.confirm) leave(); }
    });
  },
  saveGeneric() {
    if (!String(this.data.genericTitle || '').trim()) return wx.showToast({ title: '请填写记录名称', icon: 'none' });
    if (!this.data.date || !this.data.time) return wx.showToast({ title: '请补全记录时间', icon: 'none' });
    const currentUserId = getApp().globalData.userId;
    const original = Store.getRecords().find((item) => String(item.id) === this.recordId
      && hasValue(item.userId) && hasValue(currentUserId) && String(item.userId) === String(currentUserId));
    if (!original) return wx.showToast({ title: '这条记录目前不能编辑', icon: 'none' });
    const has = (key) => Object.prototype.hasOwnProperty.call(original, key);
    const updated = {
      ...original,
      consumedAt: `${this.data.date}T${this.data.time}:00`,
      updatedAt: new Date().toISOString()
    };
    if (has('title') || !has('name')) updated.title = String(this.data.genericTitle).trim();
    else updated.name = String(this.data.genericTitle).trim();
    const descriptionKey = ['description', 'details', 'note', 'notes'].find(has) || 'description';
    updated[descriptionKey] = String(this.data.genericDescription || '').trim();
    const locationKey = has('locationAddress') || !has('location') ? 'locationAddress' : 'location';
    updated[locationKey] = String(this.data.genericLocation || '').trim();
    Store.saveRecords(Store.getRecords().map((item) => String(item.id) === this.recordId
      && hasValue(item.userId) && String(item.userId) === String(currentUserId) ? updated : item));
    wx.showToast({ title: '已保存修改', icon: 'success' });
    this.genericDirty = false;
    this.setData({ mode: 'view' }, () => this.refresh());
  },
  deleteRecord() {
    this.setData({ moreOpen: false });
    if (!this.data.canEdit) return;
    wx.showModal({
      title: '删除这条记录？', content: '删除后无法恢复。', confirmText: '删除', confirmColor: '#a14a3b',
      success: (result) => {
        if (!result.confirm) return;
        const currentUserId = getApp().globalData.userId;
        const records = Store.getRecords();
        Store.saveRecords(records.filter((item) => !(String(item.id) === this.recordId
          && hasValue(item.userId) && String(item.userId) === String(currentUserId))));
        wx.navigateBack({ fail: () => wx.reLaunch({ url: '/pages/index/index' }) });
      }
    });
  },
  previewPhoto(event) {
    const index = Number(event.currentTarget.dataset.index) || 0;
    if (this.data.detail.kind === 'meal') {
      wx.navigateTo({ url: `/pages/meal-preview/meal-preview?recordId=${encodeURIComponent(this.recordId)}&index=${index}` });
      return;
    }
    const urls = this.data.detail.photos.map((photo) => photo.photo);
    if (urls.length) wx.previewImage({ current: urls[index], urls });
  },
  showLocation() {
    const location = this.data.detail && this.data.detail.location;
    if (!location || !location.canShowMap) return wx.showToast({ title: '这条记录没有地图坐标', icon: 'none' });
    if (!wx.openLocation) return wx.showToast({ title: '当前环境不支持打开地图', icon: 'none' });
    try {
      wx.openLocation({
        latitude: location.latitude,
        longitude: location.longitude,
        name: location.label,
        address: location.address || location.label,
        scale: 17,
        fail: () => wx.showToast({ title: '地图暂时无法打开', icon: 'none' })
      });
    } catch (error) {
      wx.showToast({ title: '地图暂时无法打开', icon: 'none' });
    }
  }
});
