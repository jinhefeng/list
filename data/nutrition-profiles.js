// Product-level packaged drink nutrition references, normalized per 100 ml.
// Exact-label values retain their source SKU and market; broader name matches
// are marked estimated because package formulas can vary by market and size.
const PACKAGED_NUTRITION_PROFILES = [
  {
    id: 'coca-cola-zero-cn', label: '可口可乐无糖',
    aliases: ['可口可乐零度', '零度可口可乐', '可口可乐无糖', '无糖可口可乐', '可口可乐零糖', '可口可乐zero', 'coca-cola zero', 'coca cola zero', 'coke zero'],
    energyKjPer100Ml: 0, sugarGPer100Ml: 0, caffeineMgPer100Ml: null,
    sourceType: 'official', region: '中国大陆', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；湖北太古可口可乐330ml，条码6928804010091',
    sourceUrl: 'https://nlc.chinanutri.cn/food/TeocmrP5Rlu1zbVPL_kJzg.html'
  },
  {
    id: 'coca-cola-fiber-plus-cn', label: '可口可乐纤维+',
    aliases: ['可口可乐纤维+', '可口可乐纤维＋', 'coca-cola fiber+', 'coca cola fiber+', 'coke fiber+'],
    energyKjPer100Ml: 0, sugarGPer100Ml: 0, caffeineMgPer100Ml: null,
    sourceType: 'official', region: '中国大陆', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；上海申美500ml，条码6928804016970',
    sourceUrl: 'https://nlc.chinanutri.cn/food/Ez8qddoGQ_OIWJa6wNsMiw.html'
  },
  {
    id: 'sprite-zero-hk-reference', label: '无糖雪碧',
    aliases: ['无糖雪碧', '雪碧无糖', '雪碧零糖', '雪碧零卡', 'sprite zero', 'sprite zerosugar', 'sprite zero sugar'],
    energyKcalPer100Ml: 0, sugarGPer100Ml: 0, caffeineMgPer100Ml: 0,
    sourceType: 'estimated', region: '香港官方标签参考；中国大陆产品标注0糖', updatedAt: '2026-10-16',
    source: '可口可乐中国官网标注无糖雪碧0糖；香港官方营养标签列示0 kcal、0g糖',
    sourceUrl: 'https://www.coca-cola.com/hk/zh/brands/sprite'
  },
  {
    id: 'pepsi-zero-cn', label: '百事可乐无糖',
    aliases: ['百事可乐生可乐生爽无糖', '百事可乐生爽无糖', '生爽无糖', '百事可乐无糖', '无糖百事可乐', '百事可乐零度', '百事零度可乐', '百事可乐0糖', '0糖百事可乐', 'pepsi zero', 'pepsi zerosugar', 'pepsi zero sugar'],
    energyKjPer100Ml: 0, sugarGPer100Ml: 0, caffeineMgPer100Ml: null,
    sourceType: 'official', region: '中国大陆', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；百事生爽无糖330ml，条码6924862103676',
    sourceUrl: 'https://nlc.chinanutri.cn/food/YEGa0wc_RS6Cbqtij9WcYA.html'
  },
  {
    id: 'generic-zero-cola', label: '无糖可乐（通用）',
    aliases: ['无糖可乐', '可乐无糖', '不加糖可乐', '可乐零度', '零度可乐', '可乐零糖', '零糖可乐', 'zero cola', 'diet cola'],
    energyKjPer100Ml: 0, sugarGPer100Ml: 0, caffeineMgPer100Ml: null,
    sourceType: 'estimated', region: '通用估算', updatedAt: '2026-10-16',
    source: '无糖可乐通用估算；具体能量与咖啡因以包装标签为准', sourceUrl: ''
  },
  {
    id: 'coca-cola-regular-cn', label: '可口可乐（含糖）',
    aliases: ['可口可乐', 'coca-cola', 'coca cola', 'coke'],
    excludeAliases: ['无糖', '零糖', '零度', 'zero', 'diet', '纤维+'],
    energyKjPer100Ml: 180, sugarGPer100Ml: 10.6, caffeineMgPer100Ml: null,
    sourceType: 'estimated', region: '中国大陆代表性包装', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；330ml代表性SKU，条码6928804014570',
    sourceUrl: 'https://nlc.chinanutri.cn/food/Ok7S31KVS2Kh7WcIuS2Ykw.html'
  },
  {
    id: 'pepsi-regular-cn', label: '百事可乐（含糖）',
    aliases: ['百事可乐', 'pepsi'],
    excludeAliases: ['无糖', '零糖', '零度', 'zero', 'diet'],
    energyKjPer100Ml: 119, sugarGPer100Ml: 7, caffeineMgPer100Ml: null,
    sourceType: 'estimated', region: '中国大陆代表性包装', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；百事330ml代表性SKU，条码6933266607185',
    sourceUrl: 'https://nlc.chinanutri.cn/food/vG_FrRnGTqSGOgKIEPo84w.html'
  },
  {
    id: 'sprite-regular-cn', label: '雪碧（含糖）',
    aliases: ['雪碧', 'sprite'],
    excludeAliases: ['无糖', '零糖', '零度', 'zero', 'diet'],
    energyKjPer100Ml: 149, sugarGPer100Ml: 8.6, caffeineMgPer100Ml: 0,
    sourceType: 'estimated', region: '中国大陆代表性包装', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；北京2L代表性SKU，条码6954767433073',
    sourceUrl: 'https://nlc.chinanutri.cn/food/H35JA6-qQy-maZeId3adng.html'
  },
  {
    id: 'fanta-orange-hk-reference', label: '芬达橙味汽水',
    aliases: ['芬达', 'fanta'],
    excludeAliases: ['无糖', '零糖', '零度', 'zero', 'diet'],
    energyKcalPer100Ml: 32, sugarGPer100Ml: 8, caffeineMgPer100Ml: 0,
    sourceType: 'estimated', region: '香港官方标签参考', updatedAt: '2026-10-16',
    source: '可口可乐香港官方营养标签；橙味芬达每100ml，供同品牌常规款类比',
    sourceUrl: 'https://www.coca-cola.com/hk/zh/brands/fanta'
  },
  {
    id: 'laoshan-cola-cn', label: '崂山可乐',
    aliases: ['崂山可乐', 'laoshan cola'],
    energyKjPer100Ml: 158, sugarGPer100Ml: 9.3, caffeineMgPer100Ml: null,
    sourceType: 'official', region: '中国大陆', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；330ml，条码6922307203035',
    sourceUrl: 'https://nlc.chinanutri.cn/food/RGuWh93yTPCPzLR-wJju1A.html'
  },
  {
    id: 'watsons-tonic-cn', label: '屈臣氏汤力汽水',
    aliases: ['屈臣氏汤力汽水', '屈臣氏汤力水', 'watsons tonic'],
    energyKjPer100Ml: 143, sugarGPer100Ml: 8.4, caffeineMgPer100Ml: 0,
    sourceType: 'official', region: '中国大陆', updatedAt: '2026-10-16',
    source: '中国疾控中心营养与健康所预包装食品营养标签数据查询系统；330ml，条码6920180209694',
    sourceUrl: 'https://nlc.chinanutri.cn/food/2bKXsad1T72RRXOkZY6NBA.html'
  },
  {
    id: 'generic-cola', label: '可乐（通用）',
    aliases: ['可乐', 'cola'],
    excludeAliases: ['可口可乐', '百事可乐', '崂山可乐', '无糖', '零糖', '零度', 'zero', 'diet'],
    energyKcalPer100Ml: 36, sugarGPer100Ml: 8.8, caffeineMgPer100Ml: null,
    sourceType: 'estimated', region: '中国大陆包装标签类比', updatedAt: '2026-10-16',
    source: '可口可乐与百事可乐代表性包装标签的通用类比值；未估算咖啡因', sourceUrl: ''
  }
];

module.exports = { PACKAGED_NUTRITION_PROFILES };
