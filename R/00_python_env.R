# =============================================================================
#  00_python_env.R   --   bind reticulate to a Python that has TensorFlow,
#                         without requiring conda to be on PATH.
#  ---------------------------------------------------------------------------
#  Replaces this line, which appears in six of the older scripts:
#
#      use_condaenv("tf-gpu", required = TRUE)
#
#  That call fails with "Unable to find conda binary. Is Anaconda installed?"
#  on any machine where conda has not been added to PATH -- which includes a
#  double-clicked cmd window on a perfectly ordinary Anaconda install, and
#  every machine that is not the one this study was run on. The environment is
#  sitting right there on disk; the only thing missing is the launcher used to
#  find it. So find it on disk instead.
#
#      source("R/00_python_env.R")
#      bind_python("tf-gpu")     # name, or an explicit path to python.exe
#
#  Extracted from 12_Factorial7_config.R, where it was written first.
# =============================================================================

suppressPackageStartupMessages(library(reticulate))

conda_roots <- function() {
  cand <- c(
    file.path(Sys.getenv("USERPROFILE"),   c("anaconda3", "miniconda3",
                                             "miniforge3", "mambaforge")),
    file.path(Sys.getenv("LOCALAPPDATA"),  c("anaconda3", "miniconda3",
                                             "Continuum/anaconda3")),
    file.path(Sys.getenv("ProgramFiles"),  c("Anaconda3", "Miniconda3")),
    file.path("C:/ProgramData",            c("Anaconda3", "Miniconda3")),
    file.path(Sys.getenv("HOME"),          c("anaconda3", "miniconda3",
                                             "miniforge3", "mambaforge"))
  )
  cand[nzchar(cand) & dir.exists(cand)]
}

conda_envs <- function() {
  out <- data.frame(name = character(0), python = character(0),
                    has_tf = logical(0), stringsAsFactors = FALSE)
  for (root in conda_roots()) {
    pys <- c(file.path(root, c("python.exe", "bin/python")))
    pys <- pys[file.exists(pys)]
    if (length(pys)) out <- rbind(out, data.frame(
      name = "base", python = pys[1],
      has_tf = dir.exists(file.path(root, "Lib/site-packages/tensorflow")) ||
               length(Sys.glob(file.path(root, "lib/python*/site-packages/tensorflow"))) > 0,
      stringsAsFactors = FALSE))
    envdir <- file.path(root, "envs")
    if (!dir.exists(envdir)) next
    for (e in list.dirs(envdir, recursive = FALSE)) {
      pys <- c(file.path(e, c("python.exe", "bin/python")))
      pys <- pys[file.exists(pys)]
      if (!length(pys)) next
      out <- rbind(out, data.frame(
        name = basename(e), python = pys[1],
        has_tf = dir.exists(file.path(e, "Lib/site-packages/tensorflow")) ||
                 length(Sys.glob(file.path(e, "lib/python*/site-packages/tensorflow"))) > 0,
        stringsAsFactors = FALSE))
    }
  }
  out[!duplicated(out$python), ]
}

find_conda_python <- function(name) {
  if (is.null(name) || !nzchar(name)) return(NA_character_)
  if (grepl("[/\\\\]", name)) return(if (file.exists(name)) name else NA_character_)
  envs <- conda_envs()
  hit <- envs$python[envs$name == name]
  if (length(hit)) return(hit[1])
  NA_character_
}

bind_python <- function(name = "tf-gpu", required = TRUE) {
  path <- tryCatch(find_conda_python(name), error = function(e) NA_character_)
  if (!is.na(path)) {
    use_python(path, required = required)
  } else {
    # Last resort: let reticulate try the name as a conda env, which works when
    # conda IS on PATH, and report usefully when it is not.
    ok <- tryCatch({ use_condaenv(name, required = required); TRUE },
                   error = function(e) FALSE)
    if (!ok) {
      cat("Could not bind Python environment:", name, "\n")
      cat("Environments found on disk:\n")
      e <- conda_envs()
      if (nrow(e) == 0) cat("  (none)\n") else
        for (i in seq_len(nrow(e)))
          cat(sprintf("  %-16s %-60s tensorflow=%s\n", e$name[i], e$python[i],
                      ifelse(e$has_tf[i], "yes", "no")))
      stop("set the environment name to one of the above")
    }
  }
  invisible(py_config()$python)
}

report_gpu <- function() {
  gpus <- tensorflow::tf$config$list_physical_devices("GPU")
  if (length(gpus) > 0)
    tensorflow::tf$config$experimental$set_memory_growth(gpus[[1]], TRUE)
  cat(sprintf("GPUs visible: %d\n", length(gpus)))
  invisible(length(gpus))
}
