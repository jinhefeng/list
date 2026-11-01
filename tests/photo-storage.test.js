const test = require('node:test');
const assert = require('node:assert/strict');

let storage;
let fs;
let modals;
let writes;
let photos;

test.beforeEach((t) => {
  storage = new Map([['drink-log:records', [{ id: 'old', notes: '茶☕😀', photo: 'wxfile://old.jpg' }]]]);
  modals = [];
  writes = [];
  fs = {
    saveFile(options) { options.success({ savedFilePath: 'wxfile://new.jpg' }); },
    getSavedFileList(options) { options.success({ fileList: [{ size: 2048 }, { size: 1024 }] }); },
    getFileInfo(options) { options.success({ size: 4096 }); },
    readFile(options) { options.fail({ errMsg: 'not a JPEG' }); }
  };
  global.wx = {
    getStorageSync(key) { return storage.has(key) ? storage.get(key) : ''; },
    setStorageSync(key, value) { writes.push(key); storage.set(key, value); },
    getStorageInfo(options) { options.success({ currentSize: 512, limitSize: 10240 }); },
    getFileSystemManager() { return fs; },
    chooseMedia(options) { options.success({ tempFiles: [{ tempFilePath: '/tmp/new.jpg', size: 8192 }] }); },
    showModal(options) { modals.push(options); },
    showToast() {},
    navigateTo() {}
  };
  t.mock.method(console, 'warn', () => {});
  delete require.cache[require.resolve('../utils/photo-storage')];
  photos = require('../utils/photo-storage');
});

function loadPage(path) {
  let definition;
  global.Page = (page) => { definition = page; };
  delete require.cache[require.resolve(path)];
  require(path);
  return { ...definition, data: JSON.parse(JSON.stringify(definition.data)),
    setData(changes) { Object.assign(this.data, changes); } };
}

function enableThumbnail() {
  const canvas = { getContext() { return { clearRect() {}, drawImage() {} }; },
    createImage() {
      return { width: 800, height: 600, set src(value) { this.onload(); } };
    } };
  wx.createSelectorQuery = () => ({ in() { return this; }, select() { return this; }, fields() { return this; },
    exec(callback) { callback([{ node: canvas }]); } });
  wx.canvasToTempFilePath = (options) => options.success({ tempFilePath: '/tmp/thumbnail.jpg' });
}

test('file totals and cache totals stay separate; record bytes include Chinese and emoji', async () => {
  const before = structuredClone(storage.get('drink-log:records'));
  const report = await photos.inspectStorage();
  assert.deepEqual(report.files, { available: true, count: 2, sizeBytes: 3072 });
  assert.equal(report.cache.sizeBytes, 512 * 1024);
  assert.equal(report.cache.limitBytes, 10240 * 1024);
  assert.equal(report.records.count, 1);
  assert.equal(report.records.estimatedBytes, Buffer.byteLength(JSON.stringify(before), 'utf8'));
  assert.deepEqual(storage.get('drink-log:records'), before);
  assert.deepEqual(writes, []);
});

test('failed statistics remain unavailable instead of becoming zero', async () => {
  fs.getSavedFileList = (options) => options.fail({ errMsg: 'getSavedFileList:fail permission denied' });
  wx.getStorageInfo = (options) => options.fail({ errMsg: 'getStorageInfo:fail unavailable' });
  const report = await photos.inspectStorage();
  assert.equal(report.files.available, false);
  assert.equal(report.files.sizeBytes, undefined);
  assert.match(report.files.error, /permission denied/);
  assert.equal(report.cache.available, false);
  assert.equal(report.cache.sizeBytes, undefined);
  assert.equal(report.records.available, true);
});

test('empty file list is a measured zero; missing file sizes are unavailable', async () => {
  fs.getSavedFileList = (options) => options.success({ fileList: [] });
  assert.deepEqual((await photos.inspectStorage()).files, { available: true, count: 0, sizeBytes: 0 });
  fs.getSavedFileList = (options) => options.success({ fileList: [{}] });
  assert.equal((await photos.inspectStorage()).files.available, false);
});

test('selection size falls back to file info, and a size read failure does not block selection', async () => {
  const file = { tempFilePath: '/tmp/new.jpg' };
  assert.equal((await photos.inspectSelection(file, '菜品照片')).sizeBytes, 4096);
  fs.getFileInfo = (options) => options.fail({ errMsg: 'getFileInfo:fail' });
  assert.equal((await photos.inspectSelection(file, '菜品照片')).sizeBytes, null);
});

test('cache exhaustion still exposes the original error during the current run', () => {
  const before = structuredClone(storage.get('drink-log:records'));
  wx.setStorageSync = () => { throw new Error('setStorage:fail quota exceeded'); };
  photos.reportFailure({ errMsg: 'saveFile:fail no space left on device', errCode: 130020, errno: 28 },
    { stage: '保存原图', selection: { source: '饮品照片', sizeBytes: 8192 } });
  const diagnostics = photos.getDiagnostics();
  assert.match(diagnostics.failure.message, /no space left/);
  assert.match(diagnostics.failure.codes, /errCode: 130020.*errno: 28/);
  assert.match(diagnostics.persistenceError, /quota exceeded/);
  assert.match(modals[0].content, /saveFile:fail no space left/);
  assert.deepEqual(storage.get('drink-log:records'), before);
});

