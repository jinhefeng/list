const PhotoStorage = require('../../utils/photo-storage');

function timeLabel(value) {
  if (!value) return '';
  const d = new Date(value);
  if (!Number.isFinite(d.getTime())) return value;
  const pad = (number) => String(number).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

Page({
  data: { loading: true, files: {}, cache: {}, records: {}, selection: null, failure: null, persistenceError: '', updatedAt: '' },
  onShow() { return this.refresh(); },
  async refresh() {
    const token = {};
    this.refreshToken = token;
    this.setData({ loading: true });
    const report = await PhotoStorage.inspectStorage();
    if (this.refreshToken !== token) return;
    const { files, cache, records, diagnostics } = report;
    const selection = diagnostics.selection;
    const failure = diagnostics.failure;
    this.setData({ loading: false,
      files: { ...files, sizeLabel: PhotoStorage.formatBytes(files.sizeBytes) },
      cache: { ...cache, sizeLabel: PhotoStorage.formatBytes(cache.sizeBytes), limitLabel: PhotoStorage.formatBytes(cache.limitBytes) },
      records: { ...records, sizeLabel: PhotoStorage.formatBytes(records.estimatedBytes) },
      selection: selection ? { ...selection, sizeLabel: PhotoStorage.formatBytes(selection.sizeBytes), timeLabel: timeLabel(selection.selectedAt) } : null,
      failure: failure ? { ...failure, timeLabel: timeLabel(failure.occurredAt),
        sizeLabel: failure.selection ? PhotoStorage.formatBytes(failure.selection.sizeBytes) : '未能读取' } : null,
      persistenceError: diagnostics.persistenceError || '', updatedAt: timeLabel(new Date().toISOString()) });
  },
  onUnload() { this.refreshToken = null; },
  copyReport() {
    if (this.data.loading) return;
    const { files, cache, records, selection, failure, persistenceError, updatedAt } = this.data;
    const lines = ['本地存储诊断', `读取时间：${updatedAt}`,
      files.available ? `已保存图片文件：${files.count} 个，${files.sizeLabel}（含缩略图）` : `照片文件统计失败：${files.error}`,
      cache.available ? `记录与设置缓存：${cache.sizeLabel} / ${cache.limitLabel}` : `缓存统计失败：${cache.error}`,
      records.available ? `记录：${records.count} 条，内容估算 ${records.sizeLabel}` : `记录统计失败：${records.error}`];
    if (selection) lines.push(`最近所选图片：${selection.source}，${selection.sizeLabel}，${selection.timeLabel}`);
    if (failure) lines.push(`最近失败：${failure.timeLabel}，${failure.stage}`,
      `原因：${failure.reason}`, `原始错误：${failure.message}`, failure.codes,
      `失败时所选图片：${failure.sizeLabel}`, failure.originalSaved ? '原图已保存，缩略图失败' : '');
    if (persistenceError) lines.push(`诊断信息仅在本次运行中保留：${persistenceError}`);
    wx.setClipboardData({ data: lines.filter(Boolean).join('\n'),
      fail: () => wx.showToast({ title: '复制失败，请重试', icon: 'none' }) });
  }
});
