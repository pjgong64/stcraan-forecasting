# gee/ — Earth observation extraction

Earth Engine JavaScript. Run in the Code Editor at
[code.earthengine.google.com](https://code.earthengine.google.com), in the order
below. The output is one row per sub-district per year, which
`R/prep/6_Build_SAI_file.r` then joins to the borrower panel.

One script per channel. Each filters and quality-masks its source collection,
composites it by month, reduces it over the ADM3 polygons and exports a CSV that
`R/prep/geomaniV2.r` then assembles into the panel.

| Script | Channel | Source |
|---|---|---|
| `NDVI.js` | vegetation index | MOD09GA V061 |
| `NDWI_GAO.js` | canopy water index | MOD09GA V061 |
| `LST.js` | land surface temperature | MOD11A1 V061 |
| `Precipitation.js` | rainfall | CHIRPS v2.0 |
| `SMAP.js`, `SMAP2_2022.js` | soil moisture | SPL4SMGP v7 |
| `NTL.js` | nighttime radiance | VNP46A1 |
| `VHI.js` | vegetation health index | derived |
| `HSD.js` | heat-stress day count | derived |
| `CRD.js` | cumulative rainfall departure | derived |
| `SAI_NDVI.js`, `SAI_NDWI.js` | standardised anomalies | derived |

Each script covers one year at a time — the date range and `year` variable are
set at the top. Run them year by year rather than widening the range; the
collections are large enough that a three-year request exhausts Earth Engine's
memory.

## Before you run them

Two things are deliberately not hard-coded.

**The boundary asset.** Each script opens with

```js
var ADM3 = ee.FeatureCollection('REPLACE_WITH_YOUR_ADM3_ASSET');
```

Upload the Thai ADM3 boundaries from the
[Humanitarian Data Exchange](https://data.humdata.org) as an Earth Engine asset
and put your own asset path there. The original path pointed into a personal
Earth Engine account, which no one else can read and which identifies its owner,
so it is not published.

**The export destination.** `Export.table.toDrive` writes to whichever Drive the
running account owns. Set `folder` and `description` to something you will
recognise.

## Products

Versions matter — the MODIS collections in particular have been reprocessed, and
a V061 composite is not a V006 composite. The exact products, bands and scale
factors are in `../data/schema/eo_channels.csv`, which is the same table as
Table 1 of the manuscript.

| Channel group | Collection |
|---|---|
| NDVI, NDWI | MOD09GA V061 |
| LST, heat-stress days | MOD11A1 V061 |
| Precipitation, rainfall departure | CHIRPS v2.0 daily |
| Soil moisture | SMAP SPL4SMGP v7 |
| Nighttime radiance | VIIRS Black Marble VNP46A1 |

The window is May to December, which spans land preparation through harvest for
main-season rice. Eight monthly composites per channel.

## The aggregation the paper argues against

`03_zonal_adm3.js` reduces to the sub-district polygon, and that reduction is the
binding constraint the manuscript reports: every borrower cultivating in the same
sub-district in the same season receives an identical sequence, which caps any
forecaster built on it at 0.66223 AUC when scored over the full borrower
population.

If you are adapting this code rather than reproducing the study, this is the
script to change. Cropland-masked extraction would describe rice fields rather
than the whole polygon; within-polygon dispersion statistics would preserve the
heterogeneity that spatial averaging discards; plot-level geolocation, where a
lender can obtain it, removes the constraint rather than easing it.
