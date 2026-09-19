// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// ====================================================================
// Standardized Anomaly Index (SAI) of NDWI (Time-Series Sequence)
// Target: Monthly (5-12) 2020
// Historical Baseline: 10 Years (2010 - 2019)
// Dataset: MODIS Surface Reflectance (MOD09GA)
// ====================================================================

var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");

// 1. Define time parameters
var targetYear = 2022;
var histStartYear = 2012;
var histEndYear = 2021;
// Define the list of target months for the sequence (8=Aug, 9=Sep, 10=Oct, 11=Nov)
var targetMonths = ee.List([5, 6, 7, 8, 9, 10, 11, 12]); 

// ==========================
// 2. Prepare Dataset (NDWI)
// ==========================

// Function to calculate and extract the NDWI band
var getNDWI = function(img) {
  // Utilizing Gao's NDWI formula for Vegetation Water Content: (NIR - SWIR) / (NIR + SWIR)
  // For MODIS: NIR = sur_refl_b02, SWIR = sur_refl_b06
  var ndwi = img.normalizedDifference(['sur_refl_b02', 'sur_refl_b06']).rename('NDWI');
  return img.addBands(ndwi).select('NDWI');
};

// Load all MODIS data and prepare the NDWI band
var modisNDWI = ee.ImageCollection('MODIS/061/MOD09GA').map(getNDWI);

// Retrieve native projection to use as the standard scale for Zonal Statistics
var proj = modisNDWI.first().projection();

// ==========================
// 3. Core Processing Function (Iterate over Months)
// ==========================
// This function calculates SAI_NDWI and Zonal Statistics for each specified month
var calculateMonthlySAINDWI = function(month) {
  month = ee.Number(month);
  var monthStr = ee.String('M').cat(month.format('%02d')); // e.g., M08, M09
  
  // -- A. Calculate NDWI_t (Maximum NDWI) for the target month & year
  var ndwi_t = modisNDWI.filter(ee.Filter.calendarRange(targetYear, targetYear, 'year'))
                      .filter(ee.Filter.calendarRange(month, month, 'month'))
                      .max()
                      .rename('NDWI_t'); 
                      
  // -- B. Calculate Mu_hist and Sigma_hist for the SAME month across the 10-year baseline
  var histYears = ee.List.sequence(histStartYear, histEndYear);
  var histMaxImages = ee.ImageCollection.fromImages(histYears.map(function(y) {
    return modisNDWI.filter(ee.Filter.calendarRange(y, y, 'year'))
                  .filter(ee.Filter.calendarRange(month, month, 'month'))
                  .max()
                  .set('year', y);
  }));
  
  // Calculate the 10-year historical mean and standard deviation
  var mu_hist = histMaxImages.mean().rename('mu_hist');
  var sigma_hist = histMaxImages.reduce(ee.Reducer.stdDev()).rename('sigma_hist');

  // -- C. Calculate SAI_NDWI for this specific month
  // Equation: SAI_NDWI = (NDWI_t - mu_hist) / sigma_hist
  // Note: GEE automatically masks pixels where sigma_hist is 0
  var sai_ndwi = ndwi_t.subtract(mu_hist).divide(sigma_hist).rename('SAI_NDWI');
  var combinedImage = ee.Image([ndwi_t, mu_hist, sigma_hist, sai_ndwi]);

  // -- D. ZONAL STATISTICS for this specific month
  var stats = combinedImage.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(), 
    scale: 500, // Native MODIS resolution
    crs: proj
  });

  // Remove Geometry and append month details for sequential data structuring
  return stats.map(function(f) {
    return ee.Feature(null, {
      'adm3_pcode': f.get('adm3_pcode'),
      'target_year': targetYear,
      'month_idx': month,          // Numeric month (8, 9, 10, 11)
      'month_label': monthStr,     // Formatted label (M08, M09...)
      'NDWI_t': f.get('NDWI_t'),
      'mu_hist': f.get('mu_hist'),
      'sigma_hist': f.get('sigma_hist'),
      'SAI_NDWI': f.get('SAI_NDWI')
    });
  });
};

// ==========================
// 4. Execution & Flattening
// ==========================
// Map the processing function over the list of target months
var monthlyResultsList = targetMonths.map(calculateMonthlySAINDWI);

// Flatten the List of Collections into a single, continuous DataFrame (Long format)
var finalExportTable = ee.FeatureCollection(monthlyResultsList).flatten();


// ==========================
// 5. Clean up & Export
// ==========================
print("Preview Monthly SAI_NDWI Results:", finalExportTable.limit(20));

Export.table.toDrive({
  collection: finalExportTable,
  description: 'Thailand_Tambon_SAI_NDWI_MonthlySeq' + targetYear,
  fileFormat: 'CSV',
  // Arrange columns logically for downstream Python/R preprocessing
  selectors: ['adm3_pcode', 'target_year', 'month_idx', 'month_label', 'NDWI_t', 'mu_hist', 'sigma_hist', 'SAI_NDWI']
});