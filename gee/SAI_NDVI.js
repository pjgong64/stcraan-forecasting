// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// ====================================================================
// Standardized Anomaly Index (SAI) of NDVI (Time-Series Sequence)
// Target: Monthly (5-12) 2020
// Historical Baseline: 10 Years (2010 - 2019)
// ====================================================================

var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");

// 1. Define parameters
var targetYear = 2022;
var histStartYear = 2012;
var histEndYear = 2021;
// Define the list of target months for the sequence (8=Aug, 9=Sep, 10=Oct, 11=Nov)
var targetMonths = ee.List([5, 6, 7, 8, 9, 10, 11, 12]); 

// 2. Function to calculate and select only the NDVI band
var getNDVI = function(img) {
  var ndvi = img.normalizedDifference(['sur_refl_b02', 'sur_refl_b01']).rename('NDVI');
  return img.addBands(ndvi).select('NDVI');
};

// Load all MODIS data and prepare the NDVI band
var modis = ee.ImageCollection('MODIS/061/MOD09GA').map(getNDVI);
var proj = modis.first().projection();

// ==========================
// 3. Core Processing Function (Iterate over Months)
// ==========================
// This function calculates the SAI and Zonal Statistics for each specified month
var calculateMonthlySAI = function(month) {
  month = ee.Number(month);
  var monthStr = ee.String('M').cat(month.format('%02d')); // e.g., M08, M09
  
  // -- A. Calculate NDVIt (Maximum NDVI) for the target month & year
  var ndvi_t = modis.filter(ee.Filter.calendarRange(targetYear, targetYear, 'year'))
                    .filter(ee.Filter.calendarRange(month, month, 'month'))
                    .max()
                    .rename('NDVI_t'); 
                    
  // -- B. Calculate Mu_hist and Sigma_hist for the SAME month across the 10-year baseline
  var histYears = ee.List.sequence(histStartYear, histEndYear);
  var histMaxImages = ee.ImageCollection.fromImages(histYears.map(function(y) {
    return modis.filter(ee.Filter.calendarRange(y, y, 'year'))
                .filter(ee.Filter.calendarRange(month, month, 'month'))
                .max()
                .set('year', y);
  }));
  
  var mu_hist = histMaxImages.mean().rename('mu_hist');
  var sigma_hist = histMaxImages.reduce(ee.Reducer.stdDev()).rename('sigma_hist');

  // -- C. Calculate SAI for this specific month
  var sai_ndvi = ndvi_t.subtract(mu_hist).divide(sigma_hist).rename('SAI_NDVI');
  var combinedImage = ee.Image([ndvi_t, mu_hist, sigma_hist, sai_ndvi]);

  // -- D. ZONAL STATISTICS for this specific month
  var stats = combinedImage.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(), 
    scale: 500, // Native MODIS resolution
    crs: proj
  });

  // Remove Geometry and append month details as new properties for clarity
  return stats.map(function(f) {
    return ee.Feature(null, {
      'adm3_pcode': f.get('adm3_pcode'),
      'target_year': targetYear,
      'month_idx': month,          // Numeric month (8, 9, 10, 11)
      'month_label': monthStr,     // Formatted label (M08, M09...)
      'NDVI_t': f.get('NDVI_t'),
      'mu_hist': f.get('mu_hist'),
      'sigma_hist': f.get('sigma_hist'),
      'SAI_NDVI': f.get('SAI_NDVI')
    });
  });
};

// ==========================
// 4. Execution & Flattening
// ==========================
// Map the processing function over the list of target months
// The result is a List of FeatureCollections (one collection per month)
var monthlyResultsList = targetMonths.map(calculateMonthlySAI);

// Flatten the List of Collections into a single, continuous FeatureCollection (Long format)
var finalExportTable = ee.FeatureCollection(monthlyResultsList).flatten();


// ==========================
// 5. Clean up & Export
// ==========================
print("Preview Monthly SAI Results:", finalExportTable.limit(20));

Export.table.toDrive({
  collection: finalExportTable,
  description: 'Thailand_Tambon_SAI_NDVI_MonthlySeq' + targetYear,
  fileFormat: 'CSV',
  // Arrange columns logically for downstream Machine Learning preprocessing
  selectors: ['adm3_pcode', 'target_year', 'month_idx', 'month_label', 'NDVI_t', 'mu_hist', 'sigma_hist', 'SAI_NDVI']
});