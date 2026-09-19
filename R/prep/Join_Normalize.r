library(data.table)
dt_fin <- fread("3_fin3y20_22.txt", sep = "|", encoding = "UTF-8")
setorder(dt_fin, Year, ID)
dt_geo <- fread("3_geo3y20_22.txt", sep = "|", encoding = "UTF-8")
setorder(dt_geo, Year, ADM3)
# Specify the column names to convert in .SDcols
cols_to_change <- c("Year", "ADM3")
# Use lapply to convert all the listed columns to character at once
dt_fin[, (cols_to_change) := lapply(.SD, as.character), .SDcols = cols_to_change]
dt_geo[, (cols_to_change) := lapply(.SD, as.character), .SDcols = cols_to_change]


# Set keys on the tables first so the join is faster
setkey(dt_fin, Year, ADM3)
setkey(dt_geo, Year, ADM3)

# Left join: attach dt_geo onto dt_fin
dt <- dt_geo[dt_fin, on = .(Year, ADM3)]
setorder(dt, Year, ID)
setcolorder(dt, c("Year", "ID"),)
#print(colSums(is.na(dt)))
fwrite(dt, file = "database_full.txt", sep = "|") #full data before transfroming


####Feature Preprocessing and Scaling##########
dt <- fread("database_full.txt", sep = "|", encoding = "UTF-8")
# =========================================================================
# High-Performance Data Preprocessing Pipeline (data.table)
# For 3-Year Panel Data with Monthly Spatio-Temporal Variables
# =========================================================================
#library(data.table)
# Build an index for the training set (years 1 and 2) to prevent data leakage
train_idx <- which(dt$Year %in% c(1, 2))

# =========================================================================
# STEP 1: Define feature groups
# =========================================================================

# 1.1 Group that needs a log transform (heavily right-skewed)
log_vars <- c("Depb", "Dep", "CLb", "CL", "Outb", "Out", "Int", "AreaR",
              "Area", "eCostrai", "eCost", "eYierai", "eYie", "ePrcton",
              "eInc", "Debt_per_Rai")

# 1.2 Group that needs winsorizing (ratios prone to severe outliers)
win_vars <- c("Proxy_DSR", "Liquidity_Buffer", "Bes", "Repayment_Rate",
              "Debt_to_Income", "Est_DSCR10", "Est_DSCR20",
              "Credit_Utilization_Rate", "Debt_Reduction",
              "Debt_Momentum", "Saving_Growth", "Saving_Momentum",
              "Profitability_Buffer", "Area_Utilization_Rate")

# 1.3 Standard min-max group (single variables not stored monthly)
raw_norm_vars <- c("nLC", "nIS", "nP", "nRV", "CD")

# 1.4 Monthly time-series group (May - December)
ndvi_cols   <- paste0("NDVI", 5:12)          # greenness (global min-max)
ndwi_cols   <- paste0("NDWI", 5:12)          # moisture (global min-max)
lst_cols    <- paste0("LST", 5:12)           # land surface temperature (global min-max)
precip_cols <- paste0("Precipitation", 5:12) # rainfall (global min-max)
smap_cols   <- paste0("SMAP", 5:12)
ntl_cols    <- paste0("NTL", 5:12)           # night-time lights (log transform)
SAI_NDVI_cols         <- paste0("SAI_NDVI", 5:12)
VHI_cols              <- paste0("VHI", 5:12)
SAI_NDWI_cols         <- paste0("SAI_NDWI", 5:12)
Rainfall_Deficit_cols <- paste0("Rainfall_Deficit", 5:12)
Heat_Stress_Days_cols <- paste0("Heat_Stress_Days", 5:12)
# =========================================================================
# STEP 2: Logarithmic Transformation [ log1p(x) ]
# Can be applied to all data since the formula does not depend on group statistics
# =========================================================================

# 2.1 Log-transform the financial and physical variables
log_new_names <- paste0("log_", log_vars)
dt[, (log_new_names) := lapply(.SD, log1p), .SDcols = log_vars]

