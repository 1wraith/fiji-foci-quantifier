var doZProject   = true;
var thrMethod    = "Otsu";
var bgRadius     = 25;
var blurSigma    = 0.5;
var minSize      = 40;
var maxSize      = 400;
var minCirc      = 0.5;
var useWatershed = true;
var useSplit     = true;
var splitSigma   = 1.2;
var splitSens    = 0.10;
var fociSize     = 1.0;

// ---------------- Settings ----------------
chOptions  = newArray("1", "2", "3", "4");
chOptionsN = newArray("None", "1", "2", "3", "4");
thrOptions = newArray("Otsu", "Li", "Triangle", "Huang", "Default", "Moments", "Mean");

Dialog.create("Foci Quantifier Settings");
Dialog.addMessage("Channels are identified from their LUT colour (hex code):\n   Blue = finds the individual cells (nuclei)\n   Red / Green = foci counted inside each cell found in blue");
Dialog.addMessage("--- Foci (red / green) - lower prominence = more foci ---");
Dialog.addNumber("Prominence, red foci:", 200);
Dialog.addNumber("Prominence, green foci:", 75);
Dialog.addNumber("Largest focus diameter (um):", fociSize);
Dialog.addMessage("--- Cell detection (blue) ---");
Dialog.addNumber("Min nucleus area (um^2):", minSize);
Dialog.addNumber("Max nucleus area (um^2, 0 = no limit):", maxSize);
Dialog.addNumber("Min circularity (0-1):", minCirc);
Dialog.addNumber("Background radius (um, 0 = off):", bgRadius);
Dialog.addNumber("Smoothing sigma (um, 0 = off):", blurSigma);
Dialog.addNumber("Cell-splitting blur (um):", splitSigma);
Dialog.addNumber("Cell-splitting sensitivity (lower = more splitting):", splitSens);
Dialog.addChoice("Threshold method:", thrOptions, thrMethod);
Dialog.addCheckbox("Split touching cells by brightness (recommended)", useSplit);
Dialog.addCheckbox("Also split by shape (watershed)", useWatershed);
Dialog.addMessage("--- General ---");
Dialog.addCheckbox("Max-intensity Z-project z-stacks", true);
Dialog.addCheckbox("Process every series in multi-series .nd2 files", true);
Dialog.addCheckbox("Save QC overlay images", true);
Dialog.addMessage("Fallback - used only if colours can't be identified (channel 1 = 'C=0'):");
Dialog.addCheckbox("Always use these channel numbers instead of colours", false);
Dialog.addChoice("Blue / DAPI channel:", chOptions, "1");
Dialog.addChoice("Red channel:", chOptionsN, "2");
Dialog.addChoice("Green channel:", chOptionsN, "3");
Dialog.show();

proms        = newArray(Dialog.getNumber(), Dialog.getNumber());
fociSize     = Dialog.getNumber();
minSize      = Dialog.getNumber();
maxSize      = Dialog.getNumber();
minCirc      = Dialog.getNumber();
bgRadius     = Dialog.getNumber();
blurSigma    = Dialog.getNumber();
splitSigma   = Dialog.getNumber();
splitSens    = Dialog.getNumber();
thrMethod    = Dialog.getChoice();
useSplit     = Dialog.getCheckbox();
useWatershed = Dialog.getCheckbox();
doZProject   = Dialog.getCheckbox();
allSeries    = Dialog.getCheckbox();
saveQC       = Dialog.getCheckbox();
forceNumbers = Dialog.getCheckbox();
fbNums       = newArray(3);                       // blue, red, green (-1 = none)
for (w = 0; w < 3; w++) {
    ch = Dialog.getChoice();
    fbNums[w] = -1;
    if (ch != "None") fbNums[w] = parseInt(ch);
}
if (fbNums[1] == -1 && fbNums[2] == -1) exit("Pick at least one fallback red or green channel.");
if (fbNums[1] == fbNums[0] || fbNums[2] == fbNums[0] || (fbNums[1] != -1 && fbNums[1] == fbNums[2]))
    exit("Fallback blue, red and green must all be different channels.");

