const Domain = require('../../utils/domain');
const Store = require('../../utils/store');

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function parseOptionalNutrition(value) {
  const text = String(value === undefined || value === null ? '' : value).trim();
  if (!text) return { valid: true, value: null };
  const number = Number(text);
  return { valid: Number.isFinite(number) && number >= 0, value: number };
}

function currentDateTime() {
  const d = new Date();
  return { date: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`,
    time: `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` };
}

const COMMON_CUP_TYPES = ['小杯', '中杯', '大杯', '超大杯'];
const COMMON_SWEETNESS = ['不另外加糖', '三分糖', '五分糖', '七分糖', '全糖'];
const COMMON_SERVING_OPTIONS = ['正常冰', '少冰', '多冰', '去冰', '常温', '热饮'];
const PHOTO_THUMBNAIL_SIZE = 360;

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

function createPhotoThumbnail(page, filePath) {
  return new Promise((resolve) => {
    try {
      wx.createSelectorQuery().in(page).select('#thumbnailCanvas').fields({ node: true }).exec((result) => {
        const canvas = result && result[0] && result[0].node;
        if (!canvas) return resolve('');
        canvas.width = PHOTO_THUMBNAIL_SIZE;
        canvas.height = PHOTO_THUMBNAIL_SIZE;
        const context = canvas.getContext('2d');
        const image = canvas.createImage();
        image.onload = () => {
          const side = Math.min(image.width, image.height);
          const sourceX = (image.width - side) / 2;
          const sourceY = (image.height - side) / 2;
          try {
            context.clearRect(0, 0, PHOTO_THUMBNAIL_SIZE, PHOTO_THUMBNAIL_SIZE);
            context.drawImage(image, sourceX, sourceY, side, side, 0, 0, PHOTO_THUMBNAIL_SIZE, PHOTO_THUMBNAIL_SIZE);
            wx.canvasToTempFilePath({
              canvas, x: 0, y: 0, width: PHOTO_THUMBNAIL_SIZE, height: PHOTO_THUMBNAIL_SIZE,
              destWidth: PHOTO_THUMBNAIL_SIZE, destHeight: PHOTO_THUMBNAIL_SIZE,
              fileType: 'jpg', quality: 0.82,
              success: (exported) => resolve(exported.tempFilePath),
              fail: () => resolve('')
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

function cupTypeOptions(selected, cupSizes, selectedSizeMl) {
  const pairs = Array.isArray(cupSizes) && cupSizes.length
    ? cupSizes.filter((item) => item && item.cupType).map((item) => ({ cupType: item.cupType, sizeMl: item.sizeMl || '' }))
    : COMMON_CUP_TYPES.map((cupType) => ({ cupType, sizeMl: '' }));
  let selectedPair = pairs.find((item) => item.cupType === selected);
  if (selected && !selectedPair) {
    selectedPair = { cupType: selected, sizeMl: selectedSizeMl || '' };
    pairs.push(selectedPair);
  } else if (selectedPair && selectedSizeMl) {
    selectedPair.sizeMl = selectedSizeMl;
  }
  const seen = new Set();
  return pairs.filter((item) => {
    const key = `${item.cupType}::${item.sizeMl}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).map((item) => ({
    value: `${item.cupType}::${item.sizeMl}`,
    cupType: item.cupType,
    sizeMl: item.sizeMl,
    label: item.cupType,
    selected: !!selectedPair && item.cupType === selectedPair.cupType && String(item.sizeMl) === String(selectedPair.sizeMl)
  }));
}

function choiceOptions(options, selected, fallback) {
  const values = (Array.isArray(options) && options.length ? options : fallback).slice();
  if (selected && !values.includes(selected)) values.push(selected);
  return values.map((value) => ({ value, label: value, selected: value === selected }));
}

function sweetnessOptions(options, selected) {
  return choiceOptions(options, selected, COMMON_SWEETNESS);
}

