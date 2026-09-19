// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// 1. Define Area of Interest (Thailand Tambons) and set vars
var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");
//Map.centerObject(tambons, 6);
//Map.addLayer(tambons, {color: 'blue'}, "Thailand Tambons", false);


//Collect data year by year to avoid running out of memory.
var startDate = '2022-05-01';
var endDate = '2022-12-31';
var year = 2022;
var months = ee.List.sequence(5, 12);

// Load MODIS MOD09GA Collection 6.1 (Daily Surface Reflectance 500m)
var modis = ee.ImageCollection('MODIS/061/MOD09GA')
               .filterDate(startDate, endDate)
               .map(function(img) {
                 // Calculate NDVI: (NIR - Red) / (NIR + Red)
                 // MODIS: NIR = sur_refl_b02, Red = sur_refl_b01
                 var ndvi = img.normalizedDifference(['sur_refl_b02', 'sur_refl_b01'])
                               .rename('NDVI');
                 
                 // Add the NDVI band and time properties
                 return img.addBands(ndvi)
                           .select('NDVI') // Keep only the NDVI band to save memory
                           .set('month', img.date().get('month'))
                           .set('year', img.date().get('year'));
               });


// ==========================
// 3. MONTHLY COMPOSITES
// ==========================

// Create an ImageCollection where every image is the mean for one month
var monthlyImages = ee.ImageCollection.fromImages(
  months.map(function(m) {
    var monthlyMax = modis.filter(ee.Filter.eq('month', m))
                           .max() // max images in that month
                           .set('month', m)
                           .set('year', year)
                           // Create a readable date string for the CSV (e.g., "2022-08")
                           .set('date_str', ee.Date.fromYMD(year, m, 1).format('YYYY-MM'));
    return monthlyMax;
  })
);

// ==========================
// 5. ZONAL STATISTICS (REDUCE REGIONS)
// ==========================

// Get projection info from the first image to ensure consistent scaling
var proj = ee.Image(modis.first()).projection();

// Calculate the mean NDVI for every Tambon feature for every month
// This results in a flattened FeatureCollection
var NDVI_Stats = monthlyImages.map(function(img) {
  // For each monthly image, calculate statistics over the tambon regions
  return img.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.max(),
    scale: 500, // MODIS native resolution
    crs: proj
  }).map(function(f) {
    return f.set({
      'observation_date': img.get('date_str'),
      'month': img.get('month'),
      'year': img.get('year')
    });
  });
}).flatten();

// 5. Clean up output (Remove geometry to make CSV export faster/smaller)
var exportTable = NDVI_Stats.map(function(f) {
  return ee.Feature(null, f.toDictionary([
    'adm3_pcode', 'observation_date', 'max'
  ]));
});

// 6. Console and Export

Export.table.toDrive({
  collection: exportTable,
  description: 'Thailand_Tambon_NDVI_2022',
  fileFormat: 'CSV',
  selectors: ['adm3_pcode', 'observation_date', 'max']
});








