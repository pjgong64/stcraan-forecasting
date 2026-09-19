// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
//Collect data year by year to avoid running out of memory.
var startDate = '2020-05-01';
var endDate = '2020-12-31';
var year = 2020;
var months = ee.List.sequence(5, 12);

// 2. DATA PREP (MODIS LST)
var modisLST = ee.ImageCollection('MODIS/061/MOD11A1')
               .filterDate(startDate, endDate)
               .map(function(img) {
                 // Select LST_Day_1km band
                 // Scale factor is 0.02, then convert Kelvin to Celsius (-273.15)
                 var lst = img.select('LST_Day_1km')
                              .multiply(0.02)
                              .subtract(273.15)
                              .rename('LST_Celsius');
                 
                 return img.addBands(lst)
                           .select('LST_Celsius')
                           .set('month', img.date().get('month'))
                           .set('year', img.date().get('year'));
               });

// 3. MONTHLY COMPOSITES
var monthlyImages = ee.ImageCollection.fromImages(
  months.map(function(m) {
    return modisLST.filter(ee.Filter.eq('month', m))
                   .max() // Max of the month
                   .set('month', m)
                   .set('year', year)
                   .set('date_str', ee.Date.fromYMD(year, m, 1).format('YYYY-MM'));
  })
);

// 4. ZONAL STATISTICS
var LST_Stats = monthlyImages.map(function(img) {
  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.max(),
    scale: 1000, // MODIS LST is 1km
    crs: 'EPSG:4326'
  }).map(function(f) {
    return f.set({
      'observation_date': img.get('date_str'),
      'month': img.get('month'),
      'year': img.get('year')
    });
  });
}).flatten();

// 5. EXPORT
var exportTable = LST_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary(['adm3_pcode', 'max', 'month', 'year']));
});

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_LST_2020',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'month', 'year', 'max']
});