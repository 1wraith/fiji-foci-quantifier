# Fiji Foci Quantifier

An ImageJ/Fiji macro for batch counting DNA damage foci (e.g. γH2AX) in multi-channel fluorescence images. It finds individual nuclei in the DAPI (blue) channel, then counts the foci in the red and green channels inside each nucleus. Results for every cell in every image go into a single CSV, with QC images so each count can be checked by eye.

## Features

- **Batch processing** of a whole folder of `.nd2`, `.tif` and `.tiff` files, including every field of view in multi-series `.nd2` files
- **Automatic channel detection** from each channel's display colour (blue = nuclei, red and green = foci), with a fallback to channel numbers
- **Individual cell detection** in the blue channel: background removal, thresholding, splitting of touching nuclei by brightness and shape, and filtering by size and circularity
- **Foci counting** in the red and green channels inside each blue-defined nucleus, using spot enhancement and Find Maxima
- **Per-cell results** in one CSV: nucleus area and shape, mean intensities, foci counts, and red foci as a percentage of green foci
- **QC images** for every field of view, showing the outlined and numbered cells, rejected objects and every counted focus
- **Saved cell outlines** (ROI sets) that can be reopened in Fiji

## Requirements

- [Fiji](https://fiji.sc/) (ImageJ with Bio-Formats included)
- Multi-channel images with a nuclear stain (DAPI/Hoechst) in blue and foci markers in red and/or green

## Installation

Download `Batch_Foci_Quantifier.ijm` from this repository. Nothing else needs installing.

## Usage

1. In Fiji, go to **Plugins › Macros › Run…** and choose `Batch_Foci_Quantifier.ijm`.
2. Check the settings in the dialog (see below) and click **OK**.
3. Choose the **image folder**. It must directly contain the image files, because subfolders are not searched.
4. Choose the **output folder** for the results.
5. When the run finishes, a message reports how many images were found and how many cells were recorded. The **Log** window lists each image with its channel assignments and cell count.

Close `ALL_SUMMARY_RESULTS.csv` in Excel before running. Otherwise Excel locks the file and the macro can't write to it.

## Settings

### Foci (red / green)

| Setting | Default | What it does |
|---|---|---|
| Prominence, red foci | 200 | How much brighter than its surroundings a spot must be to count as a focus. Higher = fewer foci. |
| Prominence, green foci | 75 | As above, for the green channel. |
| Largest focus diameter (µm) | 1.0 | Size of the background-removal step that isolates small spots from diffuse nuclear signal. |

### Cell detection (blue)

| Setting | Default | What it does |
|---|---|---|
| Min nucleus area (µm²) | 40 | Smaller objects are rejected (debris, fragments). |
| Max nucleus area (µm², 0 = no limit) | 400 | Larger objects are rejected (unsplit clumps). |
| Min circularity (0–1) | 0.5 | Less round objects are rejected. |
| Background radius (µm, 0 = off) | 25 | Removes uneven background and out-of-focus haze. |
| Smoothing sigma (µm, 0 = off) | 0.5 | Evens out nuclear texture so each nucleus thresholds as one object. |
| Cell-splitting blur (µm) | 1.2 | Smoothing used before finding one brightness peak per nucleus. |
| Cell-splitting sensitivity | 0.10 | Lower = touching nuclei are split more readily. |
| Threshold method | Otsu | Auto-threshold method for the blue channel. Li can work better for dim nuclei. |
| Split touching cells by brightness | On | Cuts along dimmer gaps between neighbouring nuclei. |
| Also split by shape (watershed) | On | A second, shape-based split. |

### General

| Setting | Default | What it does |
|---|---|---|
| Max-intensity Z-project z-stacks | On | Flattens z-stacks before analysis. |
| Process every series in multi-series .nd2 files | On | Analyses every field of view in a file, not just the first. |
| Save QC overlay images | On | Saves the QC images described below. |
| Always use these channel numbers instead of colours | Off | Skips colour detection and uses the fallback channel numbers. |
| Blue / Red / Green channel | 1 / 2 / 3 | Fallback channel numbers, used only when colours can't be identified. Channel 1 = `C=0` in Fiji's window titles. |

## Output

```
output_folder/
├── ALL_SUMMARY_RESULTS.csv
├── QC/
│   ├── <image>_QC_Nuclei.png
│   ├── <image>_QC_Red.png
│   └── <image>_QC_Green.png
└── Cell_ROIs/
    └── <image>_cells.zip
```

### ALL_SUMMARY_RESULTS.csv

One row per cell. Fields of view from multi-series files are labelled `_S1`, `_S2`, and so on.

| Column | Description |
|---|---|
| Image_Name | Source file (plus series number) |
| Cell_ID | Cell number, matching the label on the QC images |
| Nucleus_Area | Nucleus area in calibrated units (normally µm²) |
| Circularity | Nucleus circularity (1 = perfect circle) |
| Mean_DAPI | Mean blue intensity in the nucleus |
| Mean_Red | Mean red intensity in the nucleus |
| Foci_Count_Red | Number of red foci in the nucleus |
| Mean_Green | Mean green intensity in the nucleus |
| Foci_Count_Green | Number of green foci in the nucleus |
| Red_Percent_of_Green | Red foci as a percentage of green foci (e.g. 25 red / 50 green = 50.0). `NA` if a channel is missing or the cell has no green foci. |

`Red_Percent_of_Green` compares the two counts. It doesn't measure whether red and green foci overlap.

### QC images

- **Nuclei:** accepted cells outlined in yellow and numbered; objects rejected by the size, shape or edge filters outlined in red.
- **Red / Green:** cell outlines in cyan, with each counted focus marked (yellow on red, magenta on green). Only foci inside an accepted cell are marked.

### Cell ROIs

Each field of view's cell outlines are saved as an ROI set. Open the zip in Fiji's ROI Manager over the original image to inspect or edit individual cells.

## Tuning for your images

The defaults are a starting point. Before analysing a full dataset, compare the macro's counts with manual counts on 5–10 cells:

- **Too many foci:** raise that channel's prominence.
- **Too few foci:** lower it.
- **Touching nuclei counted as one cell:** lower the cell-splitting sensitivity (e.g. 0.07).
- **Single nuclei cut in two:** raise the sensitivity or the splitting blur.
- **Real nuclei rejected (red on the QC image):** lower the min circularity or min area, or raise the max area.

Once the counts agree, keep the same settings for every condition in the experiment.

## Notes and limitations

- Prominence values are absolute intensities. They only mean the same thing across images acquired with identical exposure, gain and laser settings.
- Max-intensity projection can merge foci that sit above each other in z, so very dense nuclei may be slightly undercounted.
- Nuclei touching the image border are excluded, because their foci counts would be incomplete.
- `Mean_DAPI` comes from the max projection and isn't suitable for DNA-content or cell-cycle analysis.
- If one file can't be opened, the batch stops at that file. Results already written stay in the CSV, and the Log shows which file it reached.

## License

Add a license of your choice (e.g. MIT) here.
