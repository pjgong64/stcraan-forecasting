// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// ====================================================================
// Vegetation Health Index (VHI) (Time-Series Sequence)
// Target: Monthly (5-12) 2020
// Historical Baseline: 10 Years (2010 - 2019)
// Datasets: MODIS Surface Reflectance (MOD09GA) & MODIS LST (MOD11A1)
// ====================================================================

var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");

// 1. Define time parameters
var targetYear = 2022;
var histStartYear = 2012;
var histEndYear = 2021;
// Define the list of target months for the sequence (8=Aug, 9=Sep, 10=Oct, 11=Nov)
var targetMonths = ee.List([5, 6, 7, 8, 9, 10, 11, 12]); 
var alpha = 0.5;    // Weight for VCI and TCI (0.5 implies equal contribution)

// ==========================
// 2. Prepare Datasets (NDVI & LST)
// ==========================

// Function to calculate and extract NDVI
var getNDVI = function(img) {
  var ndvi = img.normalizedDifference(['sur_refl_b02', 'sur_refl_b01']).rename('NDVI');
  return img.addBands(ndvi).select('NDVI');
};

var modisNDVI = ee.ImageCollection('MODIS/061/MOD09GA').map(getNDVI);
var modisLST = ee.ImageCollection('MODIS/061/MOD11A1').select(['LST_Day_1km'], ['LST']);

// Retrieve native projection from NDVI (500m) to use as the standard scale
var proj = modisNDVI.first().projection();

// ==========================
// 3. Core Processing Function (Iterate over Months)
// ==========================
// This function calculates VCI, TCI, VHI, and Zonal Statistics for each specified month
var calculateMonthlyVHI = function(month) {
  month = ee.Number(month);
  var monthStr = ee.String('M').cat(month.format('%02d')); // e.g., M08, M09
  
  // -- A. Retrieve Current Year (2020) Values for the specific month
  var targetFilter = ee.Filter.and(
    ee.Filter.calendarRange(targetYear, targetYear, 'year'),
    ee.Filter.calendarRange(month, month, 'month')
  );
  
  var ndvi_t = modisNDVI.filter(targetFilter).max().rename('NDVI_t');
  var lst_t = modisLST.filter(targetFilter).max().rename('LST_t');
  
  // -- B. Calculate Historical Baselines (2010-2019) for the SAME specific month
  var histYears = ee.List.sequence(histStartYear, histEndYear);
  var histImages = ee.ImageCollection.fromImages(histYears.map(function(y) {
    var yearFilter = ee.Filter.and(
      ee.Filter.calendarRange(y, y, 'year'),
      ee.Filter.calendarRange(month, month, 'month')
    );
    var maxNDVI = modisNDVI.filter(yearFilter).max().rename('NDVI');
    var maxLST = modisLST.filter(yearFilter).max().rename('LST');
    return maxNDVI.addBands(maxLST).set('year', y);
  }));
  
  // Calculate the 10-year historical maximums and minimums
  var ndvi_max = histImages.select('NDVI').max();
  var ndvi_min = histImages.select('NDVI').min();
  var lst_max = histImages.select('LST').max();
  var lst_min = histImages.select('LST').min();

  // -- C. Calculate Spatio-Temporal Indices (VCI, TCI, and VHI)
  // VCI = (NDVI_t - NDVI_min) / (NDVI_max - NDVI_min)
  var vci_denom = ndvi_max.subtract(ndvi_min);
  var vci = ndvi_t.subtract(ndvi_min).divide(vci_denom).rename('VCI');
  
  // TCI = (LST_max - LST_t) / (LST_max - LST_min)
  var tci_denom = lst_max.subtract(lst_min);
  var tci = lst_max.subtract(lst_t).divide(tci_denom).rename('TCI');
  
  // VHI = (alpha * VCI) + ((1 - alpha) * TCI)
  var vhi = vci.multiply(alpha).add(tci.multiply(1 - alpha)).rename('VHI');
  
  // Combine all layers into a single multi-band image for reduction
  var combinedImage = ee.Image([ndvi_t, lst_t, vci, tci, vhi]);

  // -- D. ZONAL STATISTICS (Reduce Regions)
  var stats = combinedImage.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(), 
    scale: 500, // Enforce 500m scale; GEE will seamlessly resample 1km LST
    crs: proj
  });

  // Remove Geometry and append tracking columns for LSTM sequence building
  return stats.map(function(f) {
    return ee.Feature(null, {
      'adm3_pcode': f.get('adm3_pcode'),
      'target_year': targetYear,
      'month_idx': month,          // Numeric month (8, 9, 10, 11)
      'month_label': monthStr,     // Formatted label (M08, M09...)
      'NDVI_t': f.get('NDVI_t'),
      'LST_t': f.get('LST_t'),
      'VCI': f.get('VCI'),
      'TCI': f.get('TCI'),
      'VHI': f.get('VHI')
    });
  });
};

// ==========================
// 4. Execution & Flattening
// ==========================
// Map the processing function over the target months
var monthlyResultsList = targetMonths.map(calculateMonthlyVHI);

// Flatten the List of Collections into a single continuous DataFrame (Long format)
var finalExportTable = ee.FeatureCollection(monthlyResultsList).flatten();


// ==========================
// 5. Clean up & Export
// ==========================
print("Preview Monthly VHI Results:", finalExportTable.limit(20));

Export.table.toDrive({
  collection: finalExportTable,
  description: 'Thailand_Tambon_VHI_MonthlySeq' + targetYear,
  fileFormat: 'CSV',
  // Explicitly select columns to maintain clean data for Python/R processing
  selectors: ['adm3_pcode', 'target_year', 'month_idx', 'month_label', 'NDVI_t', 'LST_t', 'VCI', 'TCI', 'VHI']
});