const Store = require('./utils/store');

App({
  globalData: { userId: '', userName: '我' },
  onLaunch() {
    let userId = wx.getStorageSync('drink-log:user-id');
    if (!userId) {
      userId = `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      wx.setStorageSync('drink-log:user-id', userId);
    }
    const userName = wx.getStorageSync('drink-log:user-name') || '我';
    if (!wx.getStorageSync('drink-log:user-name')) wx.setStorageSync('drink-log:user-name', userName);
    this.globalData.userId = userId;
    this.globalData.userName = userName;
    Store.syncCatalog();
  }
});
