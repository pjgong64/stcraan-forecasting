// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
var startDate = '2020-05-01';
var endDate = '2020-12-31';

// 2. DATA PREP (VIIRS Monthly)
// We load the monthly collection directly.
var viirs = ee.ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG")
              .filterDate(startDate, endDate)
              .select('avg_rad'); // Average Radiance

// 3. ZONAL STATISTICS
// Since it is already monthly, we map directly over the collection
var Night_Stats = viirs.map(function(img) {
  // Extract Year/Month for labeling
  var y = img.date().get('year');
  var m = img.date().get('month');
  var dateStr = img.date().format('YYYY-MM');

  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(),
    scale: 500, // VIIRS DNB is approx 500m
    crs: 'EPSG:4326'
  }).map(function(f) {
    return f.set({
      'observation_date': dateStr,
      'month': m,
      'year': y
    });
  });
}).flatten();

// 4. EXPORT
var exportTable = Night_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary(['adm3_pcode', 'observation_date', 'mean', 'month', 'year']));
});

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_NightLights_2020',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'year', 'month', 'mean']
});