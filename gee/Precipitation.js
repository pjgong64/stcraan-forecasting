// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
var startDate = '2022-05-01';
var endDate = '2022-12-31';
var year = 2022;
var months = ee.List.sequence(5, 12);

// 2. DATA PREP (CHIRPS)
var chirps = ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
               .filterDate(startDate, endDate)
               .map(function(img) {
                 return img.select('precipitation')
                           .set('month', img.date().get('month'))
                           .set('year', img.date().get('year'));
               });

// 3. MONTHLY COMPOSITES
var monthlyImages = ee.ImageCollection.fromImages(
  months.map(function(m) {
    return chirps.filter(ee.Filter.eq('month', m))
                 .sum() // **Important:** SUM the daily rain to get Monthly Total
                 .set('month', m)
                 .set('year', year)
                 .set('date_str', ee.Date.fromYMD(year, m, 1).format('YYYY-MM'));
  })
);

// 4. ZONAL STATISTICS
var Precip_Stats = monthlyImages.map(function(img) {
  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.sum(), // Sum of the "Total Rainfall" across the polygon pixels
    scale: 5566, // CHIRPS is approx 5.5km
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
var exportTable = Precip_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary(['adm3_pcode', 'observation_date', 'sum', 'month', 'year']));
});

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_Precipitation_2022',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'year', 'month', 'sum']
});