fociNames = newArray("Red", "Green");
ptCols    = newArray("yellow", "magenta");
wanted    = newArray("blue", "red", "green");

// ---------------- Setup ----------------
inputDir  = getDirectory("Choose Image Folder");
outputDir = getDirectory("Choose Destination Folder to Save Results");
list   = getFileList(inputDir);
nImg = 0;
for (i = 0; i < list.length; i++) {
    nm = toLowerCase(list[i]);
    if (endsWith(nm, ".nd2") || endsWith(nm, ".tif") || endsWith(nm, ".tiff")) nImg++;
}
if (nImg == 0) {
    shown = "";
    for (i = 0; i < minOf(list.length, 10); i++) shown = shown + "\n   " + list[i];
    exit("No .nd2 / .tif / .tiff files found directly in:\n" + inputDir + "\n\nThis folder contains " + list.length + " item(s):" + shown + "\n\nSubfolders are not searched - choose the folder that holds the image files themselves.");
}
qcDir  = outputDir + "QC" + File.separator;
roiDir = outputDir + "Cell_ROIs" + File.separator;
if (saveQC) File.makeDirectory(qcDir);
File.makeDirectory(roiDir);

header      = "Image_Name,Cell_ID,Nucleus_Area,Circularity,Mean_DAPI,Mean_Red,Foci_Count_Red,Mean_Green,Foci_Count_Green,Red_Percent_of_Green";
summaryFile = resetFile(outputDir + "ALL_SUMMARY_RESULTS.csv", header);

setOption("BlackBackground", true);
run("Set Measurements...", "area mean integrated shape redirect=None decimal=4");
run("Close All");
run("ROI Manager...");
roiManager("reset");
run("Clear Results");
print("\\Clear");
print("Input folder: " + inputDir);
print("Image files found: " + nImg);
totalCells = 0;
totalFields = 0;
run("Bio-Formats Macro Extensions");
setBatchMode(true);

