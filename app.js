App({
  globalData: { userId: '' },
  onLaunch() {
    let userId = wx.getStorageSync('drink-log:user-id');
    if (!userId) {
      userId = `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      wx.setStorageSync('drink-log:user-id', userId);
    }
    this.globalData.userId = userId;
  }
});
