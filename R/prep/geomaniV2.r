options(scipen = 999)
library(data.table)
library(purrr)

# 1. Define the list of file names
file_list <- c("NDVI", "NDWI", "LST", "Precipitation", "SMAP", "NTL",
               "SAI_NDVI", "VHI", "SAI_NDWI", "Rainfall_Deficit",
               "Heat_Stress_Days")

# 2. File-processing function (includes automatic column-name detection)
process_satellite_file <- function(file_name) {

  file_path <- file.path("geo2/2020/", paste0(file_name, ".csv"))

  # Check first whether the file actually exists, to avoid file-system errors
  if (!file.exists(file_path)) {
    warning(paste("File not found:", file_path))
    return(NULL)
  }

  # Read the file
  dt <- fread(file_path, encoding = "UTF-8")

  # Initial data preparation
  dt[, ADM3 := gsub("TH", "", adm3_pcode)]
  dt[, Year := 1]
  dt[, col_name := paste0(file_name, dt$month)]

  # --- [Key fix] automatic detection of the value column ---
  # If a column shares its name with file_name, use that column
  if (file_name %in% names(dt)) {
    target_value_col <- file_name
  } else {
    # Otherwise, look for a non-control column (the remaining column is picked automatically)
    control_cols <- c("adm3_pcode", "ADM3", "Year", "month", "col_name")
    remaining_cols <- setdiff(names(dt), control_cols)

    # Take the first remaining column as the value (usually that file's value column)
    target_value_col <- remaining_cols[1]
  }

  # Guard against the case where nothing is found
  if (is.na(target_value_col) || length(target_value_col) == 0) {
    stop(paste("No value column found in file:", file_name))
  }
  # -----------------------------------------------------

  # Reshape to wide format using the column we detected
  dt_wide <- dcast(dt,
                   ADM3 + Year ~ col_name,
                   value.var = target_value_col, # use the detected variable instead of hardcoding
                   fun.aggregate = mean)

  return(dt_wide)
}

# 3. Run the loop
processed_list <- lapply(file_list, process_satellite_file)

# Drop NULL entries from the list (in case some file could not be opened)
processed_list <- compact(processed_list)

# 4. Merge every table in the list into a single master wide table
# Use Reduce with merge to join tables on ADM3 and Year
final_satellite_dt <- Reduce(function(x, y) merge(x, y, by = c("ADM3", "Year"), all = TRUE),
                             processed_list)

# 5. Reorder columns nicely (Year, ADM3 first, the rest after)
setcolorder(final_satellite_dt, c("Year", "ADM3"))

# 1. Define the desired order of the variable-group names
prefix_order <- c("NDVI", "NDWI", "LST", "Precipitation", "SMAP", "NTL",
                  "SAI_NDVI", "VHI", "SAI_NDWI", "Rainfall_Deficit", "Heat_Stress_Days")

# 2. Define the order of the months
months <- 5:12

# 3. Build the full list of desired columns (Year, ADM3, then variables ordered by group and month)
# Use nested loops to create every combination of group and month
target_cols <- c("Year", "ADM3")

for (p in prefix_order) {
  for (m in months) {
    target_cols <- c(target_cols, paste0(p, m))
  }
}

# 4. Verify these columns actually exist in the table (guard against months with no data)
final_cols <- intersect(target_cols, names(final_satellite_dt))

# 5. Apply the new column order
setcolorder(final_satellite_dt, final_cols)
new_row <- data.table(Year = 1, ADM3 = "530407")  # Year 1 2 3
#final_satellite_dt[ADM3 == "530407", Year := 1]
final_satellite_dt <- rbind(final_satellite_dt, new_row, fill = TRUE)
setorder(final_satellite_dt, ADM3)
fwrite(final_satellite_dt, file = "geo2020.txt", sep = "|")  # 20 21 22


###====================================###
### Temporal-Geo Data Imputation ####
###====================================###
dt_geo <- fread("geo2022.txt", sep = "|", encoding = "UTF-8")  # 20 21 22
print(colSums(is.na(dt_geo)))
### Spatio-Temporal Imputation

# Build the district code (ADM2) from the first 4 digits
dt_geo[, ADM2 := substr(ADM3, 1, 4)]
# Define the variables for the loop
base_features <- c("NDVI", "NDWI", "LST", "Precipitation", "SMAP", "NTL",
                   "SAI_NDVI", "VHI","SAI_NDWI", "Rainfall_Deficit",
                   "Heat_Stress_Days") # base feature names