// ---------------- Main loop ----------------
for (i = 0; i < list.length; i++) {
    lname = toLowerCase(list[i]);
    if (endsWith(lname, ".nd2") || endsWith(lname, ".tif") || endsWith(lname, ".tiff")) {
        path = inputDir + list[i];

        nSeries = 1;
        if (allSeries && endsWith(lname, ".nd2")) {
            Ext.setId(path);
            Ext.getSeriesCount(nSeries);
            Ext.close();
        }

        for (s = 1; s <= nSeries; s++) {
            run("Close All");
            roiManager("reset");
            opts = "open=[" + path + "] color_mode=Colorized view=Hyperstack stack_order=XYCZT split_channels";
            if (nSeries > 1) opts = opts + " series_" + s;
            run("Bio-Formats Importer", opts);

            totalFields++;
            baseName = replace(list[i], ",", "_");
            if (nSeries > 1) baseName = baseName + "_S" + s;
            print(baseName);

            // ---- Assign roles (blue, red, green) from LUT colour ----
            titles = getList("image.titles");
            roles  = newArray("", "", "");
            hits   = newArray(0, 0, 0);
            for (k = 0; k < titles.length; k++) {
                hex = lutHex(titles[k]);
                col = colourName(hex);
                for (w = 0; w < 3; w++) if (col == wanted[w]) { roles[w] = titles[k]; hits[w]++; }
                print("   " + titles[k] + "   " + hex + "   -> " + col);
            }
            detected = (hits[0] == 1 && hits[1] <= 1 && hits[2] <= 1 && hits[1] + hits[2] >= 1);
            if (forceNumbers || !detected) {
                if (!forceNumbers) print("   Colours not identified cleanly - using fallback channel numbers");
                for (w = 0; w < 3; w++) {
                    roles[w] = "";
                    if (fbNums[w] != -1) roles[w] = findChannel(fbNums[w]);
                }
            }

            if (roles[0] == "" || (roles[1] == "" && roles[2] == "")) {
                print("   SKIPPED: no blue nucleus channel, or no red/green foci channel found");
            } else {
                print("   Nuclei: " + roles[0] + "  |  Red foci: " + roles[1] + "  |  Green foci: " + roles[2]);

                // ---- Blue: find individual cells once ----
                prepChannel(roles[0], "DAPI_raw");
                count = segmentNuclei("DAPI_raw");

                if (count == 0) {
                    print("   No cells found");
                } else {
                    roiManager("Save", roiDir + baseName + "_cells.zip");
                    measureAll("DAPI_raw");
                    area  = Table.getColumn("Area");
                    circ  = Table.getColumn("Circ.");
                    meanD = Table.getColumn("Mean");

                    // ---- Red / green: same cell ROIs -> [means..., counts...] ----
                    stats = newArray(4 * count);
                    for (c = 0; c < 2; c++) {
                        qcPath = "";
                        if (saveQC) qcPath = qcDir + baseName + "_QC_" + fociNames[c] + ".png";
                        res = fociStats(fociNames[c], roles[c + 1], proms[c], ptCols[c], count, qcPath);
                        for (j = 0; j < 2 * count; j++) stats[c * 2 * count + j] = res[j];
                    }
                    if (saveQC) saveQCImage("DAPI_raw", qcDir + baseName + "_QC_Nuclei.png", "yellow", "", "");

                    // ---- Build all rows once, append to the summary once ----
                    hasBoth = (roles[1] != "" && roles[2] != "");
                    block = "";
                    for (r = 0; r < count; r++) {
                        block = block + baseName + "," + cellID(r) + "," + area[r] + "," + circ[r] + "," + meanD[r];
                        for (c = 0; c < 2; c++) block = block + "," + stats[c * 2 * count + r] + "," + stats[c * 2 * count + count + r];
                        // Red foci as a percentage of green foci in the same cell
                        // (e.g. 25 red / 50 green = 50). NA if a channel is missing or green = 0
                        pct = "NA";
                        if (hasBoth) {
                            cntRed   = stats[count + r];
                            cntGreen = stats[3 * count + r];
                            if (cntGreen > 0) pct = d2s(100 * cntRed / cntGreen, 1);
                        }
                        block = block + "," + pct;
                        if (r < count - 1) block = block + "\n";
                    }
                    File.append(block, summaryFile);
                    totalCells = totalCells + count;
                    print("   " + count + " cells measured");
                }
            }
            run("Close All");
            roiManager("reset");
        }
    }
}

setBatchMode(false);
run("Clear Results");
msg = "Batch Complete!\n\nImage files found: " + nImg + "\nFields of view opened: " + totalFields + "\nCells written to the CSV: " + totalCells;
msg = msg + "\n\nResults: ALL_SUMMARY_RESULTS.csv\nCell outlines: Cell_ROIs folder";
if (totalCells == 0) msg = msg + "\n\nNO CELLS WERE RECORDED - the Log window shows what happened to each image\n('No cells found' or 'SKIPPED').";
showMessage(msg);


// =====================================================================
// Modules
// =====================================================================

// ---- Files / naming ----
function resetFile(p, head) {
    if (File.exists(p)) File.delete(p);
    File.append(head, p);
    return p;
}

function cellID(idx) {
    return "Cell_" + IJ.pad(idx + 1, 3);
}

// ---- Channel identification ----
function lutHex(title) {                       // #RRGGBB of the brightest LUT entry
    selectWindow(title);
    if (bitDepth() == 24) return "#RGB";
    getLut(reds, greens, blues);
    return "#" + hex2(reds[255]) + hex2(greens[255]) + hex2(blues[255]);
}

function hex2(v) {
    return toUpperCase(IJ.pad(toHex(v), 2));
}

