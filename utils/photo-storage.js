const DIAGNOSTICS_KEY = 'drink-log:photo-diagnostics';
const RECORDS_KEY = 'drink-log:records';
let memoryDiagnostics = null;
let persistenceError = '';

function errorDetails(error) {
  const value = error || {};
  const message = typeof error === 'string' ? error : String(value.errMsg || value.message || '未返回错误说明');
  const codes = ['errCode', 'errno', 'code'].filter((key) => value[key] !== undefined && value[key] !== null)
    .map((key) => `${key}: ${value[key]}`).join(' · ');
  return { message, codes };
}

function getDiagnostics() {
  if (memoryDiagnostics) return { ...memoryDiagnostics, persistenceError };
  try {
    const stored = wx.getStorageSync(DIAGNOSTICS_KEY);
    return stored && typeof stored === 'object' ? stored : {};
  } catch (error) {
    return { persistenceError: errorDetails(error).message };
  }
}

function updateDiagnostics(changes) {
  const { persistenceError: previousError, ...previous } = getDiagnostics();
  memoryDiagnostics = { ...previous, ...changes };
  try {
    wx.setStorageSync(DIAGNOSTICS_KEY, memoryDiagnostics);
    persistenceError = '';
  } catch (error) {
    // A full cache must not prevent the photo result or the diagnostic page from being shown.
    persistenceError = errorDetails(error).message;
  }
}

function formatBytes(bytes) {
  if (typeof bytes !== 'number' || !Number.isFinite(bytes) || bytes < 0) return '未能读取';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function inspectSelection(file, source) {
  const selection = { source, selectedAt: new Date().toISOString(), sizeBytes: null };
  if (typeof file.size === 'number' && Number.isFinite(file.size) && file.size >= 0) {
    return Promise.resolve({ ...selection, sizeBytes: file.size });
  }
  return new Promise((resolve) => {
    try {
      const fs = wx.getFileSystemManager();
      fs.getFileInfo({ filePath: file.tempFilePath,
        success: (result) => resolve({ ...selection, sizeBytes: typeof result.size === 'number' ? result.size : null }),
        fail: () => resolve(selection) });
    } catch (error) {
      resolve(selection);
    }
  });
}

function rememberSelection(selection) { updateDiagnostics({ selection }); }

function saveLocalFile(tempFilePath) {
  return new Promise((resolve, reject) => {
    try {
      const fs = wx.getFileSystemManager();
      if (!fs || !fs.saveFile) return reject(new Error('当前环境不支持本地文件保存'));
      fs.saveFile({ tempFilePath,
        success: (result) => result.savedFilePath ? resolve(result.savedFilePath) : reject(new Error('微信未返回保存后的文件路径')),
        fail: reject });
    } catch (error) { reject(error); }
  });
}

function failureReason(message) {
  if (/no space|ENOSPC|quota|exceed.*(?:size|limit)|maximum.*(?:size|limit)|storage.*(?:full|limit)|空间.*(?:不足|已满)|容量.*(?:上限|不足)/i.test(message)) return '本地文件空间不足或达到容量限制';
  if (/no such file|not found|ENOENT|文件.*不存在/i.test(message)) return '照片临时文件不存在或已失效';
  if (/permission|denied|EACCES|权限/i.test(message)) return '文件访问权限不足';
  return '照片处理未完成，具体原因见下方原始错误';
}

function openStorage() { wx.navigateTo({ url: '/pages/storage/storage' }); }

function reportFailure(error, details) {
  const raw = errorDetails(error);
  const failure = { ...details, ...raw, occurredAt: new Date().toISOString(), reason: failureReason(raw.message) };
  updateDiagnostics({ failure });
  console.warn('[photo-storage]', failure);
  const partial = details.originalSaved;
  const content = [partial ? '原图已保存，列表将使用原图显示。' : failure.reason,
    `环节：${details.stage}`, `原始错误：${raw.message}`, raw.codes,
    details.selection ? `所选图片：${formatBytes(details.selection.sizeBytes)}` : ''].filter(Boolean).join('\n');
  wx.showModal({ title: partial ? '缩略图保存失败' : '照片处理失败', content,
    confirmText: '查看存储', cancelText: '关闭',
    success: (result) => { if (result.confirm) openStorage(); } });
  return failure;
}

function readSavedFiles() {
  return new Promise((resolve) => {
    const fail = (error) => resolve({ available: false, error: errorDetails(error).message });
    try {
      const fs = wx.getFileSystemManager();
      fs.getSavedFileList({ success: (result) => {
        const files = result.fileList;
        if (!Array.isArray(files) || files.some((file) => typeof file.size !== 'number' || !Number.isFinite(file.size) || file.size < 0)) {
          return fail(new Error('微信未返回完整的文件大小信息'));
        }
        resolve({ available: true, count: files.length, sizeBytes: files.reduce((sum, file) => sum + file.size, 0) });
      }, fail });
    } catch (error) { fail(error); }
  });
}

function readCacheUsage() {
  return new Promise((resolve) => {
    const fail = (error) => resolve({ available: false, error: errorDetails(error).message });
    try {
      wx.getStorageInfo({ success: (result) => {
        if (![result.currentSize, result.limitSize].every((value) => typeof value === 'number' && Number.isFinite(value) && value >= 0)) {
          return fail(new Error('微信未返回完整的缓存容量信息'));
        }
        resolve({ available: true, sizeBytes: result.currentSize * 1024, limitBytes: result.limitSize * 1024 });
      }, fail });
    } catch (error) { fail(error); }
  });
}

function utf8Size(text) {
  let size = 0;
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i);
    if (code < 0x80) size += 1;
    else if (code < 0x800) size += 2;
    else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
      && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) { size += 4; i += 1; }
    else size += 3;
  }
  return size;
}

function readRecordUsage() {
  try {
    const stored = wx.getStorageSync(RECORDS_KEY);
    const records = stored === '' || stored === null || stored === undefined ? [] : stored;
    if (!Array.isArray(records)) throw new Error('记录缓存格式异常');
    return { available: true, count: records.length, estimatedBytes: utf8Size(JSON.stringify(records)) };
  } catch (error) { return { available: false, error: errorDetails(error).message }; }
}

async function inspectStorage() {
  const [files, cache] = await Promise.all([readSavedFiles(), readCacheUsage()]);
  return { files, cache, records: readRecordUsage(), diagnostics: getDiagnostics() };
}

module.exports = { inspectSelection, rememberSelection, saveLocalFile, reportFailure, openStorage,
  inspectStorage, getDiagnostics, formatBytes };