# 2.2 Log-transform the monthly NTL variables (NTL is always right-skewed)
ntl_new_names <- paste0("log_", ntl_cols)
dt[, (ntl_new_names) := lapply(.SD, log1p), .SDcols = ntl_cols]
log_ntl_cols    <- paste0("log_NTL", 5:12)


# =========================================================================
# STEP 3: Winsorization (clip the 1% and 99% tails)
# P1 and P99 must be taken from the train set only!
# =========================================================================
win_new_names <- paste0("win_", win_vars)

for (i in seq_along(win_vars)) {
  col <- win_vars[i]
  new_col <- win_new_names[i]

  # Compute the bounds from the train set (years 1 & 2)
  bounds <- quantile(dt[[col]][train_idx], probs = c(0.01, 0.99), na.rm = TRUE)
  p1 <- bounds[1]
  p99 <- bounds[2]

  # Apply capping to the whole table
  dt[, (new_col) := pmax(pmin(get(col), p99), p1)]
}


# =========================================================================
# STEP 4: Standard Min-Max Normalization [0, 1]
# For single variables and financial variables (already log/winsorized)
# =========================================================================
# Gather all single variables that will feed the neural network
all_single_vars <- c(log_new_names, win_new_names, raw_norm_vars)
norm_new_names <- paste0("norm_", all_single_vars)

for (i in seq_along(all_single_vars)) {
  col <- all_single_vars[i]
  new_col <- norm_new_names[i]

  # Take min/max from the train set (years 1 & 2)
  c_min <- min(dt[[col]][train_idx], na.rm = TRUE)
  c_max <- max(dt[[col]][train_idx], na.rm = TRUE)

  # Scale the data (+ 1e-8 to avoid division by zero)
  dt[, (new_col) := (get(col) - c_min) / (c_max - c_min + 1e-8)]
}


# =========================================================================
# STEP 5: Global Min-Max Normalization (Time-Series)
# For monthly variables, to preserve the "seasonal shape"
# =========================================================================

# Helper function for global scaling
apply_global_minmax <- function(dt, cols, prefix) {
  new_cols <- paste0(prefix, cols)

  # 5.1 Find the absolute min/max across *all months* combined, train set only
  # as.matrix makes finding min/max over many columns at once very fast
  global_min <- min(as.matrix(dt[train_idx, ..cols]), na.rm = TRUE)
  global_max <- max(as.matrix(dt[train_idx, ..cols]), na.rm = TRUE)

  # 5.2 Scale every monthly column with the same global parameters
  dt[, (new_cols) := lapply(.SD, function(x) {
    (x - global_min) / (global_max - global_min + 1e-8)
  }), .SDcols = cols]
}

# Run the function on the monthly satellite variable groups (NDVI, NDWI, LST, Precip)
apply_global_minmax(dt, ndvi_cols, "norm_")
apply_global_minmax(dt, ndwi_cols, "norm_")
apply_global_minmax(dt, lst_cols, "norm_")
apply_global_minmax(dt, precip_cols, "norm_")
apply_global_minmax(dt, smap_cols, "norm_")
apply_global_minmax(dt, log_ntl_cols, "norm_")
apply_global_minmax(dt, SAI_NDVI_cols, "norm_")
apply_global_minmax(dt, VHI_cols, "norm_")
apply_global_minmax(dt, SAI_NDWI_cols, "norm_")
apply_global_minmax(dt, Rainfall_Deficit_cols, "norm_")
apply_global_minmax(dt, Heat_Stress_Days_cols, "norm_")

# =========================================================================
### Categorical Feature Engineering & Embedding
# =========================================================================

# =========================================================================
# 1. Dummy Encoding for "IDRV" (rice variety)
# =========================================================================
# Set the reference category to drop, to avoid the dummy variable trap
# (this reference category is absorbed into the model baseline automatically)
ref_category <- 1

# Get all rice varieties, drop missing values (NA), and exclude the reference category
unique_idrv <- na.omit(unique(dt$IDRV))
other_varieties <- setdiff(unique_idrv, ref_category)

