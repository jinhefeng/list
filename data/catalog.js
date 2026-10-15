const updatedAt = '2026-10-15';
const checkedAt = '2026-10-15';
// Increment this when the bundled brand or drink list changes. The store uses
// it to refresh cached catalogs on existing installations without clearing records.
const version = '2026-10-15.1';

// Public menus help broaden name search, but do not prove availability at a
// particular Taobao Flash Sale store. Keep every imported reference pending.
const catalogSources = [
  {
    id: 'brand-mixue', name: '蜜雪冰城', aliases: ['蜜雪', 'MXBC'], category: '茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/mi-xue-bing-cheng/menu/available?page=1',
    products: ['冰鲜柠檬水', '珍珠奶茶', '棒打鲜橙', '蜜桃四季春', '柠檬红茶', '满杯百香果', '抹茶摇摇奶昔', '满杯玉米', '芝士奶盖玉米', '蜜瓜摇摇冰', '雪王雪顶龙井', '黑糖全冰美式', '黑糖珍珠鲜牛乳', '好柿多多', '好柿椰椰', '牛油果酸奶', '牛油果甘露', '草莓奶麻薯', '芒果奶麻薯', '黄桃果霸']
  },
  {
    id: 'brand-heytea', name: '喜茶', aliases: ['HEYTEA', '喜茶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/xi-cha/menu/available?page=1',
    products: ['多肉葡萄', '芝芝莓莓', '烤黑糖波波牛乳', '酷黑莓桑', '满杯红柚', '芒芒甘露', '青柠生乳希腊酸奶手炒冰', '芋泥波波牛乳2018', '芋泥波波牛乳茶2018', '热芋泥波波牛乳2018', '热芋泥波波牛乳茶2018', '爆芋泥生椰手炒冰', '雪毫茉王芭乐', '喜柿多多喜拉朵', '超多肉椰椰芒芒']
  },
  {
    id: 'brand-nayuki', name: '奈雪的茶', aliases: ['奈雪', 'NAIXUE'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/nai-xue-de-cha/menu/available?page=2',
    products: ['霸气橙子', '茉莉初雪', '宝藏茶', '超醒手打柠檬冰砖美式', '超C大橘美式', 'Gelato芭乐冰奶', '冰砖美式', '黄皮蜜桃冰砖美式', 'Gelato乌龙冰茶', '鸭屎香纯茶', 'Gelato香水椰', '霸气杨梅', '初雪芝士蜜桃冰奶', '初雪葡萄冰奶', '霸气小红杏酸奶冰', '霸气一桶美式', '霸气芝士葡萄', '霸气芝士芒果', '霸气青柑柠檬茶']
  },
  {
    id: 'brand-starbucks', name: '星巴克', aliases: ['STARBUCKS', '星巴克咖啡'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/xing-ba-ke/menu/available',
    products: ['美式咖啡', '拿铁', '焦糖玛奇朵', '摩卡星冰乐®', '冷萃冰咖啡', '摩卡', '星巴克馥芮白®', '抹茶星冰乐®', '高蛋白馥芮白® PRO', '法式香草风味高蛋白拿铁PRO', '臻选拿铁（水洗埃塞俄比亚耶加雪菲雪冽图）', '臻选美式（水洗埃塞俄比亚耶加雪菲雪冽图）', '臻选馥芮白（水洗埃塞俄比亚耶加雪菲雪冽图）', '奶皮子风味咸奶茶', '抹茶山系茶拿铁', '抹茶山系星冰乐', '经典伯爵冰茶']
  },
  {
    id: 'brand-chagee', name: '霸王茶姬', aliases: ['CHAGEE', '茶姬'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/ba-wang-cha-ji/menu/available',
    products: ['伯牙绝弦', '花田乌龙', '桂馥兰香', '寻香山茶', '青青糯山', '白雾红尘', '轻因·桂馥兰香', '轻因·折桂令', '凤栖梧', '黄皮油柑单丛', '荔荔栀椰']
  },
  {
    id: 'brand-luckin', name: '瑞幸咖啡', aliases: ['瑞幸', 'Luckin', 'Luckin Coffee'], category: '咖啡',
    sourceType: 'official_brand', sourceName: '瑞幸咖啡官网产品页',
    sourceUrl: 'https://www.lkcoffee.com/products',
    products: ['生椰拿铁', '茉莉花香拿铁', '拿铁', '冰吸生椰拿铁', '小黄油拿铁', '生椰三重奏拿铁', '轻椰茉莉拿铁', '丝绒拿铁', '钱塘龙井拿铁', '海盐焦糖拿铁', '绿沙沙拿铁', '桂花米酿拿铁']
  },
  {
    id: 'brand-guming', name: '古茗', aliases: ['古茗奶茶', 'Guming'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/gu-ming/menu/available?page=1',
    products: ['芝士乌龙', '珍珠奶茶', '大叔奶茶', '茉莉奶绿', '杨枝甘露轻盈版', '金桂酒酿拿铁', '云雾栀子', '大柚糯米酸奶', '大柚冰奶', 'HPP·奇兰乌龙', 'HPP·茉莉银针', '三重抹茶慕斯', '红颜石榴汁', '满杯红玉石榴', '红玉石榴葡萄', '苹果油柑美式', '苹果杨桃油柑', '苹果大红袍', '盐奶油美式', '超大杯冰美式', '泰橘美式', '马上有米拿铁', '甜心芭乐葡']
  },
  {
    id: 'brand-chabaidao', name: '茶百道', aliases: ['茶百道奶茶', 'ChaPanda'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/cha-bai-dao/new-products',
    products: ['豆乳玉麒麟', '茉莉奶绿', '杨枝甘露', '超厚芋泥金牡丹', '苹果派云顶美式', '岭南龙眼珍珠', '芭乐青提酸奶杯', '奶绿旋风', '香草金牡丹鲜奶茶', '岭南龙眼啵啵', '金喜凤梨', '香草金牡丹牛乳', '焦糖饼干奶茶', '生椰西瓜', '葡萄冰浆', '牛油果酸奶', '牛油果羽衣甘蓝', '鲜果橙C美式', '鲜果橙C拿铁', '荔枝冰奶', '杨梅酸奶昔']
  },
  {
    id: 'brand-manner', name: 'Manner咖啡', aliases: ['Manner', 'MANNER COFFEE'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/manner-coffee/menu/available',
    products: ['拿铁咖啡', '澳式白咖啡', '美式咖啡', '燕麦拿铁', '埃塞果丁丁可如蜜水洗拿铁', '埃塞果丁丁可如蜜水洗美式', '埃塞果丁丁可如蜜水洗Dirty', 'SOE美式', 'SOE拿铁', '玫瑰米酿拿铁', '黄油SOE拿铁']
  },
  {
    id: 'brand-cotti', name: '库迪咖啡', aliases: ['COTTI', 'Cotti Coffee'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/ku-di-ka-fei/menu/available?page=2',
    products: ['活荔芝云库可冰', '超燃椰青美式', '超燃椰青茉莉冰茶', '小黄油拿铁', '小黄油美式', '小黄油茉香抹茶', '鲜气杨梅燕麦奶昔', '鲜气杨梅库可冰', '鲜气杨梅冰茶', '茉莉花香拿铁', '清爽芭乐提', '胶原莓果美式', '百香橙橙美式', '杨枝甘露拿铁', '黑糖波波牛乳茶', '抹茶拿铁', '晴天茉莉绿茶', '蜂蜜白柚冰柠茶', '柠萃茉莉冰茶']
  },
  {
    id: 'brand-nowwa', name: '挪瓦咖啡', aliases: ['NOWWA', '挪瓦'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/nuo-wa-ka-fei/menu/available',
    products: ['半熟芝士拿铁', '生椰拿铁', '苹果C果茶', '苹果C美式', '芭乐柠檬水', '葡萄冰柠水', '鸭屎香柚C果茶', '柚C无醇果啤', '柚C燃减轻咖', '橙C燃减轻咖', '超大杯葡萄柠檬水', '超大杯冰爽柠檬水', '冰椰风味茉莉花茶', '超大杯茉莉冰椰茶', '橙C冰柠水']
  },
  {
    id: 'brand-yidiandian', name: '一点点', aliases: ['1点点', '一点点奶茶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/yi-dian-dian/menu/available',
    products: [
      '养乐多绿', '阿华田', '冰淇淋红茶', '四季奶青', '波霸奶茶', '只此山楂绿',
      { name: '观音柠檬奶茶', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-09-01）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/173/' },
      { name: '可可玫瑰', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-08-14）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/172/' },
      'A2牛乳奇韵观音', '奇韵观音玛奇朵', '奇韵观音奶茶', '奇韵观音', '富桂观音奶茶',
      { name: '百香芒芒绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-07-21）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/168/' },
      '山楂绿', '茉香玫莓', '柠芭一下', '粉波霸桂花奶乌', '只此青柠', '乌龙奶茶',
      { name: '甘蔗马蹄青', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-09-24）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/176/' },
      '桂花奇韵观音',
      { name: '可可芭蕾', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-08-14）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/172/' },
      { name: '特浓抹茶奶茶玛奇朵', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-07-14）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/167/' },
      { name: '西瓜奶绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-06-30）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/166/' },
      { name: '芒番了', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-06-16）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/165/' },
      { name: '只此猕猴桃', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-06-10）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/161/' },
      { name: '不蕉绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-06-10）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/160/' },
      { name: '茶冻桃喜奶青', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-04-28）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/156/' },
      { name: '茶冻桃喜香柠绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-04-28）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/156/' },
      { name: '只此芒果青', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-04-14）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/155/' },
      { name: '只此草莓红', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-04-14）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/155/' },
      { name: '黑糖粉粿奶乌', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-04-01）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/154/' },
      { name: '甜橙奶绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-03-17）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/153/' },
      { name: '芭乐奶绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-03-03）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/150/' },
      { name: '芭乐绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-03-03）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/150/' },
      { name: '玫瑰重焙奶乌', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-02-10）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/149/' },
      { name: '山楂奶绿', sourceType: 'official_brand', sourceName: '1点点官网全国上新公告（2026-01-22）', sourceUrl: 'https://www.alittle-tea.com/latestnews-detail/148/' }
    ]
  },
  {
    id: 'brand-hushangayi', name: '沪上阿姨', aliases: ['沪上阿姨鲜果茶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/hu-shang-a-yi/menu/available',
    products: [
      '血糯米奶茶', '手作黑糖波波牛乳茶', '桃桃蜜柚', '杨枝甘露经典版', '去火羽衣纤体瓶',
      'QQ桃桃奶绿', '抹掉蕉绿', '不蕉不躁', '芝香巴拿拿拿铁', '千目抹茶莓莓',
      '超糯溏心木薯椰椰', '烤椰拿铁',
      { name: '糖烤板栗锡兰奶茶', sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单（沪上阿姨，第1页）', sourceUrl: 'https://www.nckfhsm.com/ja/brands/hu-shang-a-yi/menu/available' },
      { name: '糖烤板栗奇兰奶茶', sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单（沪上阿姨，第1页）', sourceUrl: 'https://www.nckfhsm.com/ja/brands/hu-shang-a-yi/menu/available' },
      { name: '琥珀锡兰红茶', sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单（沪上阿姨，第1页）', sourceUrl: 'https://www.nckfhsm.com/ja/brands/hu-shang-a-yi/menu/available' },
      { name: '热超嗲草莓大福', sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单（沪上阿姨，第1页）', sourceUrl: 'https://www.nckfhsm.com/ja/brands/hu-shang-a-yi/menu/available' }
    ]
  },
  {
    id: 'brand-coco', name: 'CoCo都可', aliases: ['CoCo', '都可'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/coco-dou-ke/menu/available',
    products: ['鲜百香双响炮', '珍珠奶茶', '奶茶三兄弟', '莓莓小姐姐', '莓莓冰奶', '葡萄冰奶', '轻轻柠檬冰奶', '蜜恋桃桃', '桃气泡泡', '四季珍珠奶青', '四季春茶', '手打柠檬四季春', '苹果大红袍', '苹果奶绿', '鲜柠檬茶']
  },
  {
    id: 'brand-yihetang', name: '益禾堂', aliases: ['益禾烤奶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/yi-he-tang/menu/available?page=1',
    products: ['杨枝甘露', '益禾烤奶', '珍珠奶茶', '超级黑桑葚冰奶', '气泡柠檬水', '黄金柚C冰茶', '葡萄冰奶', '芋泥木薯炖奶', '超级黑桑葚冰茶', '葡萄仙芋', '抹茶仙芋', '现制冷泡茶', '粉芭乐香柠拿铁', '奶油粉芭乐', '芭乐柠檬冰茶', '葡萄气泡康普茶', '橙C气泡康普茶', '薄荷冰淇淋拿铁', '莓果四重奏', '超A养颜杯', '小莓好轻乳茶', '黑糖珍珠抹茶', '黑糖珍珠奶茶', '金桔柠檬', '香柠鸭屎香', '哈密瓜轻乳茶', '烤奶牛乳茶', '生椰拿铁', '橙C美式', '翠峰茉莉奶盖', '白芽奇兰', '翠峰茉莉']
  },
  {
    id: 'brand-chayan-yuese', name: '茶颜悦色', aliases: ['茶颜', '茶颜悦色奶茶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/cha-yan-yue-se/menu/available',
    products: ['声声乌龙', '素颜锡兰', '幽兰拿铁', '桂花弄', '麻瓜的黄油世界', '橘子落日', '杨梅过雨', '忙着去撒野', '梨园花腔（拿铁）', '梨园花腔（美式）', '柚得半日闲', '不完蛋挞（拿铁）', '不完蛋挞（美式）', '柚在青云端', '梨园花腔', '有点小梨想', '水蜜桃']
  },
  {
    id: 'brand-molynb', name: '茉莉奶白', aliases: ['Jasmine Milk White'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/mo-li-nai-bai/menu/available',
    products: ['茉莉奶白', '一朵茉莉花', '针王葡萄', '白兰', '咸奶萃碎银子', '四季酸木瓜橄榄杏', '开心加倍茉莉椰', '三朵玉兰咖啡特调', '玉兰花语咖啡特调', '单丛奶霜苹果', '单丛与苹果', '单丛与苹果杏', '针王橘子', '针王苹果', '三朵玉兰', '玉兰花语', '针王奶霜橘子', '白兰与树番茄']
  },
  {
    id: 'brand-amasha', name: '阿嬷手作', aliases: ['阿嬷', '阿嬷手作茶饮'], category: '新茶饮',
    sourceType: 'pending', sourceName: '杭州城市限定新品报道；完整菜单待补',
    sourceUrl: 'https://www.xinhuanet.com/ci/20260920/d577ffc5202d42d19c8eaf763e8e91e8/c.html',
    products: [{
      name: '桂花酒酿一米',
      sourceType: 'pending',
      sourceName: '新华网报道阿嬷手作杭州城市限定新品（2026-09-20）',
      sourceUrl: 'https://www.xinhuanet.com/ci/20260920/d577ffc5202d42d19c8eaf763e8e91e8/c.html',
      menuEntry: {
        scope: 'city', city: '杭州', status: 'pending', sourceType: 'pending',
        sourceName: '杭州城市限定新品报道；淘宝闪购门店菜单待核验',
        sourceUrl: 'https://www.xinhuanet.com/ci/20260920/d577ffc5202d42d19c8eaf763e8e91e8/c.html'
      }
    }]
  },
  {
    id: 'brand-happy-sweet-potato', name: '快乐番薯', aliases: ['快乐番薯奶茶'], category: '新茶饮',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/kuai-le-fan-shu/menu/available',
    products: ['招牌薯圆奶茶', '老红糖珍珠奶茶', '阳光青提冰奶', '多肉阳光青提', '超长杯青提香水柠', '抹茶琥珀珍奶', '抹茶香柠冰奶', '葡萄芝士胶原冻', '鸭屎香单从', '幽兰奶绿', '葡萄椰果冰', '抹茶粉芭乐', '百香菠萝双重奏', '超长杯西瓜菠萝冰', '霸王桶柠檬红茶', '霸王桶冬瓜烧仙草', '多肉玫珑蜜瓜', '玫珑蜜瓜奶盖', '玫珑蜜瓜雪泡', '霸王桶香柠粉芭乐', '百香金菠萝', '多肉葡萄', '桃桃椰果冰', '莓莓酸奶昔', '桃桃酸奶昔', '桃桃奶绿双皮奶', '杨枝甘露双皮奶', '百香果双响炮', '招牌薯圆牛乳', '老红糖珍珠牛乳', '超长杯满满鲜橙多', '超长杯冰鲜柠檬水']
  },
  {
    id: 'brand-ye-ye-bu-pao-cha', name: '爷爷不泡茶', aliases: ['爷爷不泡茶茶饮'], category: '新茶饮',
    sourceType: 'official_brand', sourceName: '爷爷不泡茶官网产品系列',
    sourceUrl: 'https://www.yeyebpc.com/products/series/',
    products: ['栀子龙眼椰', '鲜台芒·嚼酸奶', '奇香桃桃', '草莓桃·嚼酸奶', '美十三草莓奶冻', '美十三草莓牛奶冰', '荔枝冰酿', '奶油米酒', '杨梅冰酿', '兰香青柠', '奇香青柠', '西西里柠檬柚', '西班牙红葡萄冰茶', '西瓜冰茶', '鲜·玫瑰荔枝', '爆打十五次·奇兰柠檬茶', '初恋玫瑰青提', '空山栀子', '咸宁桂花', '红苹果', '武汉茉莉', '水蜜桃', '白兰玉露']
  },
  {
    id: 'brand-shuyi', name: '书亦烧仙草', aliases: ['书亦', '书亦烧仙草奶茶'], category: '新茶饮',
    sourceType: 'official_brand', sourceName: '书亦烧仙草官网产品页',
    sourceUrl: 'https://www.shuyisxc.com/home/product/index/id/13.html',
    products: ['红豆夹心糯糯珠', '老红糖珍珠奶茶', '招牌芋圆奶绿']
  },
  {
    id: 'brand-lucky-coffee', name: '幸运咖', aliases: ['幸运咖啡', 'Lucky Cup'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/xing-yun-ka/menu/available',
    products: ['经典美式', '椰椰拿铁', '铁观音拿铁', '招牌冰拿铁', '岭南荔枝幸运冰', '杨梅吐气幸运冰', '福云抹茶维也纳', '福云维也纳', '大杯回柑香柠茉莉', '回柑香柠茉莉', '大圣桶杏运冰茶', '可可咖啡', '可可牛奶', '回柑杨桃茉莉', '回柑杨桃美式', '全冰醇香拿铁']
  },
  {
    id: 'brand-huka', name: '沪咖', aliases: ['沪咖东方拿铁', 'HUKA'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开品牌页与饮品列表',
    sourceUrl: 'https://www.nckfhsm.com/brands/hu-ka',
    products: ['鲜柠美式', '生椰拿铁', '大红袍拿铁', '美式咖啡']
  },
  {
    id: 'brand-mstand', name: 'M Stand', aliases: ['M Stand Coffee', 'MStand'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/brands/m-stand/menu/available',
    products: ['澳白', '咸芝士拿铁', '荞麦乌龙水牛乳拿铁', '荞麦乌龙水牛乳Dirty', '香草籽布丁拿铁', '香草籽布丁Dirty', '超大杯冰美式（小蓝莓风味拼配）', '超大杯加浓冰美式（小蓝莓风味拼配）', '超大杯冰拿铁（小蓝莓风味拼配）', '芒果米布丁拿铁', '芒果凤梨云朵', '超大杯芒果凤梨云朵', '芒果凤梨气泡美式', '芒果凤梨冰茶', '冰摇荔枝山竹特饮', '超大杯冷萃（紫葡萄风味）', '超大杯芒果凤梨气泡美式', '超大杯芒果凤梨冰茶', '超大杯冰摇荔枝山竹特饮', '冷萃咖啡（紫葡萄风味）']
  },
  {
    id: 'brand-bestar', name: '比星咖啡', aliases: ['Bestar', 'Bestar比星咖啡'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单汇编',
    sourceUrl: 'https://www.nckfhsm.com/zh-tw/brands/bestar-bi-xing-ka-fei/menu/available',
    products: ['零下86℃超低温香草Dirty', '琥珀干酪美式', '柠香芝士维也纳', '轻芝士拿铁', '威廉斯香蕉拿铁', '凤梨香桃叶气泡冰萃', '超超超大杯话梅柠檬冰茶', '超超超大杯轻因话梅美式', '滇薄荷油柑气泡冰萃', '油柑青薄荷', '咸奶油美式', '黄油波波乌龙', '柚子乌龙干酪', '青柠茉莉干酪', '黄油波波玛奇朵', '香草锡兰玛奇朵', '抹茶·咸柚丁', '满杯维C柠檬水', '山茶白葡萄冷萃', '紫苏话梅气泡冰萃']
  },
  {
    id: 'brand-shangdao', name: '上岛咖啡', aliases: ['上岛', '上岛咖啡馆'], category: '咖啡',
    sourceType: 'pending', sourceName: '大陆在售饮品菜单待补', sourceUrl: '', products: []
  },
  {
    id: 'brand-lanwan', name: '蓝湾咖啡', aliases: ['蓝湾', 'Blue Bay Coffee'], category: '咖啡',
    sourceType: 'pending', sourceName: '大陆在售饮品菜单待补', sourceUrl: '', products: []
  },
  {
    id: 'brand-dio', name: '迪欧咖啡', aliases: ['迪欧', 'DIO Coffee'], category: '咖啡',
    sourceType: 'pending', sourceName: '在售饮品菜单待补', sourceUrl: '', products: []
  },
  {
    id: 'brand-cat-shit-coffee', name: '猫屎咖啡', aliases: ['猫屎咖啡店', 'Kafelaku Coffee'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '携程猫屎咖啡（文化公园店）菜单推荐样本（广州）',
    sourceUrl: 'https://gs.ctrip.com/html5/you/foods/fooddetail/152/133588251.html',
    menuEntry: { scope: 'store', city: '广州', storeName: '猫屎咖啡（文化公园店）' },
    products: ['椰香抹茶冰雪乐', '苏打美式', '燕麦桂花酒酿拿铁', '芒果西番莲冰雪乐', '黑加仑蓝莓冰雪乐', '椰青冰美式', '越南冰奶咖啡', '玫瑰拿铁', '苏门答腊猫屎咖啡', '玫瑰海盐拿铁', '热拿铁', '卡布奇诺', '菠萝冰美式']
  },
  {
    id: 'brand-pacific-coffee', name: '太平洋咖啡', aliases: ['Pacific Coffee', 'Pacific Coffee Company'], category: '咖啡',
    sourceType: 'pending', sourceName: '大陆在售饮品菜单待补', sourceUrl: '', products: []
  },
  {
    id: 'brand-four-leaf-coffee', name: '四叶咖', aliases: ['四叶咖啡', 'Four Leaf Coffee'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开饮品条目',
    sourceUrl: 'https://www.nckfhsm.com/products/jing-dian-mei-shi-48067',
    products: ['经典美式', '澳白', '滇红臻巧拿铁', '版纳酸角美式', '牛肝菌芝士美式（冷）', '雪顶拿铁冰（冰沙）', '南华山楂美式']
  },
  {
    id: 'brand-jueke', name: '爵渴咖啡', aliases: ['爵渴', 'Jueke Coffee'], category: '咖啡',
    sourceType: 'public_menu', sourceName: '咖啡奶茶喝什么公开在售菜单汇编（需剔除混入的餐食）',
    sourceUrl: 'https://www.nckfhsm.com/brands/jue-ke-ka-fei/menu/available',
    products: ['超超超大桶水果茶', '生椰拿铁', '茉莉奶绿', '香柠冰咖', '香柠冰奶', '茉荔冰美式', '荔枝柠檬冰茶', '经典美式16oz', '果蔬轻拿铁', '冰淇淋拿铁']
  }
];

const brands = catalogSources.map((item) => ({
  id: item.id,
  name: item.name,
  aliases: item.aliases,
  category: item.category,
  source: `${item.sourceName}；淘宝闪购具体门店待核验`,
  updatedAt,
  active: true,
  status: 'pending'
}));

const drinks = catalogSources.flatMap((brand) => Array.from(new Map(brand.products.map((product) => {
  const item = typeof product === 'string' ? { name: product } : product;
  return [item.name, item];
})).values()).map((product, index) => {
  const sourceType = product.sourceType || brand.sourceType;
  const sourceName = product.sourceName || brand.sourceName;
  const sourceUrl = product.sourceUrl || brand.sourceUrl;
  const menuEntry = { ...(brand.menuEntry || {}), ...(product.menuEntry || {}) };
  const source = `${sourceName}；淘宝闪购具体门店待核验`;
  return {
    id: `${brand.id}-drink-${index + 1}`,
    brandId: brand.id,
    brandName: brand.name,
    name: product.name,
    aliases: [],
    category: brand.category,
    active: true,
    source,
    sourceType,
    updatedAt,
    status: 'pending',
    cupTypes: [],
    cupSizes: [],
    sizesMl: [],
    sweetnessOptions: [],
    servingOptions: [],
    nutritionVariants: [],
    menuEntries: [{
      ...menuEntry,
      scope: menuEntry.scope || 'brand',
      status: menuEntry.status || 'pending',
      sourceType: menuEntry.sourceType || sourceType,
      sourceName: menuEntry.sourceName || sourceName,
      sourceUrl: menuEntry.sourceUrl || sourceUrl,
      checkedAt: menuEntry.checkedAt || checkedAt,
      cupTypes: [], cupSizes: [], sizesMl: [], sweetnessOptions: [], servingOptions: []
    }]
  };
}));

module.exports = { brands, drinks, updatedAt, version };
