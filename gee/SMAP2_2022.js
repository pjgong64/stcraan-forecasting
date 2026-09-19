// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
var year = 2022;
var months = ee.List.sequence(5, 12);

// ==========================
// 2. DATA PREP (SWITCH TO ACTIVE SMAP DATASET)
// ==========================
// We use the "SPL4SMGP" dataset which is still active.
// We DO NOT filter by date globally to avoid cutting off edge days.
var smap = ee.ImageCollection("NASA/SMAP/SPL4SMGP/007");

// ==========================
// 3. MONTHLY COMPOSITES
// ==========================
var monthlyImages = ee.ImageCollection.fromImages(
  months.map(function(m) {
    
    // Define start/end for this specific month
    var start = ee.Date.fromYMD(year, m, 1);
    var end = start.advance(1, 'month');
    var dateStr = start.format('YYYY-MM');

    // Filter and Process
    var monthlyMean = smap.filterDate(start, end)
        .select('sm_surface') // Select the new band name
        .mean()               // Average of the month
        .multiply(50)         // CONVERSION: Fraction (0-0.5) * 50mm depth = mm water
        .rename('mean')       // Rename to 'mean' for the export
        .set('month', m)
        .set('year', year)
        .set('date_str', dateStr);

    return monthlyMean;
  })
);

// ==========================
// 4. ZONAL STATISTICS
// ==========================
var SM_Stats = monthlyImages.map(function(img) {
  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(),
    scale: 9000,      // New resolution is 9km (approx)
    crs: 'EPSG:4326'
  }).map(function(f) {
    return f.set({
      'observation_date': img.get('date_str'),
      'month': img.get('month'),
      'year': img.get('year')
    });
  });
}).flatten();

// ==========================
// 5. EXPORT
// ==========================
var exportTable = SM_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary([
    'adm3_pcode', 'observation_date', 'mean', 'month', 'year'
  ]));
});

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_SoilMoisture_2022_Fixed',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'year', 'month', 'mean']
});