# Loop to quickly create new binary (0/1) integer columns
for (variety in other_varieties) {
  col_name <- paste0("IDRV_", variety)

  # Use fifelse (fast ifelse) with 1L, 0L (L = integer type)
  # for maximum speed and lower memory (RAM) use
  dt[, (col_name) := fifelse(IDRV == variety, 1L, 0L)]
}
# Drop the original IDRV column (if desired)
dt[, IDRV := NULL]
print("--- After dummy encoding ---")
print(dt[, .SD, .SDcols = patterns("ID|IDRV")]) #check DONE

# =========================================================================
# 2. Cyclical Encoding (Sine/Cosine) for the month variables (MP, MH)
# =========================================================================
# Reason: the model would not know that month 12 (December) is adjacent to month 1 (January)
# Trigonometric functions map the months onto a circle so months 12 and 1 sit close together

dt[, `:=`(
  MP_sin = sin(2 * pi * MP / 12),
  MP_cos = cos(2 * pi * MP / 12),
   MH_sin = sin(2 * pi * MH / 12),
  MH_cos = cos(2 * pi * MH / 12)
)]

# =========================================================================
# 3. Target Encoding with Smoothing for spatial variables (province, subdistrict)
# =========================================================================

# Define train_idx for years 1 and 2 to prevent data leakage
train_idx <- which(dt$Year %in% c(1, 2))

# The averages must be learned from the train set only (prevents data leakage)
target_cols <- c("ADM3", "IDProv_RL", "ADM3RL", "IDProv_rice", "IDDT")

# Compute the global mean of Default from the train set
global_mean <- mean(dt$Y[train_idx], na.rm = TRUE)

# Set the smoothing weight (m)
# Higher values pull subdistricts with few borrowers toward the national mean, preventing overfitting
m_weight <- 20

for(col in target_cols) {
  new_te_col <- paste0("TE_", col)

  # 3.1 Build a stats table (count and mean) by area **from the train set only**
  stats <- dt[train_idx, .(
    n = .N,
    cat_mean = mean(Y, na.rm = TRUE)
  ), by = col]

  # 3.2 Compute the smoothed target encoding by the formula:
  # (n * mean_cat + m * global_mean) / (n + m)
  stats[, TE_val := (n * cat_mean + m_weight * global_mean) / (n + m_weight)]

  # 3.3 Join the learned values back onto the full data (including year 3) by reference
  dt[stats, (new_te_col) := i.TE_val, on = col]

  # 3.4 Handle "new subdistricts/provinces" that may appear only in year 3 (unseen categories)
  # by filling NA with the global mean
  dt[is.na(get(new_te_col)), (new_te_col) := global_mean]
}

print("--- After target encoding with smoothing ---")
print(dt[, .SD, .SDcols = patterns("Year|ADM3|TargetEnc")])
num_cols <- names(dt)[sapply(dt, is.numeric)]
dt[, (num_cols) := lapply(.SD, round, digits = 4), .SDcols = num_cols]
fwrite(dt, file = "database_transform.txt", sep = "|")
dt <- fread("5_database_transform.txt", sep = "|", encoding = "UTF-8")