function parseCoordinateLabel(value) {
  const match = String(value || '').match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (!match) return null;
  const latitude = Number(match[1]);
  const longitude = Number(match[2]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  return { latitude, longitude };
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

function dateParts(value) {
  const match = String(value || '').match(/^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const date = new Date(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second));
  if (date.getFullYear() !== Number(year) || date.getMonth() !== Number(month) - 1 || date.getDate() !== Number(day)) return null;
  return { date: `${year}-${month}-${day}`, time: `${hour}:${minute}` };
}

function readIfd(view, tiffStart, offset, littleEndian) {
  const start = tiffStart + offset;
  if (start < tiffStart || start + 2 > view.byteLength) return {};
  const count = view.getUint16(start, littleEndian);
  const result = {};
  for (let i = 0; i < count; i += 1) {
    const entryOffset = start + 2 + i * 12;
    if (entryOffset + 12 > view.byteLength) break;
    const tag = view.getUint16(entryOffset, littleEndian);
    const type = view.getUint16(entryOffset + 2, littleEndian);
    const itemCount = view.getUint32(entryOffset + 4, littleEndian);
    const unitSize = ({ 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 })[type] || 0;
    const byteLength = itemCount * unitSize;
    const dataOffset = byteLength <= 4 ? entryOffset + 8 : tiffStart + view.getUint32(entryOffset + 8, littleEndian);
    if (dataOffset < tiffStart || dataOffset + Math.min(byteLength, 4) > view.byteLength) continue;
    result[tag] = { type, count: itemCount, dataOffset };
  }
  return result;
}

function ifdString(view, entry) {
  if (!entry || entry.type !== 2) return '';
  let value = '';
  for (let i = 0; i < entry.count && entry.dataOffset + i < view.byteLength; i += 1) {
    const code = view.getUint8(entry.dataOffset + i);
    if (!code) break;
    value += String.fromCharCode(code);
  }
  return value.trim();
}

function ifdRationals(view, entry, littleEndian) {
  if (!entry || entry.type !== 5 || entry.count < 3 || entry.dataOffset + 24 > view.byteLength) return null;
  const values = [];
  for (let i = 0; i < 3; i += 1) {
    const numerator = view.getUint32(entry.dataOffset + i * 8, littleEndian);
    const denominator = view.getUint32(entry.dataOffset + i * 8 + 4, littleEndian);
    if (!denominator) return null;
    values.push(numerator / denominator);
  }
  return values;
}

function parseExif(buffer) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength < 12) return {};
  const view = new DataView(buffer);
  if (view.getUint16(0, false) !== 0xffd8) return {};
  let offset = 2;
  while (offset + 4 < view.byteLength) {
    if (view.getUint8(offset) !== 0xff) break;
    while (offset < view.byteLength && view.getUint8(offset) === 0xff) offset += 1;
    const marker = view.getUint8(offset);
    if (marker === 0xd9 || marker === 0xda) break;
    if (offset + 3 >= view.byteLength) break;
    const segmentLength = view.getUint16(offset + 1, false);
    const payload = offset + 3;
    if (segmentLength < 2 || payload + segmentLength - 2 > view.byteLength) break;
    if (marker === 0xe1 && payload + 14 < view.byteLength
      && view.getUint8(payload) === 0x45 && view.getUint8(payload + 1) === 0x78
      && view.getUint8(payload + 2) === 0x69 && view.getUint8(payload + 3) === 0x66) {
      const tiffStart = payload + 6;
      const byteOrder = view.getUint16(tiffStart, false);
      const littleEndian = byteOrder === 0x4949;
      if (!littleEndian && byteOrder !== 0x4d4d) return {};
      if (view.getUint16(tiffStart + 2, littleEndian) !== 42) return {};
      const ifd0 = readIfd(view, tiffStart, view.getUint32(tiffStart + 4, littleEndian), littleEndian);
      const exifIfd = ifd0[0x8769] ? readIfd(view, tiffStart, view.getUint32(ifd0[0x8769].dataOffset, littleEndian), littleEndian) : {};
      const gpsIfd = ifd0[0x8825] ? readIfd(view, tiffStart, view.getUint32(ifd0[0x8825].dataOffset, littleEndian), littleEndian) : {};
      const timestamp = dateParts(ifdString(view, exifIfd[0x9003]) || ifdString(view, exifIfd[0x9004]) || ifdString(view, ifd0[0x0132]));
      const latitude = ifdRationals(view, gpsIfd[0x0002], littleEndian);
      const longitude = ifdRationals(view, gpsIfd[0x0004], littleEndian);
      let locationCoordinates = null;
      if (latitude && longitude) {
        const latRef = ifdString(view, gpsIfd[0x0001]);
        const lonRef = ifdString(view, gpsIfd[0x0003]);
        const lat = (latitude[0] + latitude[1] / 60 + latitude[2] / 3600) * (latRef === 'S' ? -1 : 1);
        const lon = (longitude[0] + longitude[1] / 60 + longitude[2] / 3600) * (lonRef === 'W' ? -1 : 1);
        locationCoordinates = { latitude: lat, longitude: lon };
      }
      return { timestamp, locationCoordinates };
    }
    offset = payload + segmentLength - 2;
  }
  return {};
}