test('last failure survives a fresh module load with its own selected image size', () => {
  photos.reportFailure({ errMsg: 'saveFile:fail file not found', code: 'ENOENT' },
    { stage: '保存原图', selection: { source: '饮品照片', sizeBytes: 8192 } });
  photos.rememberSelection({ source: '菜品照片', sizeBytes: 4096 });
  delete require.cache[require.resolve('../utils/photo-storage')];
  const restored = require('../utils/photo-storage').getDiagnostics();
  assert.equal(restored.failure.selection.sizeBytes, 8192);
  assert.equal(restored.selection.sizeBytes, 4096);
  assert.match(restored.failure.codes, /ENOENT/);
});

for (const kind of ['drink', 'meal']) {
  function form() {
    const page = loadPage(kind === 'drink' ? '../pages/record/record' : '../pages/meal/meal');
    if (kind === 'drink') page.setData({ photo: 'wxfile://old.jpg', photoThumbnail: 'wxfile://old-thumb.jpg' });
    else page.setData({ dishes: [{ id: 'dish-1', name: '饭', photo: 'wxfile://old.jpg', photoThumbnail: 'wxfile://old-thumb.jpg' }] });
    return page;
  }
  function choose(page) {
    if (kind === 'drink') { page.choosePhoto(); return page.photoWork; }
    page.chooseDishPhoto({ currentTarget: { dataset: { id: 'dish-1' } } });
    return page.photoWorks && page.photoWorks[page.photoWorks.length - 1];
  }
  function image(page) { return kind === 'drink' ? page.data : page.data.dishes[0]; }

  test(`${kind}: full local storage preserves the existing photo and exposes exact save failure`, async () => {
    const page = form();
    fs.saveFile = (options) => options.fail({ errMsg: 'saveFile:fail the maximum size of the file storage limit is exceeded', errCode: 100 });
    await choose(page);
    assert.equal(image(page).photo, 'wxfile://old.jpg');
    assert.equal(image(page).photoThumbnail, 'wxfile://old-thumb.jpg');
    assert.equal(image(page).photoPending, false);
    assert.equal(photos.getDiagnostics().failure.stage, '保存原图');
    assert.match(modals[0].content, /storage limit is exceeded/);
    assert.match(modals[0].content, /8.0 KB/);
    assert.equal(storage.get('drink-log:records')[0].photo, 'wxfile://old.jpg');
    assert.ok(writes.every((key) => key === 'drink-log:photo-diagnostics'));
  });

  test(`${kind}: thumbnail save failure keeps the successfully saved original`, async () => {
    enableThumbnail();
    fs.saveFile = (options) => options.tempFilePath.includes('thumbnail')
      ? options.fail({ errMsg: 'saveFile:fail ENOSPC' }) : options.success({ savedFilePath: 'wxfile://new.jpg' });
    const page = form();
    await choose(page);
    assert.equal(image(page).photo, 'wxfile://new.jpg');
    assert.equal(image(page).photoThumbnail, 'wxfile://new.jpg');
    assert.equal(image(page).photoPending, false);
    assert.equal(photos.getDiagnostics().failure.stage, '保存缩略图');
    assert.equal(photos.getDiagnostics().failure.originalSaved, true);
    assert.match(modals[0].content, /原图已保存/);
  });

  test(`${kind}: successful selection saves distinct original and thumbnail files`, async () => {
    enableThumbnail();
    fs.saveFile = (options) => options.success({ savedFilePath: options.tempFilePath.includes('thumbnail') ? 'wxfile://new-thumb.jpg' : 'wxfile://new.jpg' });
    const page = form();
    await choose(page);
    assert.equal(image(page).photo, 'wxfile://new.jpg');
    assert.equal(image(page).photoThumbnail, 'wxfile://new-thumb.jpg');
    assert.equal(photos.getDiagnostics().selection.sizeBytes, 8192);
    assert.equal(modals.length, 0);
  });

  test(`${kind}: an outdated selection failure cannot replace the latest photo or show an error`, async () => {
    let rejectOld;
    fs.saveFile = (options) => { rejectOld = options.fail; };
    const page = form();
    const old = choose(page);
    await new Promise((resolve) => setImmediate(resolve));
    fs.saveFile = (options) => options.success({ savedFilePath: 'wxfile://new.jpg' });
    await choose(page);
    rejectOld({ errMsg: 'saveFile:fail outdated' });
    await old;
    assert.equal(image(page).photo, 'wxfile://new.jpg');
    assert.equal(modals.length, 0);
    assert.equal(photos.getDiagnostics().failure, undefined);
  });

  test(`${kind}: cancelling the picker is silent; picker permission errors are retained`, () => {
    const page = form();
    wx.chooseMedia = (options) => options.fail({ errMsg: 'chooseMedia:fail cancel' });
    choose(page);
    assert.equal(modals.length, 0);
    wx.chooseMedia = (options) => options.fail({ errMsg: 'chooseMedia:fail permission denied', errno: 103 });
    choose(page);
    assert.equal(modals.length, 1);
    assert.match(photos.getDiagnostics().failure.message, /permission denied/);
    assert.equal(image(page).photo, 'wxfile://old.jpg');
  });
}

test('diagnostic page refresh and copy include errors and sizes without copying record contents', async () => {
  photos.rememberSelection({ source: '饮品照片', sizeBytes: 8192 });
  photos.reportFailure({ errMsg: 'saveFile:fail permission denied', errno: 103 }, { stage: '保存原图', selection: { sizeBytes: 8192 } });
  const page = loadPage('../pages/storage/storage');
  await page.onShow();
  let copied;
  wx.setClipboardData = ({ data }) => { copied = data; };
  page.copyReport();
  assert.equal(page.data.files.count, 2);
  assert.equal(page.data.selection.sizeLabel, '8.0 KB');
  assert.match(copied, /saveFile:fail permission denied/);
  assert.match(copied, /errno: 103/);
  assert.doesNotMatch(copied, /茶|wxfile:\/\/old/);
});
