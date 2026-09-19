# Recording the environment

## What these two files are, and why anyone wants them

A reader who clones this repository has R and Python, but not *your* R and
Python. They have different versions of `data.table`, a different TensorFlow, a
different xgboost. Code that ran here can behave differently there, and when it
does, nobody can tell whether the difference is the finding or the software.

Two files fix that. Each is a plain text list of every package installed on the
machine that ran the study, with its exact version number:

| File | Covers | Roughly |
|---|---|---|
| `renv.lock` | the R side | "data.table 1.15.4, pROC 1.18.5, xgboost 1.7.8.1, …" |
| `environment.yml` | the Python side that Keras and TensorFlow use | "python 3.10.13, tensorflow 2.10.1, numpy 1.26.4, …" |

You do not write them by hand. Each is produced by one command that inspects
what is already installed and writes the list out. Neither installs anything,
neither changes your setup, and neither can be produced anywhere but on the
machine that ran the study — which is why this is a job only you can do.

---

## Part 1 — `renv.lock`, in RStudio

**Step 1.** Open RStudio.

**Step 2.** Point it at the repository folder:
`Session` → `Set Working Directory` → `Choose Directory…` → select your repo
folder (the one containing `README.md`).

**Step 3.** In the Console, type this and press Enter. It installs the tool that
writes the file. Wait for it to finish.

```r
install.packages("renv")
```

**Step 4.** Type this and press Enter:

```r
renv::init(bare = TRUE)
```

It may say it will restart R. Answer **yes**. It creates a small `renv/` folder
and a `.Rprofile`; it does **not** reinstall your packages — that is what
`bare = TRUE` prevents, and it matters, because a plain `renv::init()` tries to
rebuild your library from scratch and can leave you with a different TensorFlow
than the one that works.

**Step 5.** Type this and press Enter:

```r
renv::snapshot(type = "all")
```

It prints the list of packages it is about to record and asks
`Do you want to proceed? [y/N]:` — type **y** and press Enter.

**Step 6.** Look in the repo folder. `renv.lock` is now there. Open it in any
text editor if you want to see what it looks like; it is readable JSON.

`type = "all"` records the whole library rather than only the packages renv can
see being called by name. Use it here: several packages are reached indirectly
through reticulate and h2o, and the default scan misses them.

**Step 7 — check that it actually recorded your packages.** This is not
optional, because the most common failure is silent. In the Console:

```r
length(jsonlite::fromJSON("renv.lock")$Packages)
"data.table" %in% names(jsonlite::fromJSON("renv.lock")$Packages)
```

You should see a number in the low hundreds and `TRUE`.

If you see about **16** and `FALSE`, the lock file recorded only R's own base
and recommended packages. That happens because `renv::init()` creates a fresh
private library for the project, and the snapshot then describes that empty
library rather than the one your analysis actually uses. Point it at your real
library instead:

```r
renv::deactivate()     # leave the project library
.libPaths()            # confirm this now shows your usual library
renv::snapshot(library = .libPaths(), lockfile = "renv.lock",
               type = "all", force = TRUE)
```

Then run the two checks again. If it still comes back short, use the fallback
inventory further down — it is honest and it works.

---

## Part 2 — `environment.yml`, in Anaconda Prompt

**Step 1.** Open the Start menu, type `Anaconda Prompt`, open it. A black
terminal window appears. Do **not** activate the environment — leave it at
`(base)`.

**Step 2.** Change to the repository folder. If it is on a different drive from
the one shown, add `/d`:

```
cd /d C:\Users\AdmiN\Desktop\stcraan-forecasting
```

**Step 3.** Type this one line and press Enter:

```
conda env export -n tf-gpu --no-builds > environment.yml
```

Nothing visible happens — that is correct, the output went into the file. It
takes a few seconds.

**Step 4.** Open `environment.yml` in Notepad. Scroll to the very bottom. Delete
the last line, which looks like:

```
prefix: C:\Users\AdmiN\anaconda3\envs\tf-gpu
```

That line is the path to the environment on your own disk. It leaks your
username and means nothing on anyone else's machine. Save and close.

**Step 5.** While the file is open, glance at the `pip:` section if there is one.
If any line points at a local file (`file:///C:/...`) rather than a package name,
replace it with the public package name and version — a reader cannot install
from a path on your computer.

`--no-builds` is the flag that matters. Without it every line carries a build
hash like `=py310h7f8727e_0`, which is specific to one platform and one channel
snapshot, and the file then fails to solve on anyone else's machine. That is
worse than having no file: it looks like a guarantee and behaves like a wall.

---

## If either of those goes wrong

They are worth having, but they are not worth a lost afternoon. A plain record
of what was installed is honest and most reviewers accept it. From R:

```r
writeLines(capture.output(sessionInfo()), "R_sessionInfo.txt")
write.csv(installed.packages()[, c("Package", "Version")],
          "R_packages.csv", row.names = FALSE)
```

And from Anaconda Prompt, with the environment activated:

```
conda activate tf-gpu
pip freeze > python_packages.txt
```

Commit those instead, and say in the README that they are a package inventory
rather than a lock file. Stating plainly what you have is always better than
shipping a lock file that does not work.

---

## What neither file covers

Neither renv nor conda manages CUDA, cuDNN or the graphics driver on Windows,
and TensorFlow's GPU support is sensitive to all three. An environment that
solves cleanly can still fall back to CPU or fail to initialise.

So record them separately. This is the machine the study ran on:

```
TensorFlow      2.10.0
CUDA (TF build) 11.2     what TensorFlow was compiled against -- match this
cuDNN           8
GPU             NVIDIA GeForce RTX 4060
Driver          596.49
CUDA (driver)   13.2     the highest runtime this driver supports, per nvidia-smi
```

Both CUDA numbers are listed because they are not the same thing and the gap
between them is wide enough to mislead. `nvidia-smi` reports the highest runtime
the installed driver can support — 13.2 here. TensorFlow is compiled against one
specific, older runtime, and that is the figure to match when building an
environment: **11.2**. TensorFlow 2.10 is the last release with native Windows
GPU support and could not use CUDA 13 if it were offered one.

Read from the library itself rather than inferred:

```
conda activate tf-gpu
python -c "import tensorflow as tf; b=tf.sysconfig.get_build_info(); print('CUDA',b['cuda_version'],'cuDNN',b['cudnn_version'])"
```

`bat/check.bat` prints the R side of this on any Windows machine, and
`R/00_paths.R` writes `sessionInfo.txt` next to every set of results, so a
number can always be traced back to the versions that produced it.
