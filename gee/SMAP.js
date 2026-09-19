// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
var startDate = '2020-05-01';
var endDate = '2020-12-31';
var year = 2020;
var months = ee.List.sequence(5, 12);

// 2. DATA PREP (SMAP)
var smap = ee.ImageCollection("NASA_USDA/HSL/SMAP10KM_soil_moisture")
             .filterDate(startDate, endDate)
             .map(function(img) {
               return img.select('ssm') // Surface Soil Moisture
                         .set('month', img.date().get('month'))
                         .set('year', img.date().get('year'));
             });

// 3. MONTHLY COMPOSITES
var monthlyImages = ee.ImageCollection.fromImages(
  months.map(function(m) {
    return smap.filter(ee.Filter.eq('month', m))
               .mean() 
               .set('month', m)
               .set('year', year)
               .set('date_str', ee.Date.fromYMD(year, m, 1).format('YYYY-MM'));
  })
);

// 4. ZONAL STATISTICS
var SM_Stats = monthlyImages.map(function(img) {
  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(),
    scale: 10000, // SMAP is approx 10km
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
var exportTable = SM_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary(['adm3_pcode', 'observation_date', 'mean', 'month', 'year']));
});

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_SoilMoisture_2020',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'year', 'month', 'mean']
});