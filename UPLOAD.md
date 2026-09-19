# Putting this on GitHub and getting a DOI

## สรุปขั้นตอนแบบสั้น (ภาษาไทย)

ทำตามลำดับ ข้ามไม่ได้สองขั้น — ขั้น 3a กับขั้น 5 แก้ย้อนหลังไม่ได้

| # | ทำอะไร | ใช้เวลา |
|---|---|---|
| 1 | แตกซิปลง**โฟลเดอร์ใหม่เปล่า ๆ** ห้ามมีไฟล์ข้อมูลจริงปนอยู่ | 1 นาที |
| 2 | สร้าง repo บน github.com ชื่อ `stcraan-forecasting` ตั้งเป็น **Public** และ **อย่าติ๊ก** ทั้งสามช่อง (Add README / Add .gitignore / Choose a license) | 2 นาที |
| 3a | อัป **`.gitignore` ไฟล์เดียวก่อน** แล้ว commit — Windows ซ่อนไฟล์ที่ขึ้นต้นด้วยจุด ต้องเปิด `View → Show → Hidden items` ก่อนถึงจะลากได้ | 2 นาที |
| 3b | อัปที่เหลือทั้งหมด **ลากเป็นโฟลเดอร์** ไม่ใช่ลากไฟล์ข้างใน | 5 นาที |
| 3c | เปิด repo เช็คว่า `R/` มี 7 โฟลเดอร์ย่อย · `gee/` มี 12 ไฟล์ · และ**ไม่มี** `panel_synthetic.txt`, `cluster_summary_ADM3_Year.csv`, `.h5` | 2 นาที |
| 4 | แก้ `README.md` บน GitHub แทนที่ `REPLACE_WITH_REPOSITORY_URL` ทั้งสองจุดด้วย URL จริง | 2 นาที |
| 5 | **เปิดสวิตช์ Zenodo ก่อนสร้าง release** — zenodo.org → ล็อกอิน**ด้วย GitHub** → เมนู GitHub → หา repo → สับสวิตช์เป็น On | 3 นาที |
| 6 | สร้าง release tag `v1.0.0` คำอธิบายคัดจาก `CHANGELOG.md` → Zenodo จะออก DOI ให้ในไม่กี่นาที | 5 นาที |
| 7 | เอา **concept DOI** (อันใต้ "Cite all versions") ไปใส่ 4 ที่: `CITATION.cff` · DAS ในต้นฉบับ · cover letter · ช่อง data availability ในระบบ submission | 10 นาที |
| 8 | ขอหนังสือ/อีเมลจาก BAAC ยินยอมให้เผยแพร่ใต้ MIT **ลงวันที่ก่อน** repo เป็น public | — |

### สองกับดัก

**ขั้น 3a — git history ลบไม่ออก** ถ้าเผลออัปไฟล์ต้องห้ามขึ้นไปแม้แต่ครั้งเดียว
ต่อให้ลบใน commit ถัดไป มันก็ยังอยู่ใน repo และยัง clone ได้ ทางแก้มีทางเดียวคือ
ลบ repo ทิ้งแล้วเริ่มใหม่ `.gitignore` กันไฟล์พวกนี้ไว้หมดแล้ว แต่จะกันได้ก็ต่อเมื่อ
มันขึ้นไปเป็น commit แรก

**ขั้น 5 — Zenodo เก็บเฉพาะ release ที่เกิดหลังเปิดสวิตช์** สร้าง release ก่อนแล้วค่อย
เปิดสวิตช์ = ไม่ได้ DOI และย้อนไปเก็บให้ไม่ได้ ต้องสร้าง release ใหม่อีกรอบ

### ใช้ concept DOI ไม่ใช่ version DOI

Zenodo ให้มาสองเลข concept DOI ชี้ไปที่เวอร์ชันล่าสุดเสมอ ส่วน version DOI ตรึงอยู่ที่
v1.0.0 ตลอดไป ถ้าต้องออก v1.0.1 ตอนแก้ revision ลิงก์ในเปเปอร์ที่เป็น concept DOI
จะยังใช้ได้ แต่ version DOI จะชี้ไปที่ของเก่า

---

*The full version follows in English.*

---

Follow the order. Step 5 in particular cannot be fixed afterwards.

---

## 0. Before anything — the one irreversible mistake

Git history is permanent. A restricted file committed once and deleted in the
next commit is still in the repository, still clonable, and still on GitHub's
servers. Recovering means deleting the repository and starting over, and any
clone taken in the meantime keeps the file.

So: **do not run `git init` in a folder that contains restricted files.** Work in
a clean folder containing only this tree. Specifically, these must not be
anywhere inside it:

- `cluster_summary_ADM3_Year.csv` and anything else with per-sub-district counts
- `data_hybrid2_prec*.txt`, `3_geo3y*.txt`, `3_fin3y*.txt`
- any `*_predict.txt`, any `HBDL2*` model folder, any `.h5`

`.gitignore` excludes all of these, but a `.gitignore` only helps if it is
committed **first**, which is what step 3 does.

---

## 1. Fill in the placeholders

Search the tree for `REPLACE_WITH_` and fix what you can now:

| File | Placeholder | Fill with |
|---|---|---|
| `gee/*.js` (12 files) | `REPLACE_WITH_YOUR_ADM3_ASSET` | leave as is — it is meant to stay a placeholder |
| `README.md` | `REPLACE_WITH_REPOSITORY_URL` | after step 4 |
| `CITATION.cff` | `REPLACE_WITH_REPOSITORY_URL`, `REPLACE_WITH_ZENODO_CONCEPT_DOI` | after steps 4 and 6 |

The GPU block in `ENVIRONMENT.md` and `README.md` is already filled in.

---

## 2. Create the repository on GitHub

github.com → **New repository**

- Name: `stcraan-forecasting`
- **Public**
- **Do not** tick "Add a README file", "Add .gitignore" or "Choose a license".
  Leave all three off. This tree already has them, and letting GitHub create its
  own means resolving a conflict on the first push for no reason.

Press **Create repository**. You now have an empty repository and a page of
instructions. Ignore that page; use step 3 instead.

---

## 3. Upload — the browser way, no git installed

GitHub's web uploader is enough for a repository this size, and it preserves
folders if you drag folders rather than files.

**3a. Commit `.gitignore` first, on its own.**

On the empty repository page, click **uploading an existing file**. Drag in
`.gitignore` alone. In the "Commit changes" box type `Add .gitignore` and press
**Commit changes**.

Windows Explorer hides files that begin with a dot. Turn on
`View → Show → Hidden items` or you will not see it to drag.

**3b. Now everything else.**

Click **Add file → Upload files**. Drag the remaining top-level items in one go:

```
README.md   LICENSE   CITATION.cff   CHANGELOG.md
AUDIT.md    ENVIRONMENT.md   UPLOAD.md
renv.lock   environment.yml
R/   data/   gee/   bat/   output/
```

Drag the **folders**, not their contents — the uploader keeps the structure.
Commit message: `Initial release: analysis code, results and schema`.

Wait for it to finish before navigating away; it uploads in the background.

**3c. Check.**

Open the repository and confirm: `R/` has seven subfolders, `gee/` has twelve
`.js` files, `output/` has `results/` and `diagnostics/`, and there is **no**
`panel_synthetic.txt`, no `cluster_summary_ADM3_Year.csv`, no `.h5`.

(`data/synthetic/smoke_data.xlsx` **should** be there — it is the mock three-row
extract, not real records.)

---

## 3-alt. Upload with git, if you have it

```bash
cd stcraan-forecasting
git init
git add .gitignore && git commit -m "Add .gitignore"
git add . && git status          # READ THIS OUTPUT BEFORE COMMITTING
git commit -m "Initial release: analysis code, results and schema"
git branch -M main
git remote add origin https://github.com/<you>/stcraan-forecasting.git
git push -u origin main
```

`git status` before the second commit is the safety check. Read the file list.
If anything restricted appears, stop and fix `.gitignore` — do not commit and
clean up afterwards.

---

## 4. Copy the repository URL into the README

Edit `README.md` on GitHub (pencil icon), replace both occurrences of
`REPLACE_WITH_REPOSITORY_URL` with the actual URL, commit.

---

## 5. Turn on Zenodo — BEFORE creating any release

This is the step that cannot be undone in place.

1. Go to **zenodo.org** and sign in **with GitHub** (not with an email account —
   the link only works for the GitHub identity).
2. Top-right menu → **GitHub**.
3. Find `stcraan-forecasting` in the list and **switch the toggle to On**.
   If it is not listed, press **Sync now**; the repository must be public.

Zenodo only archives releases created **after** the toggle is on. A release made
before it is invisible to Zenodo and gets no DOI, and switching the toggle later
does not pick it up — you have to publish another release.

---

## 6. Create release `v1.0.0`

On the repository page: **Releases** → **Create a new release**.

- **Choose a tag** → type `v1.0.0` → "Create new tag: v1.0.0 on publish"
- Release title: `v1.0.0`
- Description: paste the v1.0.0 section of `CHANGELOG.md`
- **Publish release**

Within a few minutes Zenodo creates a record and a DOI. Find it at
zenodo.org → your uploads.

Release notes can be edited on GitHub at any time afterwards, but **Zenodo does
not follow the edit** — its archived copy is captured at the moment you press
Publish. Get the description right first.

---

## 7. Use the concept DOI, not the version DOI

Zenodo gives you two:

| | Points at | Use for |
|---|---|---|
| **Concept DOI** | always the newest version | the paper, `CITATION.cff` |
| Version DOI | v1.0.0 forever | nothing here |

On the Zenodo record page the concept DOI is the one under "Cite all versions".
If you have to publish v1.0.1 during revision, the concept DOI in the paper keeps
working; a version DOI would not.

Put it in four places:

1. `CITATION.cff` — the `doi:` field
2. the Data Availability Statement in the manuscript
3. the cover letter — `[CODE REPOSITORY URL]` and `[CODE ZENODO DOI]`
4. the submission system's data-availability field

---

## 8. One piece of paper

Before the repository goes public, get BAAC's agreement to publish under MIT in
writing and dated. An email is enough. MIT is irrevocable for what has been
published, so the agreement should exist beforehand rather than afterwards.
