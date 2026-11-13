const fs = require('node:fs');
const path = require('node:path');
const seed = require('../data/catalog');

function createIOSCatalog(catalog) {
  return {
    version: catalog.version,
    updatedAt: catalog.updatedAt,
    brands: catalog.brands,
    drinks: catalog.drinks
  };
}

if (require.main === module) {
  const destination = path.resolve(process.argv[2] || path.join(__dirname, '../ios/GanfanHandbook/Resources/catalog.json'));
  fs.writeFileSync(destination, `${JSON.stringify(createIOSCatalog(seed), null, 2)}\n`);
  process.stdout.write(`Exported ${seed.brands.length} brands and ${seed.drinks.length} drinks to ${destination}\n`);
}

module.exports = { createIOSCatalog };