function colourName(hex) {                     // component "on" if >= 60% of brightest
    if (hex == "#RGB") return "rgb_image";
    v = newArray(parseInt(substring(hex, 1, 3), 16), parseInt(substring(hex, 3, 5), 16), parseInt(substring(hex, 5, 7), 16));
    Array.getStatistics(v, mn, mx);
    if (mx < 50) return "unknown";
    code = 0;                                  // red = 4, green = 2, blue = 1
    if (v[0] >= 0.6 * mx) code = code + 4;
    if (v[1] >= 0.6 * mx) code = code + 2;
    if (v[2] >= 0.6 * mx) code = code + 1;
    names = newArray("unknown", "blue", "green", "cyan", "red", "magenta", "yellow", "grey");
    return names[code];
}

function findChannel(ch) {                     // window ending "C=n" (ch is 1-based)
    t = getList("image.titles");
    for (j = 0; j < t.length; j++) if (endsWith(t[j], "C=" + (ch - 1))) return t[j];
    return "";
}

// ---- Image preparation ----
function prepChannel(title, newName) {         // Z-project (or one slice) and rename
    selectWindow(title);
    if (nSlices > 1) {
        if (doZProject) run("Z Project...", "projection=[Max Intensity]");
        else run("Duplicate...", "title=tmp_single");
        t = getTitle();
        selectWindow(title);
        close();
        selectWindow(t);
    }
    rename(newName);
}

// Individual cells from the blue channel. Works on a copy, so DAPI_raw stays
// untouched for intensity measurements. Leaves "DAPI_mask" open (all objects)
// so rejected objects can be shown on the QC image.
function segmentNuclei(title) {
    selectWindow(title);
    run("Select None");
    run("Duplicate...", "title=DAPI_mask");
    getPixelSize(unit, pw, ph);
    // 1. Remove uneven background / out-of-focus haze
    if (bgRadius > 0) run("Subtract Background...", "rolling=" + round(bgRadius / pw) + " sliding");
    if (useSplit) run("Duplicate...", "title=DAPI_split");   // copy kept for splitting
    // 2. Smooth texture so each nucleus thresholds as one solid object
    selectWindow("DAPI_mask");
    if (blurSigma > 0) run("Gaussian Blur...", "sigma=" + blurSigma + " scaled");
    // 3. Threshold, fill nucleoli/holes
    setAutoThreshold(thrMethod + " dark");
    run("Convert to Mask");
    run("Fill Holes");
    // 4. Split touching cells: each nucleus is brightest in its centre, so cut
    //    along the dimmer valleys between neighbours, then (optionally) by shape
    if (useSplit) splitByBrightness("DAPI_mask", "DAPI_split");
    selectWindow("DAPI_mask");
    if (useWatershed) run("Watershed");
    // 5. Keep only objects with nucleus-like size and shape; drop edge cells
    sizeMax = "Infinity";
    if (maxSize > 0) sizeMax = "" + maxSize;
    run("Analyze Particles...", "size=" + minSize + "-" + sizeMax + " circularity=" + minCirc + "-1.00 exclude add");
    n = roiManager("count");
    for (q = 0; q < n; q++) {
        roiManager("select", q);
        roiManager("rename", cellID(q));
    }
    run("Select None");
    return n;
}

// Cut the mask along intensity valleys between neighbouring nuclei.
// Prominence scales with how bright the nuclei are, so it adapts per image.
function splitByBrightness(maskT, imgT) {
    selectWindow(maskT);
    getStatistics(a, m, mn, mx);
    if (mx > 0) {
        run("Create Selection");
        selectWindow(imgT);
        run("Restore Selection");
        getStatistics(a, meanN);
        run("Select None");
        run("Gaussian Blur...", "sigma=" + splitSigma + " scaled");
        run("Find Maxima...", "prominence=" + (splitSens * meanN) + " output=[Segmented Particles]");
        segT = getTitle();
        selectWindow(maskT);
        run("Select None");
        imageCalculator("AND", maskT, segT);
        close(segT);
    }
    close(imgT);
}

// Keep small bright spots, remove the diffuse signal across the nucleus
function enhanceSpots(title) {
    selectWindow(title);
    run("Select None");
    run("Duplicate...", "title=" + title + "_spots");
    getPixelSize(unit, pw, ph);
    run("Subtract Background...", "rolling=" + maxOf(1, round(fociSize / pw)));
    run("Gaussian Blur...", "sigma=1");          // 1 pixel: removes single-pixel noise
    return getTitle();
}

