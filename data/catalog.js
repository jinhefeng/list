const updatedAt = '2026-10-13';
const source = '示例菜单，具体在售款式请以品牌门店为准';

const brands = [
  { id: 'brand-mixue', name: '蜜雪冰城', source, updatedAt, active: true },
  { id: 'brand-heytea', name: '喜茶', source, updatedAt, active: true },
  { id: 'brand-nayuki', name: '奈雪的茶', source, updatedAt, active: true },
  { id: 'brand-starbucks', name: '星巴克', source, updatedAt, active: true },
  { id: 'brand-chagee', name: '霸王茶姬', source, updatedAt, active: true }
];

const names = {
  'brand-mixue': ['冰鲜柠檬水', '珍珠奶茶', '棒打鲜橙'],
  'brand-heytea': ['多肉葡萄', '芝芝莓莓', '烤黑糖波波牛乳'],
  'brand-nayuki': ['霸气橙子', '茉莉初雪', '宝藏茶'],
  'brand-starbucks': ['美式咖啡', '拿铁', '焦糖玛奇朵'],
  'brand-chagee': ['伯牙绝弦', '花田乌龙', '桂馥兰香']
};

const drinks = brands.flatMap((brand) => names[brand.id].map((name, index) => ({
  id: `${brand.id}-drink-${index + 1}`,
  brandId: brand.id,
  brandName: brand.name,
  name,
  active: true,
  source,
  region: '中国大陆（示例）',
  updatedAt,
  sizes: [300, 500, 700],
  sweetnessOptions: ['不另外加糖', '三分糖', '五分糖', '七分糖', '全糖'],
  iceOptions: ['常温', '少冰', '正常冰', '去冰', '热饮'],
  toppingOptions: ['珍珠', '椰果', '奶盖', '布丁'],
  nutritionVariants: []
})));

module.exports = { brands, drinks };
