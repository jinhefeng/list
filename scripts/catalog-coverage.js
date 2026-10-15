#!/usr/bin/env node

const coverage = require('../data/catalog-coverage.json');
const catalog = require('../data/catalog');

const namesById = new Map(catalog.brands.map((brand) => [brand.id, brand.name]));
const countsById = new Map();
catalog.drinks.forEach((drink) => countsById.set(drink.brandId, (countsById.get(drink.brandId) || 0) + 1));

const statusLabels = {
  partial: '部分菜单',
  source_not_menu: '来源非菜单',
  source_missing: '缺菜单来源',
  source_contaminated: '来源混有餐食',
  complete: '已完成'
};
const rows = coverage.brands.map((item) => ({
  name: namesById.get(item.brandId) || item.brandId,
  candidates: countsById.get(item.brandId) || 0,
  sourceCount: item.sourceReportedInSaleItems === null ? '未知' : String(item.sourceReportedInSaleItems),
  pages: `${item.pagesReviewed}/${item.sourceReportedPages === null ? '?' : item.sourceReportedPages}`,
  status: statusLabels[item.status] || item.status
}));
const widths = {
  name: Math.max(6, ...rows.map((row) => row.name.length)),
  candidates: 8,
  sourceCount: 12,
  pages: 12
};

process.stdout.write(`目录范围：${coverage.scope.targetBrandCount} 个品牌；当前 ${catalog.brands.length} 个品牌、${catalog.drinks.length} 个候选饮品名。\n`);
process.stdout.write('候选数来自 catalog.js；来源收录数仅为网页自报，不能据此证明菜单完整。\n\n');
process.stdout.write(`${'品牌'.padEnd(widths.name)}  ${'候选名'.padStart(widths.candidates)}  ${'来源自报数'.padStart(widths.sourceCount)}  ${'已查页/总页'.padStart(widths.pages)}  状态\n`);
rows.forEach((row) => {
  process.stdout.write(`${row.name.padEnd(widths.name)}  ${String(row.candidates).padStart(widths.candidates)}  ${row.sourceCount.padStart(widths.sourceCount)}  ${row.pages.padStart(widths.pages)}  ${row.status}\n`);
});

const completeCount = coverage.brands.filter((item) => item.status === 'complete').length;
const missingSources = coverage.brands.filter((item) => item.status === 'source_missing').length;
process.stdout.write(`\n已按完整规则完成：${completeCount}/${coverage.brands.length}；缺少菜单来源：${missingSources}。\n`);