months_list <- 5:12                      # months available in the data (e.g. 1:12 or 5:10)
# ==========================================
# 2. Start the imputation process (nested loop: feature x month)
# ==========================================
for (f in base_features) {
  for (m in months_list) {
    # Build column names dynamically
    target_col <- paste0(f, m)       # e.g. "NDVI5"
    lag_col    <- paste0(f, m - 1)   # e.g. "NDVI4"
    lead_col   <- paste0(f, m + 1)   # e.g. "NDVI6"
    # Skip this iteration if the table lacks this column (e.g. the loop hits LST but it was not supplied)
    if (!target_col %in% names(dt_geo)) next

    # --- a. Compute the temporal component (X_temp) ---
    # Pull the previous and next month; if the column does not exist (e.g. first/last month) use NA
    dt_geo[, temp_lag  := if (lag_col %in% names(dt_geo)) get(lag_col) else NA_real_]
    dt_geo[, temp_lead := if (lead_col %in% names(dt_geo)) get(lead_col) else NA_real_]

    # fcoalesce takes the average; if one month is missing, fall back to the other
    dt_geo[, X_temp := fcoalesce((temp_lag + temp_lead) / 2, temp_lag, temp_lead)]

    # --- b. Compute the spatial component (X_spatial) ---
    # Average that feature-month at the district (ADM2) level
    spatial_avg <- dt_geo[, .(X_spatial = mean(get(target_col), na.rm = TRUE)), by = ADM2]
    dt_geo[spatial_avg, X_spatial := i.X_spatial, on = "ADM2"]

    # --- c. Compute the final imputed value (dynamic alpha) ---
    # Only for rows where the target is NA, to save time
    dt_geo[is.na(get(target_col)), imputed_val := {
      alpha <- 0.5
      alpha <- fifelse(is.na(X_spatial), 1, alpha) # if the spatial value is missing, trust time
      alpha <- fifelse(is.na(X_temp), 0, alpha)    # if the temporal value is missing, trust space

      (alpha * X_temp) + ((1 - alpha) * X_spatial)
    }]

    # --- d. Fill the gap with the value ---
    dt_geo[is.na(get(target_col)), (target_col) := imputed_val]

    # Drop the scratch columns, ready for the next month
    dt_geo[, c("temp_lag", "temp_lead", "X_temp", "X_spatial", "imputed_val") := NULL]
  }
}

print(colSums(is.na(dt_geo)))

# ==========================================
# Safety Net: a 3-layer fallback (ADM2 -> ADM1 -> Global)
# ==========================================

# 1. Prepare the area codes
# Build the district code (4 digits) and province code (2 digits) from ADM3
dt_geo[, ADM2 := substr(ADM3, 1, 4)]
dt_geo[, ADM1 := substr(ADM3, 1, 2)]

# 2. Find columns that still contain NA
cols_with_na <- names(dt_geo)[colSums(is.na(dt_geo)) > 0]

# 3. Loop over only the columns that still have problems
for (col in cols_with_na) {

  # --- a. Compute the mean for each fallback layer ---
  # Layer 1: district-level mean (ADM2)
  dt_geo[, adm2_mean := mean(get(col), na.rm = TRUE), by = ADM2]
  # Layer 2: province-level mean (ADM1)
  dt_geo[, adm1_mean := mean(get(col), na.rm = TRUE), by = ADM1]
  # Layer 3: national mean (the whole table)
  global_mean <- mean(dt_geo[[col]], na.rm = TRUE)

  # --- b. Guard against NaN errors ---
  # If clouds cover a whole district or province, the mean comes out as NaN
  # We must convert NaN back to NA so fcoalesce keeps working
  dt_geo[is.nan(adm2_mean), adm2_mean := NA_real_]
  dt_geo[is.nan(adm1_mean), adm1_mean := NA_real_]
  if(is.nan(global_mean)) global_mean <- NA_real_

  # --- c. Apply the 3-layer fallback with fcoalesce ---
  dt_geo[, (col) := fcoalesce(
    get(col),        # original value (use it directly if present)
    adm2_mean,       # layer 1: fill with the district value
    adm1_mean,       # layer 2: fill with the province value
    global_mean      # layer 3: fill with the national value
  )]

  # Drop the scratch columns, ready for the next iteration
  dt_geo[, c("adm2_mean", "adm1_mean") := NULL]
}

# 4. Drop ADM1 and ADM2 to return the table to its original clean state
# (or delete this line if you want to keep them for later use)
dt_geo[, c("ADM1", "ADM2") := NULL]

print(colSums(is.na(dt_geo)))
#dt_geo[, Heat_Days := fifelse(Heat_Days %% 1 > 0.25, ceiling(Heat_Days), floor(Heat_Days))]
num_cols <- names(dt_geo)[sapply(dt_geo, is.numeric)]
dt_geo[, (num_cols) := lapply(.SD, round, digits = 4), .SDcols = num_cols]
fwrite(dt_geo, file = "geo2022.txt", sep = "|")


# 1. Build a list of file names
files <- c("geo2020.txt", "geo2021.txt", "geo2022.txt")

# 2. Read every file into a list with lapply, then combine them with rbindlist
dt_geo <- rbindlist(lapply(files, fread), use.names = TRUE, fill = TRUE)
fwrite(dt_geo, file = "geo3y20_22.txt", sep = "|")
