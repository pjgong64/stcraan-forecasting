options(scipen = 999)
library(readr)
library(data.table)

# 1. Build a list of file names
files <- c("fin2/2020v.txt", "fin2/2021v.txt", "fin2/2022v.txt")

# 2. Read every file into a list with lapply, then combine them with rbindlist
dt <- rbindlist(lapply(files, fread), use.names = TRUE, fill = TRUE)
dt[, DF := NULL]
#fwrite(dt, file="data_before_out.txt", sep = "|")
# 1. Define the group of columns to strip outliers from
#target_cols <- c("Depb", "Dep", "CLb", "CL", "Outb", "Out", "AreaR", "Area",
                 #"eCostrai", "eCost", "eYierai", "eYie", "ePrcton", "eInc")
target_cols <- c("Depb", "Dep", "CLb", "CL", "Outb", "Out", "AreaR")
#sum_dt <- data.table(summary(dt[, ..target_cols]))
fwrite(sum_dt, file="summary_before_out.csv")

# ==========================================
# Outlier Treatment
# 1. Create an IQR capping function
# ==========================================
cap_iqr <- function(x) {
  # Skip the calculation if the values are all NA
  if (all(is.na(x))) return(x)

  # Compute Q1 and Q3 (ignoring NA values)
  qnt <- quantile(x, probs = c(0.25, 0.75), na.rm = TRUE)
  Q1 <- qnt[1]
  Q3 <- qnt[2]

  # Compute the IQR
  IQR_val <- Q3 - Q1

  # Define the lower and upper thresholds
  lower_bound <- Q1 - 1.5 * IQR_val
  upper_bound <- Q3 + 1.5 * IQR_val

  # Cap the values that fall outside the bounds
  # pmax raises values below lower_bound up to lower_bound
  # pmin lowers values above upper_bound down to upper_bound
  x_capped <- pmax(x, lower_bound, na.rm = FALSE)
  x_capped <- pmin(x_capped, upper_bound, na.rm = FALSE)

  return(x_capped)
}

# ==========================================
# 2. Apply the function to your data table
# ==========================================
# Assume your table is named combined_data

# Define the column names you want to apply outlier treatment to
# (these are agricultural variables such as cost, yield, and income)
target_cols <- c("Depb", "Dep", "CLb", "CL", "Outb", "Out", "AreaR", "Area",
                 "eCostrai", "eCost", "eYierai", "eYie", "ePrcton", "eInc")
# Update the original columns in place (fast and memory efficient)
combined_data <- dt[, (target_cols) := lapply(.SD, cap_iqr), .SDcols = target_cols]
fwrite(combined_data, file="data_after_out.txt", sep = "|")
# Check the result (inspect min/max to confirm the capping worked)
dt_sum <- data.table(summary(combined_data[, ..target_cols]))
fwrite(dt_sum, file="summary_after_out.csv")


dt <- fread("data_after_out.txt", sep = "|", encoding = "UTF-8")
#dt <- fread("vfinal/dataset20_22V3.txt", sep = "|", encoding = "UTF-8")
print(colSums(dt == 0, na.rm = TRUE))
#### Derived Financial Features
dt[, Proxy_DSR := Out/(((eYie*Area)/1000)*ePrcton)]
dt[, Liquidity_Buffer := (1-(Out/CL))]
dt[, Bes := (eInc-(eCost+Out))/eInc]
dt[, Repayment_Rate := (Outb-Out)/Outb]
dt[, Debt_to_Income := Out / eInc]
dt[, Est_DSCR10 := eInc/((0.1*Out)+(Out*Int/100))]
dt[, Est_DSCR20 := eInc/((0.2*Out)+(Out*Int/100))]
dt[, Debt_per_Rai := Out/Area]
dt[, Credit_Utilization_Rate := Out/CL]


setorder(dt, ID, Year)
# Mechanism: previous-year debt (shift lag) minus current-year debt (Out), computed per person (by = ID)
dt[, Debt_Reduction := shift(Outb, n = 1, type = "lag") - Out, by = ID]
# (the lag for year 1 is NA because there is no year 0, so we use that directly as a condition)
dt[Year == 1 | is.na(Debt_Reduction), Debt_Reduction := -1]
print(head(dt[, .(ID, Year, Out, Debt_Reduction)], 10))

dt[, Debt_Momentum := (Out - shift(Outb, n = 1, type = "lag"))/shift(Outb, n = 1, type = "lag") , by = ID]
dt[Year == 1 | is.na(Debt_Momentum), Debt_Momentum := -1]
print(head(dt[, .(ID, Year, Out, Debt_Momentum)], 10))


dt[, Saving_Growth := Dep - shift(Depb, n = 1, type = "lag"), by = ID]
dt[Year == 1 | is.na(Saving_Growth), Saving_Growth := -1]

dt[, Saving_Momentum := (Dep - shift(Depb, n = 1, type = "lag")) / shift(Depb, n = 1, type = "lag"), by = ID]
dt[Year == 1 | is.na(Saving_Momentum), Saving_Momentum := -1]

dt[, Profitability_Buffer := (eInc-eCost)/Out]
dt[, Area_Utilization_Rate:= Area/AreaR]

print(colSums(is.na(dt)))
num_cols <- names(dt)[sapply(dt, is.numeric)]
print(colSums(dt[, .SD, .SDcols = num_cols] == 0, na.rm = TRUE))
print(colSums(sapply(dt[, .SD, .SDcols = num_cols], is.infinite)))

#====================================
#Inf Imputation
#====================================
num_cols <- names(dt)[sapply(dt, is.numeric)]

for (col in num_cols) {
  # First check whether this column hides any Inf (to save computation time)
  if (any(is.infinite(dt[[col]]))) {
    # Find the max and min of that column
    c_max <- max(dt[is.finite(get(col)), get(col)], na.rm = TRUE)
    c_min <- min(dt[is.finite(get(col)), get(col)], na.rm = TRUE)
    # Replace Inf with c_max
    dt[is.infinite(get(col)) & get(col) > 0, (col) := c_max]
    # Replace -Inf with c_min
    dt[is.infinite(get(col)) & get(col) < 0, (col) := c_min]
  }
}


#====================================
#NA Imputation
#====================================
# ---------------------------------------------------------
# Group 1: replace NA with 0
# ---------------------------------------------------------
cols_zero <- c("Liquidity_Buffer", "Credit_Utilization_Rate", "Repayment_Rate", "Debt_to_Income",
              "Proxy_DSR")

for (col in cols_zero) {
  # If this column exists in the table, replace its NA values with 0
  if (col %in% names(dt)) {
    dt[is.na(get(col)), (col) := 0]
  }
}

# ---------------------------------------------------------
# Group 2: replace NA with the column's max value
# ---------------------------------------------------------
cols_max <- c("Est_DSCR10", "Est_DSCR20")

for (col in cols_max) {
  if (col %in% names(dt)) {
    # Find the max (excluding NA and Inf)
    c_max <- max(dt[is.finite(get(col)), get(col)], na.rm = TRUE)

    # Replace NA with the max value
    dt[is.na(get(col)), (col) := c_max]
  }
}

print(colSums(is.na(dt)))
print(colSums(dt[, .SD, .SDcols = num_cols] == 0, na.rm = TRUE))
print(colSums(sapply(dt[, .SD, .SDcols = num_cols], is.infinite)))
num_cols <- names(dt)[sapply(dt, is.numeric)]
dt[, (num_cols) := lapply(.SD, round, digits = 4), .SDcols = num_cols]


fwrite(dt, file = "fin3y20_22.txt", sep = "|")

