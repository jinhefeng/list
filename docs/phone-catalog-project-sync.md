# 手机品牌资料回灌项目

手机端维护的品牌和饮品保存在 App 本机目录覆盖中。更新后的 App 可从「更多 → 饮品目录 → 项目资料同步」导出一个 JSON 资料包，内容包含本机新增或修改的品牌、饮品、来源链接和 Logo 图片；不会包含饮食记录、记录照片或 API 设置。

## 从 iPhone 导入项目

1. 在 iPhone 上更新并打开“吃吃喝喝”，进入「更多 → 饮品目录」。升级会沿用现有的本机目录数据。
2. 点「导出手机维护的品牌资料」，再点「发送资料包到项目电脑」，通过 AirDrop 或“存储到文件”把 JSON 发到 Mac。
3. 在项目目录中先预览导入结果：

   ```sh
   npm run catalog:import-phone -- "/path/to/吃吃喝喝-品牌资料.json"
   ```

4. 确认品牌和饮品数量后，执行导入：

   ```sh
   npm run catalog:import-phone -- "/path/to/吃吃喝喝-品牌资料.json" --apply
   ```

脚本先按稳定 ID 匹配，再按品牌名称和明确别名做唯一匹配；匹配到内置品牌时会换成内置 ID。若别名同时指向多个品牌，预览会列出候选，需先解决歧义再应用。相同品牌下名称去空格、忽略大小写后相同的饮品会合为一项：手机数据优先、软件包字段补空，并记录旧饮品 ID 以便历史记录继续解析。用户选择过的 Logo 优先；没有用户 Logo 时使用当前软件包 Logo。

应用时，脚本会把图片加入 `Assets.xcassets`，把合并后的手机覆盖保存到 `data/catalog-phone-overrides.json`，然后重新生成 iOS 内置目录 `ios/GanfanHandbook/Resources/catalog.json`。手机端已删除的条目不会自动从项目目录删除。iOS 运行时也会迁移已安装或从旧备份恢复的本机目录，规则与回灌一致，重复启动不会重复添加品牌或菜单。

导入后可检查：

```sh
git diff -- data/catalog-phone-overrides.json ios/GanfanHandbook/Resources/catalog.json ios/GanfanHandbook/Assets.xcassets
```

## 网页菜单和 Logo 检索

新增品牌向导使用 App 内的百度或 Bing 网页搜索，不调用 AI API 或搜索 API。选择一个网页后，App 尝试读取页面的结构化商品名称、菜单列表、分享图和页面图片；结果先放进可编辑草稿。保存的菜单候选保留来源并标为“待核验”。网站若不提供可读结构，仍可在草稿中逐行粘贴或编辑饮品名称。Logo 下载到本机并经裁切确认后离线保存。