train_feature <- c("Year", "ID", "ADM3", "Has_Credit_History", "Previous_Default", "Y",
                   "norm_log_Depb", "norm_log_Dep", "norm_log_CLb", "norm_log_CL", "norm_log_Outb", "norm_log_Out", "norm_log_Int",
                   "norm_log_AreaR", "norm_log_Area", "norm_log_eCostrai", "norm_log_eCost", "norm_log_eYierai", "norm_log_eYie",
                   "norm_log_ePrcton", "norm_log_eInc", "norm_log_Debt_per_Rai",
                   "norm_win_Proxy_DSR", "norm_win_Liquidity_Buffer", "norm_win_Bes", "norm_win_Repayment_Rate",
                   "norm_win_Debt_to_Income", "norm_win_Est_DSCR10", "norm_win_Est_DSCR20", "norm_win_Credit_Utilization_Rate",
                   "norm_win_Debt_Reduction", "norm_win_Debt_Momentum", "norm_win_Saving_Growth", "norm_win_Saving_Momentum",
                   "norm_win_Profitability_Buffer", "norm_win_Area_Utilization_Rate", "norm_nLC", "norm_nIS", "norm_nP", "norm_nRV", "norm_CD",
                   "norm_NDVI5", "norm_NDVI6", "norm_NDVI7", "norm_NDVI8", "norm_NDVI9", "norm_NDVI10", "norm_NDVI11", "norm_NDVI12",
                   "norm_NDWI5", "norm_NDWI6", "norm_NDWI7", "norm_NDWI8", "norm_NDWI9", "norm_NDWI10", "norm_NDWI11", "norm_NDWI12",
                   "norm_LST5", "norm_LST6", "norm_LST7", "norm_LST8", "norm_LST9", "norm_LST10", "norm_LST11", "norm_LST12",
                   "norm_Precipitation5", "norm_Precipitation6", "norm_Precipitation7", "norm_Precipitation8", "norm_Precipitation9",
                   "norm_Precipitation10", "norm_Precipitation11", "norm_Precipitation12",
                   "norm_SMAP5", "norm_SMAP6", "norm_SMAP7", "norm_SMAP8", "norm_SMAP9", "norm_SMAP10", "norm_SMAP11", "norm_SMAP12",
                   "norm_log_NTL5", "norm_log_NTL6", "norm_log_NTL7", "norm_log_NTL8", "norm_log_NTL9", "norm_log_NTL10", "norm_log_NTL11", "norm_log_NTL12",
                   "norm_SAI_NDVI5", "norm_SAI_NDVI6", "norm_SAI_NDVI7", "norm_SAI_NDVI8", "norm_SAI_NDVI9", "norm_SAI_NDVI10", "norm_SAI_NDVI11", "norm_SAI_NDVI12",
                   "norm_VHI5", "norm_VHI6", "norm_VHI7","norm_VHI8", "norm_VHI9", "norm_VHI10", "norm_VHI11", "norm_VHI12",
                   "norm_SAI_NDWI5", "norm_SAI_NDWI6", "norm_SAI_NDWI7","norm_SAI_NDWI8", "norm_SAI_NDWI9", "norm_SAI_NDWI10", "norm_SAI_NDWI11", "norm_SAI_NDWI12",
                   "norm_Rainfall_Deficit5", "norm_Rainfall_Deficit6", "norm_Rainfall_Deficit7", "norm_Rainfall_Deficit8", "norm_Rainfall_Deficit9", "norm_Rainfall_Deficit10", "norm_Rainfall_Deficit11", "norm_Rainfall_Deficit12",
                   "norm_Heat_Stress_Days5","norm_Heat_Stress_Days6", "norm_Heat_Stress_Days7","norm_Heat_Stress_Days8", "norm_Heat_Stress_Days9", "norm_Heat_Stress_Days10", "norm_Heat_Stress_Days11", "norm_Heat_Stress_Days12",
                   "IDRV_5", "IDRV_2", "IDRV_4", "IDRV_3", "MP_sin", "MP_cos", "MH_sin", "MH_cos",
                   "TE_ADM3", "TE_IDProv_RL", "TE_ADM3RL", "TE_IDProv_rice", "TE_IDDT")

