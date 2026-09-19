// NOTE: the ADM3 boundary asset below is a placeholder. Upload the Thai
// sub-district boundaries from the Humanitarian Data Exchange as your own
// Earth Engine asset and put its path here.
// ====================================================================
// Heat Stress Days (Time-Series Sequence)
// Target: Monthly (May - December) 2020
// Dataset: MODIS Daily Land Surface Temperature (MOD11A1)
// Threshold: LST > 35 Degrees Celsius
// ====================================================================

var tambons = ee.FeatureCollection("REPLACE_WITH_YOUR_ADM3_ASSET");

// 1. Define time and threshold parameters
var targetYear = 2022;
// Define the list of target months for the sequence (5= 6 7 8=Aug, 9=Sep, 10=Oct, 11=Nov)
var targetMonths = ee.List([
  5, 6, 7, 8, 9, 10, 11, 12]); 
var heatThresholdCelsius = 35; 

// ==========================
// 2. Prepare Dataset
// ==========================
// Load MODIS Daily Land Surface Temperature (LST)
var modisLST = ee.ImageCollection('MODIS/061/MOD11A1').select(['LST_Day_1km']);

// Retrieve native projection to use as the standard scale for Zonal Statistics
var proj = modisLST.first().projection();

// ==========================
// 3. Core Processing Function (Iterate over Months)
// ==========================
// This function calculates the number of Heat Stress Days and Zonal Stats for each month
var calculateMonthlyHeatStress = function(month) {
  month = ee.Number(month);
  var monthStr = ee.String('M').cat(month.format('%02d')); // e.g., M08, M09
  
  // -- A. Filter daily LST data for the specific target month
  var dailyLST = modisLST.filter(ee.Filter.calendarRange(targetYear, targetYear, 'year'))
                         .filter(ee.Filter.calendarRange(month, month, 'month'));
                         
  // -- B. Apply Indicator Function (The Formula)
  // Map over every daily image in the isolated month's collection
  var heatStressCollection = dailyLST.map(function(img) {
    // Convert raw MODIS LST to Celsius: (Raw * 0.02) - 273.15
    var lstCelsius = img.multiply(0.02).subtract(273.15);
    
    // Apply Indicator Function: I(LST > 35)
    // .gt() returns a binary image: 1 if true (heat stress), 0 if false
    var isHeatStress = lstCelsius.gt(heatThresholdCelsius).rename('daily_stress_flag');
    
    return isHeatStress.set('system:time_start', img.get('system:time_start'));
  });

  // -- C. Sum all the daily 1s and 0s to get the total heat stress days for this month
  var totalHeatStressDays = heatStressCollection.sum().rename('Heat_Stress_Days');

  // -- D. ZONAL STATISTICS for this specific month
  // Calculate the average number of Heat Stress Days across each Tambon boundary
  var stats = totalHeatStressDays.reduceRegions({
    collection: tambons,
    reducer: ee.Reducer.mean(), 
    scale: 1000, // MODIS LST native resolution is 1km
    crs: proj
  });

  // Remove Geometry and append tracking columns for LSTM sequence building
  return stats.map(function(f) {
    return ee.Feature(null, {
      'adm3_pcode': f.get('adm3_pcode'),
      'target_year': targetYear,
      'month_idx': month,          // Numeric month (8, 9, 10, 11)
      'month_label': monthStr,     // Formatted label (M08, M09...)
      // The 'mean' column holds the average days computed by reduceRegions
      'Heat_Stress_Days': f.get('mean') 
    });
  });
};

// ==========================
// 4. Execution & Flattening
// ==========================
// Map the processing function over the target months
var monthlyResultsList = targetMonths.map(calculateMonthlyHeatStress);

// Flatten the List of Collections into a single continuous DataFrame (Long format)
var finalExportTable = ee.FeatureCollection(monthlyResultsList).flatten();


// ==========================
// 5. Clean up & Export
// ==========================
print("Preview Monthly Heat Stress Results:", finalExportTable.limit(20));

Export.table.toDrive({
  collection: finalExportTable,
  description: 'Thailand_Tambon_Heat_Stress_MonthlySeq' + targetYear,
  fileFormat: 'CSV',
  // Arrange columns logically for downstream Machine Learning preprocessing
  selectors: ['adm3_pcode', 'target_year', 'month_idx', 'month_label', 'Heat_Stress_Days']
});