// ---- Measurement ----
function measureAll(title) {                   // every cell in one call -> Results table
    selectWindow(title);
    run("Select None");
    run("Clear Results");
    roiManager("Deselect");
    roiManager("Measure");
}

function fociStats(name, title, prom, ptCol, n, qcPath) {   // returns [means(n), counts(n)]
    out = newArray(2 * n);
    if (title == "") {
        for (j = 0; j < 2 * n; j++) out[j] = "NA";
        return out;
    }
    prepChannel(title, name);
    if (bitDepth() == 8 && prom > 255) print("   WARNING: " + name + " is 8-bit - prominence " + prom + " can never be reached");
    measureAll(name);
    means = Table.getColumn("Mean");             // mean intensity from the raw image
    spotT = enhanceSpots(name);
    run("Find Maxima...", "prominence=" + prom + " output=[Single Points]");
    rename(name + "_Maxima");
    close(spotT);
    measureAll(name + "_Maxima");
    raw = Table.getColumn("RawIntDen");        // each focus = one pixel of 255
    for (j = 0; j < n; j++) {
        out[j]     = means[j];
        out[n + j] = raw[j] / 255;
    }
    if (qcPath != "") saveQCImage(name, qcPath, "cyan", name + "_Maxima", ptCol);
    return out;
}

// ---- QC images ----
function selectAllNuclei() {
    if (roiManager("count") == 1) roiManager("select", 0);
    else { roiManager("Deselect"); roiManager("Combine"); }
}

function saveQCImage(title, savePath, lineCol, maxT, ptCol) {
    selectWindow(title);
    run("Select None");
    run("Duplicate...", "title=QC_tmp");
    run("Enhance Contrast", "saturated=0.35");

    // Every accepted cell outlined in one step
    roiManager("Deselect");
    roiManager("Set Color", lineCol);
    roiManager("Set Line Width", 2);
    run("From ROI Manager");
    Overlay.drawLabels(false);

    // Cell number beside each outline (matches Cell_ID in the CSV)
    fs = maxOf(14, round(getWidth() / 70));
    setFont("SansSerif", fs, "bold antialiased");
    setColor("white");
    for (q = 0; q < roiManager("count"); q++) {
        roiManager("select", q);
        Roi.getBounds(bx, by, bw, bh);
        Overlay.drawString("" + (q + 1), bx + bw, by + fs);
    }
    run("Select None");

    if (maxT == "") {
        // Nuclei image: objects that were found but rejected (size/shape/edge) in red
        selectWindow("DAPI_mask");
        run("Select None");
        run("Duplicate...", "title=QC_rej");
        selectAllNuclei();
        setBackgroundColor(0, 0, 0);
        run("Clear", "slice");
        run("Select None");
        getStatistics(a, m, mn, mx);
        if (mx > 0) {
            setThreshold(255, 255);
            run("Create Selection");
            selectWindow("QC_tmp");
            run("Restore Selection");
            Overlay.addSelection("red", 2);
            run("Select None");
        }
        close("QC_rej");
    } else {
        // Foci image: only the foci that were counted (inside an accepted cell)
        selectWindow(maxT);
        run("Select None");
        run("Duplicate...", "title=QC_pts");
        selectAllNuclei();
        setBackgroundColor(0, 0, 0);
        run("Clear Outside");
        run("Select None");
        run("Find Maxima...", "prominence=10 output=[Point Selection]");
        hasPts = (selectionType() != -1);
        if (hasPts) getSelectionCoordinates(xs, ys);
        close("QC_pts");
        selectWindow("QC_tmp");
        if (hasPts) {
            makeSelection("point", xs, ys);
            Overlay.addSelection(ptCol);
        }
    }
    selectWindow("QC_tmp");
    run("Select None");
    run("Flatten");
    saveAs("PNG", savePath);
    close();
    close("QC_tmp");
}