train_feature_mlp <- c("Year", "ID", "ADM3", "Has_Credit_History", "Previous_Default", "Y",
                   "norm_log_Depb", "norm_log_Dep", "norm_log_CLb", "norm_log_CL", "norm_log_Outb", "norm_log_Out", "norm_log_Int",
                   "norm_log_AreaR", "norm_log_Area", "norm_log_eCostrai", "norm_log_eCost", "norm_log_eYierai", "norm_log_eYie",
                   "norm_log_ePrcton", "norm_log_eInc", "norm_log_Debt_per_Rai",
                   "norm_win_Proxy_DSR", "norm_win_Liquidity_Buffer", "norm_win_Bes", "norm_win_Repayment_Rate",
                   "norm_win_Debt_to_Income", "norm_win_Est_DSCR10", "norm_win_Est_DSCR20", "norm_win_Credit_Utilization_Rate",
                   "norm_win_Debt_Reduction", "norm_win_Debt_Momentum", "norm_win_Saving_Growth", "norm_win_Saving_Momentum",
                   "norm_win_Profitability_Buffer", "norm_win_Area_Utilization_Rate", "norm_nLC", "norm_nIS", "norm_nP", "norm_nRV", "norm_CD",
                   "norm_NDVI5", "norm_NDVI6", "norm_NDVI7", "norm_NDVI8", "norm_NDVI9", "norm_NDVI10", "norm_NDVI11", "norm_NDVI12",
                   "norm_NDWI5", "norm_NDWI6", "norm_NDWI7", "norm_NDWI8", "norm_NDWI9", "norm_NDWI10", "norm_NDWI11", "norm_NDWI12",
                   "norm_LST5", "norm_LST6", "norm_LST7", "norm_LST8", "norm_LST9", "norm_LST10", "norm_LST11", "norm_LST12",
                   "norm_Precipitation5", "norm_Precipitation6", "norm_Precipitation7", "norm_Precipitation8", "norm_Precipitation9",
                   "norm_Precipitation10", "norm_Precipitation11", "norm_Precipitation12",
                   "norm_SMAP5", "norm_SMAP6", "norm_SMAP7", "norm_SMAP8", "norm_SMAP9", "norm_SMAP10", "norm_SMAP11", "norm_SMAP12",
                   "norm_log_NTL5", "norm_log_NTL6", "norm_log_NTL7", "norm_log_NTL8", "norm_log_NTL9", "norm_log_NTL10", "norm_log_NTL11", "norm_log_NTL12",
                   "norm_SAI_NDVI5", "norm_SAI_NDVI6", "norm_SAI_NDVI7", "norm_SAI_NDVI8", "norm_SAI_NDVI9", "norm_SAI_NDVI10", "norm_SAI_NDVI11", "norm_SAI_NDVI12",
                   "norm_VHI5", "norm_VHI6", "norm_VHI7","norm_VHI8", "norm_VHI9", "norm_VHI10", "norm_VHI11", "norm_VHI12",
                   "norm_SAI_NDWI5", "norm_SAI_NDWI6", "norm_SAI_NDWI7","norm_SAI_NDWI8", "norm_SAI_NDWI9", "norm_SAI_NDWI10", "norm_SAI_NDWI11", "norm_SAI_NDWI12",
                   "norm_Rainfall_Deficit5", "norm_Rainfall_Deficit6", "norm_Rainfall_Deficit7", "norm_Rainfall_Deficit8", "norm_Rainfall_Deficit9", "norm_Rainfall_Deficit10", "norm_Rainfall_Deficit11", "norm_Rainfall_Deficit12",
                   "norm_Heat_Stress_Days5","norm_Heat_Stress_Days6", "norm_Heat_Stress_Days7","norm_Heat_Stress_Days8", "norm_Heat_Stress_Days9", "norm_Heat_Stress_Days10", "norm_Heat_Stress_Days11", "norm_Heat_Stress_Days12",
                   "IDRV_5", "IDRV_2", "IDRV_4", "IDRV_3", "MP_sin", "MP_cos", "MH_sin", "MH_cos",
                   "TE_ADM3", "TE_IDProv_RL", "TE_ADM3RL", "TE_IDProv_rice", "TE_IDDT")

train_dt <- dt[, ..train_feature]
num_cols <- names(train_dt)[sapply(train_dt, is.numeric)]
train_dt[, (num_cols) := lapply(.SD, round, digits = 4), .SDcols = num_cols]

fwrite(train_dt, file = "train_database.txt", sep = "|")

# =========================================================================
# 4. Entity Embedding Preparation for the Neural Network (LSTM/Dense)
# =========================================================================
# Keras / TensorFlow needs contiguous indices (1, 2, 3, ..., V) for the embedding layer
# We build new purely-numeric ID columns for the spatial variables