function readPhotoExif(filePath) {
  return new Promise((resolve) => {
    try {
      wx.getFileSystemManager().readFile({ filePath, success: (result) => {
        try { resolve(parseExif(result.data)); } catch (error) { resolve({}); }
      }, fail: () => resolve({}) });
    } catch (error) {
      resolve({});
    }
  });
}

function drinkEditSnapshot(data) {
  return JSON.stringify({
    custom: data.custom, brandId: data.selectedBrand && data.selectedBrand.id, drinkId: data.selectedDrink && data.selectedDrink.id,
    brandName: data.brandName, drinkName: data.drinkName, sizeMl: data.sizeMl, cupType: data.cupType,
    sweetness: data.sweetness, servingOption: data.servingOption, temperature: data.temperature, ice: data.ice,
    date: data.date, time: data.time, location: data.location, locationAddress: data.locationAddress,
    locationLatitude: data.locationLatitude, locationLongitude: data.locationLongitude, notes: data.notes,
    photo: data.photo, photoThumbnail: data.photoThumbnail, energyKcal: data.energyKcal, sugarG: data.sugarG,
    caffeineMg: data.caffeineMg
  });
}

Page({
  data: {
    editing: false, fromDetail: false, recordId: '', custom: false, creatingForBrand: false, brands: [], drinks: [], selectedBrand: {}, selectedDrink: {},
    brandQuery: '', drinkQuery: '', drinkName: '', brandName: '', ...currentDateTime(),
    sizeMl: '', cupType: '', sweetness: '', servingOption: '', temperature: '', ice: '',
    location: '', locationAddress: '', locationLatitude: '', locationLongitude: '', notes: '', photo: '', photoThumbnail: '', photoPending: false,
    energyKcal: '', sugarG: '', caffeineMg: '', showBrandPicker: false, showDrinkPicker: false,
    cupOptions: cupTypeOptions(''), sweetnessOptions: sweetnessOptions(null, ''),
    servingOptions: choiceOptions(null, '', COMMON_SERVING_OPTIONS),
    timeHint: '默认使用填写时的时间；可手动调整', locationHint: '可搜索并确认地图地点，也可以留空'
  },
  onLoad(query) {
    this.setData({ fromDetail: query.fromDetail === '1' });
    const catalog = Store.catalog();
    this.catalog = catalog;
    this.globalCupSizes = Store.getCupSizes();
    this.setData({ brands: Domain.searchBrands(catalog.brands, ''), cupOptions: cupTypeOptions('', this.globalCupSizes) });
    if (query.id) this.loadRecord(query.id);
    else {
      this.setData(currentDateTime());
    }
    this.refreshCatalog();
  },
  refreshCatalog() {
    return Store.syncCatalog().then((result) => {
      if (!result || !result.updated) return;
      const catalog = Store.catalog();
      this.catalog = catalog;
      const selectedBrandId = this.data.selectedBrand && this.data.selectedBrand.id;
      const selectedDrinkId = this.data.selectedDrink && this.data.selectedDrink.id;
      const selectedBrand = selectedBrandId && catalog.brands.find((item) => item.id === selectedBrandId);
      const selectedDrink = selectedDrinkId && Domain.findDrink(catalog.drinks, selectedDrinkId);
      const changes = {
        brands: Domain.searchBrands(catalog.brands, this.data.brandQuery),
        drinks: Domain.searchDrinks(catalog.drinks, selectedBrandId || '', this.data.drinkQuery)
      };
      if (selectedBrand) changes.selectedBrand = selectedBrand;
      if (selectedDrink) {
        changes.selectedDrink = selectedDrink;
        changes.cupOptions = cupTypeOptions(this.data.cupType, this.globalCupSizes, this.data.sizeMl);
        changes.sweetnessOptions = sweetnessOptions(selectedDrink.sweetnessOptions, this.data.sweetness);
        changes.servingOptions = choiceOptions(selectedDrink.servingOptions, this.data.servingOption, COMMON_SERVING_OPTIONS);
      }
      this.setData(changes);
    }).catch(() => {});
  },
  loadRecord(id) {
    const record = Store.getRecords().find((item) => item.id === id && item.userId === getApp().globalData.userId);
    if (!record) return wx.showToast({ title: '记录不存在', icon: 'none' });
    const brand = this.catalog.brands.find((item) => item.id === record.brandId) || {};
    const drink = Domain.findDrink(this.catalog.drinks, record.drinkId) || {};
    const serving = Domain.resolveTemperatureIce(record);
    const servingOption = record.servingOption || serving.ice || serving.temperature;
    const legacyCoordinates = parseCoordinateLabel(record.location);
    const locationName = legacyCoordinates ? '' : (record.location || '');
    const locationLatitude = record.locationLatitude !== null && record.locationLatitude !== undefined
      ? Number(record.locationLatitude) : legacyCoordinates && legacyCoordinates.latitude;
    const locationLongitude = record.locationLongitude !== null && record.locationLongitude !== undefined
      ? Number(record.locationLongitude) : legacyCoordinates && legacyCoordinates.longitude;
    if (Number.isFinite(locationLatitude) && Number.isFinite(locationLongitude) && !legacyCoordinates) {
      this.currentMapCenter = { latitude: locationLatitude, longitude: locationLongitude };
    } else if (legacyCoordinates) {
      this.currentMapCenter = wgs84ToGcj02(legacyCoordinates.latitude, legacyCoordinates.longitude);
    }
    this.locationEdited = !!locationName;
    const savedNutritionInput = record.nutritionInputPer100Ml || (drink.custom && drink.nutritionPerUnit
      && drink.nutritionPerUnit.unit === 'ml' ? drink.nutritionPerUnit : {});
    const resolvedCupSize = record.sizeMl || Domain.resolveCupSizeMl(record, this.globalCupSizes) || '';
    this.setData({ editing: true, recordId: id, custom: !drink || drink.custom, selectedBrand: brand, selectedDrink: drink,
      brandName: record.brandName, drinkName: record.drinkName, date: record.consumedAt.slice(0, 10), time: record.consumedAt.slice(11, 16),
      sizeMl: resolvedCupSize ? String(resolvedCupSize) : '', cupType: record.cupType || '', sweetness: record.sweetness,
      energyKcal: savedNutritionInput.energyKcal === null || savedNutritionInput.energyKcal === undefined ? '' : String(savedNutritionInput.energyKcal),
      sugarG: savedNutritionInput.sugarG === null || savedNutritionInput.sugarG === undefined ? '' : String(savedNutritionInput.sugarG),
      caffeineMg: savedNutritionInput.caffeineMg === null || savedNutritionInput.caffeineMg === undefined ? '' : String(savedNutritionInput.caffeineMg),
      servingOption, temperature: serving.temperature, ice: serving.ice,
      location: locationName, locationAddress: record.locationAddress || '', locationLatitude: Number.isFinite(locationLatitude) ? locationLatitude : '',
      locationLongitude: Number.isFinite(locationLongitude) ? locationLongitude : '', notes: record.notes, photo: record.photo,
      photoThumbnail: record.photoThumbnail || record.photo || '',
      cupOptions: cupTypeOptions(record.cupType || '', this.globalCupSizes, record.sizeMl), sweetnessOptions: sweetnessOptions(drink && drink.sweetnessOptions, record.sweetness),
      servingOptions: choiceOptions(drink && drink.servingOptions, servingOption, COMMON_SERVING_OPTIONS),
      timeHint: '已保存的记录时间，可手动调整',
      locationHint: legacyCoordinates ? '旧记录保存了坐标；可重新搜索并确认地图地点' : locationName ? '已保存地图地点；可重新搜索并确认' : '可搜索并确认地图地点，也可以留空' }, () => {
      this.editSnapshot = drinkEditSnapshot(this.data);
    });
  },
  cancelEdit() {
    const leave = () => wx.navigateBack();
    if (drinkEditSnapshot(this.data) === this.editSnapshot) return leave();
    wx.showModal({ title: '放弃修改？', content: '尚未保存的内容会丢失。', confirmText: '放弃修改', confirmColor: '#9b5148',
      success: (result) => { if (result.confirm) leave(); } });
  },
  updateField(event) {
    const field = event.currentTarget.dataset.field;
    const value = event.detail.value;
    const changes = { [field]: value };
    this.setData(changes);
  },
  toggleBrandPicker() { this.setData({ showBrandPicker: !this.data.showBrandPicker, showDrinkPicker: false }); },
  toggleDrinkPicker() { this.setData({ showDrinkPicker: !this.data.showDrinkPicker, showBrandPicker: false }); },
  onBrandSearch(event) {
    const query = event.detail.value;
    this.setData({ brandQuery: query, brands: Domain.searchBrands(this.catalog.brands, query) });
  },
  selectBrand(event) {
    const brand = this.catalog.brands.find((item) => item.id === event.currentTarget.dataset.id);
    this.setData({ selectedBrand: brand, selectedDrink: null, brandName: brand.name, drinkName: '', drinkQuery: '',
      drinks: Domain.searchDrinks(this.catalog.drinks, brand.id, ''), showBrandPicker: false, custom: false, creatingForBrand: false });
  },
  onDrinkSearch(event) {
    const query = event.detail.value;
    this.setData({ drinkQuery: query, drinks: Domain.searchDrinks(this.catalog.drinks, this.data.selectedBrand && this.data.selectedBrand.id, query) });
  },
  selectDrink(event) {
    const drink = Domain.findDrink(this.catalog.drinks, event.currentTarget.dataset.id);
    this.setData({ selectedDrink: drink, drinkName: drink.name, sizeMl: '', cupType: '',
      cupOptions: cupTypeOptions('', this.globalCupSizes), sweetnessOptions: sweetnessOptions(drink.sweetnessOptions, ''),
      servingOptions: choiceOptions(drink.servingOptions, '', COMMON_SERVING_OPTIONS),
      sweetness: '', servingOption: '', temperature: '', ice: '', showDrinkPicker: false, custom: false });
  },
  addMissingDrink() {
    if (this.data.selectedBrand && this.data.selectedBrand.id) {
      const brand = this.data.selectedBrand;
      this.setData({ custom: true, creatingForBrand: true, selectedDrink: null, brandName: brand.name, drinkName: '',
        sizeMl: '', cupType: '', sweetness: '', energyKcal: '', sugarG: '', caffeineMg: '',
        cupOptions: cupTypeOptions('', this.globalCupSizes), sweetnessOptions: sweetnessOptions(null, ''),
        servingOptions: choiceOptions(null, '', COMMON_SERVING_OPTIONS), servingOption: '', temperature: '', ice: '',
        showDrinkPicker: false, showBrandPicker: false });
      return;
    }
    this.enableCustom();
  },
  cancelAddDrink() {
    const brand = this.data.selectedBrand;
    this.setData({ custom: false, creatingForBrand: false, selectedDrink: null, drinkName: '', energyKcal: '', sugarG: '', caffeineMg: '',
      drinks: Domain.searchDrinks(this.catalog.drinks, brand && brand.id, this.data.drinkQuery),
      sweetnessOptions: sweetnessOptions(null, ''), servingOptions: choiceOptions(null, '', COMMON_SERVING_OPTIONS) });
  },
  enableCustom() { this.setData({ custom: true, creatingForBrand: false, selectedDrink: null, selectedBrand: null, brandName: '', drinkName: '', sizeMl: '', cupType: '', sweetness: '',
    cupOptions: cupTypeOptions('', this.globalCupSizes), sweetnessOptions: sweetnessOptions(null, ''),
    servingOptions: choiceOptions(null, '', COMMON_SERVING_OPTIONS),
    servingOption: '', temperature: '', ice: '', showDrinkPicker: false, showBrandPicker: false }); },
  selectCup(event) {
    const cupType = event.currentTarget.dataset.cupType || '';
    const sizeMl = event.currentTarget.dataset.sizeMl || '';
    this.setData({ cupType, sizeMl, cupOptions: cupTypeOptions(cupType, this.globalCupSizes, sizeMl) });
  },
  selectSweetness(event) {
    const selected = event.currentTarget.dataset.value;
    const sweetness = this.data.sweetness === selected ? '' : selected;
    this.setData({ sweetness, sweetnessOptions: sweetnessOptions(this.data.selectedDrink && this.data.selectedDrink.sweetnessOptions, sweetness) });
  },
  selectServing(event) {
    const selected = event.currentTarget.dataset.value;
    const servingOption = this.data.servingOption === selected ? '' : selected;
    const serving = Domain.resolveTemperatureIce({ servingOption });
    this.setData({ servingOption, temperature: serving.temperature, ice: serving.ice,
      servingOptions: choiceOptions(this.data.selectedDrink && this.data.selectedDrink.servingOptions, servingOption, COMMON_SERVING_OPTIONS) });
  },
  choosePlace() {
    if (!wx.chooseLocation) {
      this.setData({ locationHint: '当前环境不支持地图选点，请在微信中打开后选择地点' });
      return;
    }
    const center = this.photoMapCenter || this.currentMapCenter;
    const options = { success: (result) => {
      const location = result.name || result.address || '';
      this.locationEdited = true;
      this.locationFromPhoto = false;
      this.currentMapCenter = { latitude: result.latitude, longitude: result.longitude };
      this.setData({ location, locationAddress: result.address || '', locationLatitude: result.latitude, locationLongitude: result.longitude,
        locationHint: location ? '已在地图中确认地点；可重新搜索更换' : '已确认地图坐标' });
    }, fail: (error) => {
      if (error && String(error.errMsg || '').includes('cancel')) return;
      this.setData({ locationHint: '地图选点未完成，可重试或留空' });
    } };
    if (center && Number.isFinite(Number(center.latitude)) && Number.isFinite(Number(center.longitude))) {
      options.latitude = Number(center.latitude);
      options.longitude = Number(center.longitude);
    }
    try {
      wx.chooseLocation(options);
    } catch (error) {
      this.setData({ locationHint: '当前环境无法打开地图，请在微信中打开后选择地点' });
    }
  },
  choosePhoto() {
    wx.chooseMedia({ count: 1, mediaType: ['image'], sourceType: ['album', 'camera'], sizeType: ['original'], success: (res) => {
      const tempFile = res.tempFiles && res.tempFiles[0];
      if (!tempFile || !tempFile.tempFilePath) return;
      const tempFilePath = tempFile.tempFilePath;
      const photoToken = `${Date.now()}-${Math.random()}`;
      this.photoToken = photoToken;
      this.photoBusy = true;
      this.setData({ photoPending: true });
      const previousThumbnail = this.thumbnailQueue || Promise.resolve('');
      const photoWork = readPhotoExif(tempFilePath).then((metadata) => {
        if (this.photoToken !== photoToken) return null;
        const updates = {};
        if (metadata.timestamp && !this.timeEdited) Object.assign(updates, metadata.timestamp);
        if (metadata.locationCoordinates && !this.locationEdited) {
          this.locationFromPhoto = true;
          this.photoMapCenter = wgs84ToGcj02(metadata.locationCoordinates.latitude, metadata.locationCoordinates.longitude);
          updates.locationHint = '已优先读取照片位置；点选地图可选择地点名称';
        }
        if (metadata.timestamp && !this.timeEdited) updates.timeHint = '已优先读取照片拍摄时间；可自行修改';
        if (Object.keys(updates).length) this.setData(updates);
        return saveLocalFile(tempFilePath);
      }).then((photo) => {
        if (this.photoToken !== photoToken) return null;
        if (!photo) throw new Error('photo-save-failed');
        const thumbnailWork = previousThumbnail.then(() => createPhotoThumbnail(this, photo));
        this.thumbnailQueue = thumbnailWork.then(() => '', () => '');
        return thumbnailWork.then((path) => path ? saveLocalFile(path) : '')
          .then((thumbnail) => ({ photo, photoThumbnail: thumbnail || photo }));
      }).then((result) => {
        if (this.photoToken !== photoToken || !result) return result;
        this.photoBusy = false;
        this.setData({ ...result, photoPending: false });
        return result;
      }).catch(() => {
        if (this.photoToken === photoToken) {
          this.photoBusy = false;
          this.setData({ photoPending: false });
          wx.showToast({ title: '照片保存失败，请重试', icon: 'none' });
        }
        return null;
      });
      this.photoWork = photoWork;
    } });
  },
  removePhoto() {
    this.photoToken = `${Date.now()}-removed`;
    this.photoBusy = false;
    this.photoWork = null;
    this.setData({ photo: '', photoThumbnail: '', photoPending: false });
  },
  previewPhoto(event) {
    const photo = event && event.currentTarget && event.currentTarget.dataset.photo || this.data.photo;
    if (photo) wx.previewImage({ current: photo, urls: [photo] });
  },
  onDateChange(event) { this.timeEdited = true; this.setData({ date: event.detail.value, timeHint: '已自定义记录时间' }); },
  onTimeChange(event) { this.timeEdited = true; this.setData({ time: event.detail.value, timeHint: '已自定义记录时间' }); },
  save() {
    if (this.saving) return;
    if (this.photoBusy && this.photoWork) {
      this.saving = true;
      wx.showLoading({ title: '正在处理照片', mask: true });
      const waitForCurrentPhoto = () => {
        const work = this.photoWork;
        if (!work || !this.photoBusy) return Promise.resolve();
        return work.then(waitForCurrentPhoto, waitForCurrentPhoto);
      };
      waitForCurrentPhoto().then(() => {
        wx.hideLoading();
        this.saving = false;
        this.saveRecord();
      });
      return;
    }
    this.saveRecord();
  },
  saveRecord() {
    const userId = getApp().globalData.userId;
    let brandName = this.data.custom ? this.data.brandName.trim() : (this.data.selectedBrand && this.data.selectedBrand.name) || this.data.brandName.trim();
    let drinkName = this.data.custom ? this.data.drinkName.trim() : (this.data.selectedDrink && this.data.selectedDrink.name) || this.data.drinkName.trim();
    if (!brandName || !drinkName) return wx.showToast({ title: '请选择或填写品牌和饮品', icon: 'none' });
    const consumedAt = `${this.data.date}T${this.data.time}:00`;
    const records = Store.getRecords();
    const existing = this.data.editing ? records.find((item) => item.id === this.data.recordId && item.userId === userId) : null;
    const toppings = existing && Array.isArray(existing.toppings) ? existing.toppings : [];
    const sizeMl = this.data.sizeMl !== '' ? this.data.sizeMl : (existing && existing.sizeMl) || '';
    const cupType = this.data.cupType || (existing && existing.cupType) || '';
    const serving = Domain.resolveTemperatureIce({ servingOption: this.data.servingOption, temperature: this.data.temperature, ice: this.data.ice });
    const nutritionValues = {
      energyKcal: parseOptionalNutrition(this.data.energyKcal),
      sugarG: parseOptionalNutrition(this.data.sugarG),
      caffeineMg: parseOptionalNutrition(this.data.caffeineMg)
    };
    if (Object.keys(nutritionValues).some((key) => !nutritionValues[key].valid)) {
      return wx.showToast({ title: '营养数值须为 0 或更大的数字', icon: 'none' });
    }
    const nutritionEntered = Object.keys(nutritionValues).some((key) => nutritionValues[key].value !== null);
    if (this.data.custom && nutritionEntered && !cupType) {
      return wx.showToast({ title: '先选择杯型，系统才能按全局容量折算营养', icon: 'none' });
    }
    let numericSizeMl = Number(sizeMl) || 0;
    let nutritionInputPer100Ml = existing && existing.nutritionInputPer100Ml;
    let nutritionSnapshot = existing && existing.nutritionSnapshot;
    let drink = this.data.selectedDrink;
    if (this.data.custom) {
      const normalize = (value) => String(value || '').trim().toLowerCase();
      const previousCustom = this.catalog.drinks.find((item) => normalize(item.brandName) === normalize(brandName)
        && normalize(item.name) === normalize(drinkName));
      drink = previousCustom || Domain.createCustomDrink({ brandName, drinkName, sizeMl }, userId);
      if (this.data.creatingForBrand && this.data.selectedBrand) {
        drink.brandId = this.data.selectedBrand.id;
        drink.category = drink.category || this.data.selectedBrand.category || '';
      }
      drink.brandName = brandName;
      drink.name = drinkName;
      numericSizeMl = numericSizeMl || Domain.resolveCupSizeMl({ cupType }, this.globalCupSizes) || 0;
      if (nutritionEntered) {
        const updatedAt = new Date().toISOString();
        const enteredValues = {
          energyKcal: nutritionValues.energyKcal.value,
          sugarG: nutritionValues.sugarG.value,
          caffeineMg: nutritionValues.caffeineMg.value
        };
        nutritionInputPer100Ml = { amount: 100, unit: 'ml', ...enteredValues, sourceType: 'estimated', source: '用户按每100ml填写', updatedAt };
        const existingNutrition = drink.nutritionPerUnit || {};
        const hasOfficialBaselineValue = ['energyKcal', 'sugarG', 'caffeineMg'].some((key) =>
          existingNutrition[key] !== null && existingNutrition[key] !== undefined && existingNutrition[key] !== '');
        const preserveOfficialBaseline = existingNutrition.sourceType === 'official' && hasOfficialBaselineValue;
        if (!preserveOfficialBaseline) {
          const existingPer100Ml = existingNutrition.unit === 'ml' ? existingNutrition : {};
          const mergedValues = {};
          Object.keys(enteredValues).forEach((key) => {
            mergedValues[key] = enteredValues[key] === null
              ? (existingPer100Ml[key] === undefined ? null : existingPer100Ml[key])
              : enteredValues[key];
          });
          drink.nutritionPerUnit = {
            ...existingPer100Ml, amount: 100, unit: 'ml', ...mergedValues,
            sourceType: 'estimated', source: '用户按每100ml填写', updatedAt
          };
          if (numericSizeMl > 0) {
            const previousNutritionVariants = Array.isArray(drink.nutritionVariants) ? drink.nutritionVariants : [];
            const sameServing = (item) => {
              const itemServing = Domain.resolveTemperatureIce(item);
              const sameCup = !item.cupType || !cupType || item.cupType === cupType;
              return sameCup && Number(item.sizeMl) === numericSizeMl
                && (item.sweetness || '') === (this.data.sweetness || '')
                && itemServing.temperature === serving.temperature && itemServing.ice === serving.ice
                && (item.toppings || []).slice().sort().join('|') === toppings.slice().sort().join('|');
            };
            const editableEstimateSources = ['用户估算', '用户按每100ml填写'];
            drink.nutritionVariants = previousNutritionVariants.filter((item) => !(sameServing(item)
              && item.sourceType !== 'official' && editableEstimateSources.includes(item.source)));
            drink.nutritionVariants.push({
              sizeMl: numericSizeMl, cupType, sweetness: this.data.sweetness, servingOption: this.data.servingOption,
              temperature: serving.temperature, ice: serving.ice, toppings, sourceType: 'estimated', source: '用户按每100ml填写', updatedAt,
              energyKcal: mergedValues.energyKcal === null ? null : mergedValues.energyKcal * numericSizeMl / 100,
              sugarG: mergedValues.sugarG === null ? null : mergedValues.sugarG * numericSizeMl / 100,
              caffeineMg: mergedValues.caffeineMg === null ? null : mergedValues.caffeineMg * numericSizeMl / 100
            });
          }
        }
        if (numericSizeMl > 0) {
          const recordForNutrition = {
            sizeMl: numericSizeMl, cupType, sweetness: this.data.sweetness, servingOption: this.data.servingOption,
            temperature: serving.temperature, ice: serving.ice, toppings
          };
          const currentNutrition = Domain.nutritionForRecord(recordForNutrition, drink, this.globalCupSizes);
          const snapshotValue = (key) => enteredValues[key] === null
            ? currentNutrition[key]
            : enteredValues[key] * numericSizeMl / 100;
          nutritionSnapshot = {
            complete: true,
            energyKcal: snapshotValue('energyKcal'),
            sugarG: snapshotValue('sugarG'),
            caffeineMg: snapshotValue('caffeineMg'),
            sourceType: 'estimated',
            source: '用户按每100ml填写',
            updatedAt: updatedAt
          };
        } else {
          nutritionSnapshot = null;
        }
      }
      const saved = Store.saveUserDrink(drink);
      this.catalog = saved.catalog;
      drink = saved.drink;
    }
    const location = this.data.location || (this.locationEdited ? '' : (existing && existing.location)) || '';
    const locationAddress = this.data.locationAddress || (this.locationEdited ? '' : (existing && existing.locationAddress)) || '';
    const locationLatitude = this.data.locationLatitude !== '' ? this.data.locationLatitude : (this.locationEdited ? null : existing && existing.locationLatitude);
    const locationLongitude = this.data.locationLongitude !== '' ? this.data.locationLongitude : (this.locationEdited ? null : existing && existing.locationLongitude);
    const payload = Domain.createRecord({ ...(existing || {}), id: this.data.recordId || undefined, brandId: (this.data.selectedBrand && this.data.selectedBrand.id) || drink.brandId || '',
      brandName, drinkId: drink.id, drinkName, consumedAt, sizeMl, cupType, sweetness: this.data.sweetness,
      nutritionInputPer100Ml, nutritionSnapshot,
      servingOption: this.data.servingOption, temperature: serving.temperature, ice: serving.ice, toppings,
      photo: this.data.photo, photoThumbnail: this.data.photoThumbnail || this.data.photo,
      location, locationAddress, locationLatitude, locationLongitude,
      userName: getApp().globalData.userName || '我', notes: this.data.notes }, userId);
    if (this.data.editing) Store.saveRecords(Domain.updateRecord(records, this.data.recordId, userId, payload));
    else Store.saveRecords([payload, ...records]);
    const toastTitle = nutritionEntered && this.data.custom && numericSizeMl <= 0
      ? '营养基准已保存，杯型容量待配置'
      : this.data.editing ? '已保存修改' : '记录完成';
    wx.showToast({ title: toastTitle, icon: 'success' });
    setTimeout(() => wx.navigateBack(), 450);
  },
  deleteRecord() {
    wx.showModal({ title: '删除这条记录？', content: '删除后无法恢复。', confirmColor: '#a14a3b', success: (result) => {
      if (!result.confirm) return;
      const records = Domain.deleteRecord(Store.getRecords(), this.data.recordId, getApp().globalData.userId);
      Store.saveRecords(records);
      wx.navigateBack();
    } });
  }
});
