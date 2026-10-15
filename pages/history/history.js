const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

const RECORD_TYPE_LABELS = { drink: '饮品', meal: '吃饭' };

function recordTypeKey(record) {
  return record && record.type ? String(record.type) : 'drink';
}

function recordTypeLabel(record, key) {
  const explicitLabel = String((record && (record.typeLabel || record.typeName)) || '').trim();
  return explicitLabel || RECORD_TYPE_LABELS[key] || key;
}

function isCoordinateLabel(value) {
  return /^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$/.test(String(value || ''));
}

function recordUserId(record) {
  return String(record.userId || '__unknown__');
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
  data: {
    records: [], hasRecords: false,
    filterOpen: false, filterUsers: [], selectedUserIds: [], draftUserIds: [],
    filterTypes: [], selectedTypeKeys: [], draftTypeKeys: [],
    startDate: '', endDate: '', draftStartDate: '', draftEndDate: '', hasActiveFilters: false
  },
  onShow() { this.refresh(); },
  refresh() {
    const { drinks } = Store.catalog();
    const cupSizes = Store.getCupSizes();
    const allRecords = Domain.listRecords(Store.getRecords());
    const uniqueUsers = new Map();
    const currentUserId = getApp().globalData.userId;
    allRecords.forEach((record) => {
      const id = recordUserId(record);
      const fallbackName = id === '__unknown__' ? '未登记用户' : id === currentUserId ? '我' : '未命名用户';
      if (!uniqueUsers.has(id)) uniqueUsers.set(id, { id, label: record.userName || fallbackName });
    });
    const userOptions = Array.from(uniqueUsers.values()).sort((a, b) => a.label.localeCompare(b.label));
    const availableIds = userOptions.map((user) => user.id);
    const previousIds = this.data.selectedUserIds || [];
    const knownIds = this.knownUserIds || [];
    const newlyAvailableIds = this.userFiltersInitialized ? availableIds.filter((id) => !knownIds.includes(id)) : [];
    let selectedUserIds = this.userFiltersInitialized
      ? previousIds.filter((id) => availableIds.includes(id))
      : availableIds.slice();
    if (this.userFiltersInitialized) {
      newlyAvailableIds.forEach((id) => { if (!selectedUserIds.includes(id)) selectedUserIds.push(id); });
    }
    this.userFiltersInitialized = true;
    this.knownUserIds = availableIds;
    const selectedIds = new Set(selectedUserIds);

    const typeOptionsByKey = new Map();
    allRecords.forEach((record) => {
      const key = recordTypeKey(record);
      const label = recordTypeLabel(record, key);
      if (!typeOptionsByKey.has(key) || typeOptionsByKey.get(key).label === key) {
        typeOptionsByKey.set(key, { key, label });
      }
    });
    const typeOptions = Array.from(typeOptionsByKey.values()).sort((a, b) => {
      const typeOrder = (key) => key === 'drink' ? 0 : key === 'meal' ? 1 : 2;
      return typeOrder(a.key) - typeOrder(b.key)
        || a.label.localeCompare(b.label);
    });
    const availableTypeKeys = typeOptions.map((type) => type.key);
    const previousTypeKeys = this.data.selectedTypeKeys || [];
    const knownTypeKeys = this.knownRecordTypeKeys || [];
    const newlyAvailableTypeKeys = this.recordTypeFiltersInitialized
      ? availableTypeKeys.filter((key) => !knownTypeKeys.includes(key))
      : [];
    let selectedTypeKeys = this.recordTypeFiltersInitialized
      ? previousTypeKeys.filter((key) => availableTypeKeys.includes(key))
      : availableTypeKeys.slice();
    newlyAvailableTypeKeys.forEach((key) => {
      if (!selectedTypeKeys.includes(key)) selectedTypeKeys.push(key);
    });
    this.recordTypeFiltersInitialized = true;
    this.knownRecordTypeKeys = availableTypeKeys;
    const selectedTypeSet = new Set(selectedTypeKeys);

    const visibleRecords = allRecords.filter((record) => {
      const dateKey = String(record.consumedAt || '').slice(0, 10);
      return selectedIds.has(recordUserId(record))
        && selectedTypeSet.has(recordTypeKey(record))
        && (!this.data.startDate || dateKey >= this.data.startDate)
        && (!this.data.endDate || dateKey <= this.data.endDate);
    });
    const records = visibleRecords.map((record) => {
      const date = new Date(record.consumedAt);
      const typeKey = recordTypeKey(record);
      const typeLabel = recordTypeLabel(record, typeKey);
      const common = { ...record, typeKey, typeLabel, dateLabel: `${date.getMonth() + 1}月${date.getDate()}日`, dateKey: record.consumedAt.slice(0, 10),
        timeLabel: record.consumedAt.slice(11, 16), userName: record.userName || '我' };
      if (Domain.isMealRecord(record)) {
        const dishes = record.dishes || [];
        return { ...common, kind: 'meal', dishes, ...mealPhotoStack(dishes, 168, 22) };
      }
      if (Domain.isDrinkRecord(record)) {
        const nutrition = Domain.nutritionForRecord(record, Domain.findDrink(drinks, record.drinkId), cupSizes);
        const servingLabel = Domain.formatServingLabel(record) || '未选择';
        const locationLabel = isCoordinateLabel(record.location) ? '' : (record.location || '');
        return { ...common, kind: 'drink', nutritionLabel: nutrition.label, servingLabel,
          cupLabel: Domain.formatCupLabel(record), locationLabel };
      }
      return { ...common, kind: 'other', displayName: record.title || record.name || typeLabel,
        displayDetails: record.description || record.note || '' };
    });
    records.forEach((record, index) => {
      record.isLast = index === records.length - 1;
      record.showDate = index === 0 || record.dateKey !== records[index - 1].dateKey;
    });
    const draftUserIds = this.data.filterOpen
      ? Array.from(new Set([...(this.data.draftUserIds || []), ...newlyAvailableIds])).filter((id) => availableIds.includes(id))
      : selectedUserIds;
    const draftIds = new Set(draftUserIds);
    const filterUsers = userOptions.map((user) => ({ ...user, selected: selectedIds.has(user.id), draftSelected: draftIds.has(user.id) }));
    const draftTypeKeys = this.data.filterOpen
      ? Array.from(new Set([...(this.data.draftTypeKeys || []), ...newlyAvailableTypeKeys])).filter((key) => availableTypeKeys.includes(key))
      : selectedTypeKeys;
    const draftTypeSet = new Set(draftTypeKeys);
    const filterTypes = typeOptions.map((type) => ({ ...type, selected: selectedTypeSet.has(type.key), draftSelected: draftTypeSet.has(type.key) }));
    const hasActiveFilters = !!this.data.startDate || !!this.data.endDate
      || selectedUserIds.length !== availableIds.length || selectedTypeKeys.length !== availableTypeKeys.length;
    this.setData({ records, hasRecords: records.length > 0, filterUsers, selectedUserIds, filterTypes, selectedTypeKeys,
      draftUserIds, draftTypeKeys,
      hasActiveFilters });
  },
  toggleFilter() {
    if (this.data.filterOpen) return this.setData({ filterOpen: false });
    const selectedUserIds = this.data.selectedUserIds.slice();
    const selectedIds = new Set(selectedUserIds);
    this.setData({ filterOpen: true, draftStartDate: this.data.startDate, draftEndDate: this.data.endDate,
      draftUserIds: selectedUserIds,
      draftTypeKeys: this.data.selectedTypeKeys.slice(),
      filterUsers: this.data.filterUsers.map((user) => ({ ...user, draftSelected: selectedIds.has(user.id) })),
      filterTypes: this.data.filterTypes.map((type) => ({ ...type, draftSelected: this.data.selectedTypeKeys.includes(type.key) })) });
  },
  onStartDateChange(event) { this.setData({ draftStartDate: event.detail.value }); },
  onEndDateChange(event) { this.setData({ draftEndDate: event.detail.value }); },
  toggleFilterUser(event) {
    const userId = String(event.currentTarget.dataset.userId);
    const selected = new Set(this.data.draftUserIds);
    if (selected.has(userId)) selected.delete(userId);
    else selected.add(userId);
    const draftUserIds = Array.from(selected);
    const draftIds = new Set(draftUserIds);
    this.setData({ draftUserIds, filterUsers: this.data.filterUsers.map((user) => ({ ...user, draftSelected: draftIds.has(user.id) })) });
  },
  selectAllFilterUsers() {
    const draftUserIds = this.data.filterUsers.map((user) => user.id);
    this.setData({ draftUserIds, filterUsers: this.data.filterUsers.map((user) => ({ ...user, draftSelected: true })) });
  },
  toggleFilterType(event) {
    const typeKey = String(event.currentTarget.dataset.typeKey);
    const selected = new Set(this.data.draftTypeKeys);
    if (selected.has(typeKey)) selected.delete(typeKey);
    else selected.add(typeKey);
    const draftTypeKeys = Array.from(selected);
    const draftTypeSet = new Set(draftTypeKeys);
    this.setData({ draftTypeKeys, filterTypes: this.data.filterTypes.map((type) => ({ ...type, draftSelected: draftTypeSet.has(type.key) })) });
  },
  selectAllFilterTypes() {
    const draftTypeKeys = this.data.filterTypes.map((type) => type.key);
    this.setData({ draftTypeKeys, filterTypes: this.data.filterTypes.map((type) => ({ ...type, draftSelected: true })) });
  },
  resetFilterDraft() {
    const draftUserIds = this.data.filterUsers.map((user) => user.id);
    const draftTypeKeys = this.data.filterTypes.map((type) => type.key);
    this.setData({ draftStartDate: '', draftEndDate: '', draftUserIds, draftTypeKeys,
      filterUsers: this.data.filterUsers.map((user) => ({ ...user, draftSelected: true })),
      filterTypes: this.data.filterTypes.map((type) => ({ ...type, draftSelected: true })) });
  },
  applyFilters() {
    const { draftStartDate: startDate, draftEndDate: endDate } = this.data;
    if (startDate && endDate && startDate > endDate) {
      return wx.showToast({ title: '开始日期不能晚于结束日期', icon: 'none' });
    }
    this.setData({ startDate, endDate, selectedUserIds: this.data.draftUserIds.slice(), selectedTypeKeys: this.data.draftTypeKeys.slice(), filterOpen: false }, () => this.refresh());
  },
  openRecord(event) {
    const record = Store.getRecords().find((item) => item.id === event.currentTarget.dataset.id);
    if (!record) return;
    wx.navigateTo({ url: `/pages/record-detail/record-detail?id=${encodeURIComponent(record.id)}` });
  },
  previewPhoto(event) {
    const { photo, recordId, photoIndex } = event.currentTarget.dataset;
    if (recordId) {
      wx.navigateTo({ url: `/pages/meal-preview/meal-preview?recordId=${encodeURIComponent(recordId)}&index=${Number(photoIndex) || 0}` });
      return;
    }
    if (photo) wx.previewImage({ current: photo, urls: [photo] });
  }
});