# =========================================================================
# 4. Entity Embedding Preparation for the Neural Network (LSTM/Dense)
# =========================================================================
# Columns to prepare for entity embedding
emb_cols <- c("IDProv_RL", "IDProv_rice", "IDDT", "ADM3RL", "ADM3")

for(col in emb_cols) {
  new_emb_col <- paste0("emb_idx_", col)

  # 1. Get the unique categories **from the train set (years 1-2) only**
  # to stop the model from knowing year-3 subdistricts in advance
  unique_vals <- na.omit(unique(df[[col]][train_idx]))

  # 2. Build the mapping dictionary table (index starts at 1)
  # (in Keras, index 0 is usually reserved for NA/unknown)
  mapping <- data.table(
    original_val = unique_vals,
    idx = seq_along(unique_vals)
  )

  # Rename the column to match the real column name for the join
  setnames(mapping, "original_val", col)

  # 3. Map the indices back onto the full data (including year 3)
  df[mapping, (new_emb_col) := i.idx, on = col]

  # 4. Fill 0 for:
  #    - data that was NA from the start
  #    - "new subdistricts/provinces" in year 3 that are absent from the years 1-2 mapping
  df[is.na(get(new_emb_col)), (new_emb_col) := 0L]
}

# Summary: emb_idx_xxx ranges from 0 (unknown/NA) up to V (number of subdistricts in the train set)
# ready to feed into layer_embedding() in R Keras


feature_vector <- c(
  "Year", "ID", "ADM3", "NDVI5", "NDVI6", "NDVI7", "NDVI8", "NDVI9", "NDVI10", "NDVI11", "NDVI12",
  "NDWI5", "NDWI6", "NDWI7", "NDWI8", "NDWI9", "NDWI10", "NDWI11", "NDWI12",
  "LST5", "LST6", "LST7", "LST8", "LST9", "LST10", "LST11", "LST12",
  "Precipitation5", "Precipitation6", "Precipitation7", "Precipitation8", "Precipitation9", "Precipitation10", "Precipitation11", "Precipitation12",
  "SMAP5", "SMAP6", "SMAP7", "SMAP8", "SMAP9", "SMAP10", "SMAP11", "SMAP12",
  "NTL5", "NTL6", "NTL7", "NTL8", "NTL9", "NTL10", "NTL11", "NTL12",
  "SAI_NDVI8", "SAI_NDVI9", "SAI_NDVI10", "SAI_NDVI11",
  "VHI8", "VHI9", "VHI10", "VHI11",
  "SAI_NDWI8", "SAI_NDWI9", "SAI_NDWI10", "SAI_NDWI11",
  "Rainfall_Deficit8", "Rainfall_Deficit9", "Rainfall_Deficit10", "Rainfall_Deficit11",
  "Heat_Stress_Days8", "Heat_Stress_Days9", "Heat_Stress_Days10", "Heat_Stress_Days11",
  "IDProv_RL", "ADM3RL", "Depb", "Dep", "nLC", "nIS", "CLb", "CL", "Outb", "Out", "Int",
  "IDProv_rice", "nP", "IDDT", "AreaR", "Area", "nRV", "IDRV", "MP", "MH", "CD",
  "eCostrai", "eCost", "eYierai", "eYie", "ePrcton", "eInc",
  "Has_Credit_History", "Previous_Default", "Y", "Proxy_DSR", "Liquidity_Buffer", "Bes",
  "Repayment_Rate", "Debt_to_Income", "Est_DSCR10", "Est_DSCR20", "Debt_per_Rai",
  "Credit_Utilization_Rate", "Debt_Reduction", "Debt_Momentum", "Saving_Growth",
  "Saving_Momentum", "Profitability_Buffer",
  "log_Depb", "log_Dep", "log_CLb", "log_CL", "log_Outb", "log_Out", "log_Int",
  "log_AreaR", "log_Area", "log_eCostrai", "log_eCost", "log_eYierai", "log_eYie", "log_ePrcton", "log_eInc",
  "log_Debt_per_Rai", "log_NTL5", "log_NTL6", "log_NTL7", "log_NTL8", "log_NTL9", "log_NTL10", "log_NTL11", "log_NTL12",
  "win_Proxy_DSR", "win_Liquidity_Buffer", "win_Bes", "win_Repayment_Rate", "win_Debt_to_Income",
  "win_Est_DSCR10", "win_Est_DSCR20", "win_Credit_Utilization_Rate", "win_Debt_Reduction",
  "win_Debt_Momentum", "win_Saving_Growth", "win_Saving_Momentum", "win_Profitability_Buffer",
  "norm_log_Depb", "norm_log_Dep", "norm_log_CLb", "norm_log_CL", "norm_log_Outb", "norm_log_Out", "norm_log_Int",
  "norm_log_AreaR", "norm_log_Area", "norm_log_eCostrai", "norm_log_eCost", "norm_log_eYierai", "norm_log_eYie",
  "norm_log_ePrcton", "norm_log_eInc", "norm_log_Debt_per_Rai",
  "norm_win_Proxy_DSR", "norm_win_Liquidity_Buffer", "norm_win_Bes", "norm_win_Repayment_Rate",
  "norm_win_Debt_to_Income", "norm_win_Est_DSCR10", "norm_win_Est_DSCR20", "norm_win_Credit_Utilization_Rate",
  "norm_win_Debt_Reduction", "norm_win_Debt_Momentum", "norm_win_Saving_Growth", "norm_win_Saving_Momentum",
  "norm_win_Profitability_Buffer", "norm_nLC", "norm_nIS", "norm_nP", "norm_nRV", "norm_CD",
  "norm_NDVI5", "norm_NDVI6", "norm_NDVI7", "norm_NDVI8", "norm_NDVI9", "norm_NDVI10", "norm_NDVI11", "norm_NDVI12",
  "norm_NDWI5", "norm_NDWI6", "norm_NDWI7", "norm_NDWI8", "norm_NDWI9", "norm_NDWI10", "norm_NDWI11", "norm_NDWI12",
  "norm_LST5", "norm_LST6", "norm_LST7", "norm_LST8", "norm_LST9", "norm_LST10", "norm_LST11", "norm_LST12",
  "norm_Precipitation5", "norm_Precipitation6", "norm_Precipitation7", "norm_Precipitation8", "norm_Precipitation9",
  "norm_Precipitation10", "norm_Precipitation11", "norm_Precipitation12",
  "norm_SMAP5", "norm_SMAP6", "norm_SMAP7", "norm_SMAP8", "norm_SMAP9", "norm_SMAP10", "norm_SMAP11", "norm_SMAP12",
  "norm_log_NTL5", "norm_log_NTL6", "norm_log_NTL7", "norm_log_NTL8", "norm_log_NTL9", "norm_log_NTL10", "norm_log_NTL11", "norm_log_NTL12",
  "norm_SAI_NDVI8", "norm_SAI_NDVI9", "norm_SAI_NDVI10", "norm_SAI_NDVI11",
  "norm_VHI8", "norm_VHI9", "norm_VHI10", "norm_VHI11",
  "norm_SAI_NDWI8", "norm_SAI_NDWI9", "norm_SAI_NDWI10", "norm_SAI_NDWI11",
  "norm_Rainfall_Deficit8", "norm_Rainfall_Deficit9", "norm_Rainfall_Deficit10", "norm_Rainfall_Deficit11",
  "norm_Heat_Stress_Days8", "norm_Heat_Stress_Days9", "norm_Heat_Stress_Days10", "norm_Heat_Stress_Days11",
  "IDRV_5", "IDRV_2", "IDRV_4", "IDRV_3", "MP_sin", "MP_cos", "MH_sin", "MH_cos",
  "TE_ADM3", "TE_IDProv_RL", "TE_ADM3RL", "TE_IDProv_rice", "TE_IDDT"
)

num_cols <- names(dt)[sapply(dt, is.numeric)]
dt[, (num_cols) := lapply(.SD, round, digits = 4), .SDcols = num_cols]
fwrite(dt, file = "full_database.txt", sep = "|")
