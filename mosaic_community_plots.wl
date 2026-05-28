(* ::Package:: *)

(* mosaic_community_plots.wl --
   Companion package for the Wolfram Community post
   "Mosaic at home: 16-member ensemble weather forecasts, analysed in WL".

   Self-contained: every embedded figure in the post is produced by a single
   public function here. The post's notebook ships alongside this .wl and
   shows the one-liner command above each embedded figure, so readers can
   re-render, restyle, or save to a different format.

   Typical use, from inside the post notebook:

       Get[FileNameJoin[{NotebookDirectory[], "mosaic_community_plots.wl"}]];
       data = mcpLoadData[];               (* loads CSVs + coastlines + stats *)
       mcpFigGeo[data]                     (* fig 01 *)
       mcpFig3PanelGlobal["~/forecast.npz"](* fig 09 -- needs a Mosaic .npz   *)

   The "data" Association also gives you the derived stats (bootstrap CI,
   PCA scores, Spearman rho, ...) so you can reuse them in your own cells.
*)

BeginPackage["MosaicPlots`"];

mcpReadNPY::usage          = "mcpReadNPY[path] reads a single .npy file into the matching WL array.";
mcpReadNPZ::usage          = "mcpReadNPZ[path] reads a .npz archive into an Association.";

mcpLoadData::usage         = "mcpLoadData[] loads the shipped assessment CSVs + Natural Earth coastlines and pre-computes the derived stats (bootstrap CI, PCA, etc.). mcpLoadData[embedded] uses an already-uncompressed Association with keys \"summary\" + \"cities\" instead of reading CSVs.";

mcpFigGeo::usage           = "mcpFigGeo[data] -> figure 01: cities on a coastline-backed map, disk colour = 10-day T2m RMSE.";
mcpFigFit::usage           = "mcpFigFit[data] -> figure 02: T2m RMSE vs |latitude| with bootstrap CI band.";
mcpFigCalib::usage         = "mcpFigCalib[data] -> figure 03: ensemble calibration scatter (RMSE vs spread).";
mcpFigPCA::usage           = "mcpFigPCA[data] -> figure 04: cities in the first two principal components of standardised skill.";
mcpFigHeat::usage          = "mcpFigHeat[data] -> figure 05: normalised RMSE heatmap (city x variable).";
mcpFigBias::usage          = "mcpFigBias[data] -> figure 07: per-(variable, city) bias bars.";
mcpFigRadar::usage         = "mcpFigRadar[data] -> figure 08: city skill fingerprint radar.";

mcpRenderGlobal::usage     = "mcpRenderGlobal[field2D, title, range, colorSpec, legendLabel, gLon, gLat, coastlines] renders a global 2D field with Natural Earth coastlines overlaid.";
mcpFig3PanelGlobal::usage  = "mcpFig3PanelGlobal[npzPath] -> figure 09: ensemble-mean 2 m T at day 1, 5, 10 (three stacked global panels).";
mcpFigGlobalSpread::usage  = "mcpFigGlobalSpread[npzPath, day:5] -> figure 10: ensemble standard deviation of 2 m T at given lead day.";
mcpFigGlobalAnomaly::usage = "mcpFigGlobalAnomaly[npzPath] -> figure 11: Day 10 minus Day 1 ensemble-mean 2 m T anomaly.";
mcpFigHov50N::usage        = "mcpFigHov50N[npzPath] -> figure 12: Hovmoller diagram (lon x day) at the 50N latitude band.";
mcpAnimateGlobal::usage    = "mcpAnimateGlobal[npzPath, varName:\"2m_temperature\", outGif:\"global.gif\"] writes a plain ArrayPlot animated GIF for the given variable (simple, no coastlines).";
mcpAnimateEnsembleMean::usage = "mcpAnimateEnsembleMean[npzPath, outGif:\"global.gif\"] writes the 10-day ensemble-mean 2 m T animation with coastlines and RdYlBu_r colours (the variant embedded in the post).";

mcpFigAberdeenCompare::usage = "mcpFigAberdeenCompare[npzPath] -> figure 13: Aberdeen Mosaic forecast vs ERA5 truth vs WeatherData observations.";
mcpFigSkillVsLead::usage     = "mcpFigSkillVsLead[npzPath] -> figure 14: per-city T2m ensemble-mean |error| vs lead time.";
mcpFigCrpsVsLead::usage      = "mcpFigCrpsVsLead[npzPath] -> figure 15: global-mean CRPS of 2 m T ensemble vs lead time.";
mcpFigSkillPersistence::usage= "mcpFigSkillPersistence[npzPath] -> figure 16: 2 m T skill score vs day-1 persistence baseline.";
mcpFigRankHistogram::usage   = "mcpFigRankHistogram[npzPath] -> figure 17: Talagrand rank histogram for the 16-member 2 m T ensemble.";
mcpFigHovLatLead::usage      = "mcpFigHovLatLead[npzPath] -> figure 18: latitude x lead Hovmoller of 2 m T ensemble-mean RMSE.";

Begin["`Private`"];

(* Capture the package directory at LOAD time. $InputFileName inside a
   function called later resolves to the caller, not to this file -- so
   the coastlines path would silently default to the calling script's
   directory and the coastlines would never load. *)
$mcpPackageDir = If[StringQ[$InputFileName],
   DirectoryName[$InputFileName], Directory[]];

(* ============================================================================
   NPY / NPZ readers (35 lines of pure WL, no NumPy required)
   ============================================================================ *)
mcpReadNPY[path_String] := Module[
  {s, magic, major, minor, hl, h, descr, fortran, shape, raw, n, nc, cb},
  s = OpenRead[path, BinaryFormat -> True];
  magic = BinaryReadList[s, "Byte", 6];
  {major, minor} = BinaryReadList[s, "Byte", 2];
  hl = BinaryReadList[s,
        If[major == 1, "UnsignedInteger16", "UnsignedInteger32"], 1][[1]];
  h  = FromCharacterCode[BinaryReadList[s, "Byte", hl]];
  descr   = First @ StringCases[h,
              "'descr':" ~~ Whitespace... ~~ "'" ~~ d:Except["'"].. ~~ "'" :> d, 1];
  fortran = StringContainsQ[h, "'fortran_order':" ~~ Whitespace... ~~ "True"];
  shape   = First @ StringCases[h,
              "'shape':" ~~ Whitespace... ~~ "(" ~~ sh:Except[")"]... ~~ ")" :> sh, 1];
  shape   = DeleteCases[ToExpression /@ StringSplit[shape, ","], Null];
  n = If[shape === {}, 1, Times @@ shape];
  Which[
    descr === "<f4", raw = BinaryReadList[s, "Real32",     n],
    descr === "<i4", raw = BinaryReadList[s, "Integer32",  n],
    StringMatchQ[descr, "<U" ~~ NumberString],
      (nc = ToExpression @ StringDrop[descr, 2];
       cb = BinaryReadList[s, "UnsignedInteger32", n nc];
       raw = Table[
         StringJoin[DeleteCases[FromCharacterCode /@ cb[[(k-1) nc + 1 ;; k nc]], "\000"]],
         {k, n}])];
  Close[s];
  If[fortran && Length[shape] > 1,
     raw = Flatten[Transpose[ArrayReshape[raw, Reverse[shape]]]]];
  Which[
    shape === {},        First[raw],
    Length[shape] == 1,  raw,
    True,                ArrayReshape[raw, shape]]];

mcpReadNPZ[path_String] := Module[{t = CreateDirectory[], out},
  ExtractArchive[path, t];
  out = AssociationMap[
     mcpReadNPY[FileNameJoin[{t, # <> ".npy"}]] &,
     FileBaseName /@ FileNames["*.npy", t]];
  DeleteDirectory[t, DeleteContents -> True];
  out];

(* ============================================================================
   CSV loaders + numeric coercion (used by mcpLoadData)
   ============================================================================ *)
parseRow[h_List, r_List] := AssociationThread[h,
  MapThread[
    If[StringQ[#1] && StringMatchQ[#1, NumberString], ToExpression[#1], #1] &,
    {r, h}]];

importTable[file_] := Module[{raw, h},
  raw = Import[file, "CSV"]; h = raw[[1]];
  parseRow[h, #] & /@ Rest[raw]];

coerceNumeric[rows_List, numericKeys_List] := rows /. (k_ -> v_) /;
  MemberQ[numericKeys, k] :> (k -> If[NumericQ[v], v, Quiet[ToExpression[v]]]);

(* ============================================================================
   Colour scales (the cartopy/matplotlib RdYlBu_r convention for temperature
   and a hand-tuned diverging scale centred on zero for anomalies)
   ============================================================================ *)
$rdYlBuRStops = {
   RGBColor[0.192,0.212,0.584], RGBColor[0.270,0.459,0.706],
   RGBColor[0.455,0.678,0.820], RGBColor[0.671,0.851,0.914],
   RGBColor[0.878,0.953,0.973], RGBColor[1.000,1.000,0.749],
   RGBColor[0.996,0.878,0.565], RGBColor[0.992,0.682,0.380],
   RGBColor[0.957,0.427,0.263], RGBColor[0.843,0.188,0.153],
   RGBColor[0.647,0.000,0.149]};
rdYlBuR        = Blend[$rdYlBuRStops, Clip[#, {0, 1}]] &;
rdYlBuRScaled[vmin_, vmax_] := Function[v, rdYlBuR[(v - vmin)/(vmax - vmin)]];

$divergingStops = {
   {-3.0, RGBColor[0.05,0.10,0.45]}, {-1.5, RGBColor[0.15,0.40,0.75]},
   {-0.5, RGBColor[0.55,0.75,0.92]}, { 0.0, RGBColor[0.97,0.97,0.95]},
   { 0.5, RGBColor[0.95,0.65,0.45]}, { 1.5, RGBColor[0.85,0.20,0.15]},
   { 3.0, RGBColor[0.45,0.05,0.10]}};
divergingCmap  = Blend[$divergingStops, Clip[#, {-3., 3.}]] &;
scaledDivergingCmap[vmax_] := Function[v, divergingCmap[3 v/vmax]];

(* ============================================================================
   mcpLoadData -- two forms: from-CSV (default) or from-Association (lets the
   notebook pass in the embedded data that's Uncompressed from the .nb).
   Both call deriveStats[] so the figure functions get the same shape input.
   ============================================================================ *)
(* Try both: the post-repo layout has data/ next to the .wl; the original
   WeatherMosaic build layout has it one level up at ../data. *)
defaultDataDir[] := With[
   {flat = FileNameJoin[{$mcpPackageDir, "data"}],
    nested = FileNameJoin[{$mcpPackageDir, "..", "data"}]},
   Which[
      DirectoryQ[flat],   flat,
      DirectoryQ[nested], nested,
      True,               flat]];
defaultCoastFile[] := FileNameJoin[{$mcpPackageDir, "coastlines_natural_earth.m"}];

deriveStats[summary_List, cities_List, coastlines_List] := Module[
  {cityCoords, variableList, cityList, absLatRmse, fit,
   bootSlopes, bootIntercepts, slopeCI, spearman, rmseMat,
   zMat, eigvals, eigvecs, varExplained, pcScores,
   cityCol, varCol, norm},
  cityCoords    = Association[#["city"] -> {#["lat"], #["lon"]} & /@ cities];
  variableList  = DeleteDuplicates[#["variable"] & /@ summary];
  cityList      = DeleteDuplicates[#["city"]     & /@ summary];
  absLatRmse = Table[{Abs[cityCoords[c][[1]]],
     First[Select[summary, #["city"]==c && #["variable"]=="T2m" &]]["rmse"]},
    {c, cityList}];
  fit = LinearModelFit[absLatRmse, x, x];
  SeedRandom[42];
  bootSlopes = Table[
     Coefficient[Normal[LinearModelFit[
        RandomChoice[absLatRmse, Length[absLatRmse]], x, x]], x], 2000];
  bootIntercepts = Table[
     LinearModelFit[RandomChoice[absLatRmse, Length[absLatRmse]], x, x][0], 2000];
  slopeCI  = Quantile[bootSlopes, {0.025, 0.975}];
  spearman = SpearmanRho @@ Transpose[absLatRmse];
  rmseMat = Table[
     First[Select[summary, #["city"]==c && #["variable"]==v &]]["rmse"],
     {c, cityList}, {v, variableList}];
  zMat = Transpose[Standardize /@ Transpose[rmseMat]];
  {eigvals, eigvecs} = Eigensystem[Covariance[zMat]];
  varExplained = N[eigvals/Total[eigvals]];
  pcScores     = zMat . Transpose[eigvecs[[1 ;; 2]]];
  cityCol = AssociationThread[cityList,
     Take[ColorData[97, "ColorList"], Length[cityList]]];
  varCol  = AssociationThread[variableList,
     Take[ColorData[97, "ColorList"], Length[variableList]]];
  norm = Association @ Table[
     v -> With[{rows = Select[summary, #["variable"]==v &]},
       Association @ Table[
         r["city"] -> r["rmse"]/Max[#["rmse"] & /@ rows], {r, rows}]],
     {v, variableList}];
  <|
   "summary"        -> summary,        "cities"        -> cities,
   "cityCoords"     -> cityCoords,     "cityList"      -> cityList,
   "variableList"   -> variableList,   "absLatRmse"    -> absLatRmse,
   "fit"            -> fit,            "slopeCI"       -> slopeCI,
   "bootSlopes"     -> bootSlopes,     "bootIntercepts"-> bootIntercepts,
   "spearman"       -> spearman,
   "pcScores"       -> pcScores,       "varExplained"  -> varExplained,
   "cityCol"        -> cityCol,        "varCol"        -> varCol,
   "norm"           -> norm,
   "coastlines"     -> coastlines|>];

Options[mcpLoadData] = {"DataDir" -> Automatic, "CoastlinesFile" -> Automatic};
mcpLoadData[OptionsPattern[]] := Module[
   {dataDir, coastFile, summary, cities, coastlines},
   dataDir   = OptionValue["DataDir"]       /. Automatic :> defaultDataDir[];
   coastFile = OptionValue["CoastlinesFile"] /. Automatic :> defaultCoastFile[];
   summary = coerceNumeric[
      importTable[FileNameJoin[{dataDir, "assessment_summary.csv"}]],
      {"bias","rmse","spread","spread_over_rmse"}];
   cities  = coerceNumeric[
      importTable[FileNameJoin[{dataDir, "cities.csv"}]], {"lat","lon"}];
   coastlines = If[FileExistsQ[coastFile], Get[coastFile], {}];
   deriveStats[summary, cities, coastlines]];

mcpLoadData[embedded_Association, OptionsPattern[]] := Module[
   {coastFile, coastlines, summary, cities},
   coastFile = OptionValue["CoastlinesFile"] /. Automatic :> defaultCoastFile[];
   coastlines = If[FileExistsQ[coastFile], Get[coastFile], {}];
   summary = coerceNumeric[embedded["summary"], {"bias","rmse","spread","spread_over_rmse"}];
   cities  = coerceNumeric[embedded["cities"],  {"lat","lon"}];
   deriveStats[summary, cities, coastlines]];

(* ============================================================================
   FIGURES 01-08 -- city statistics (no .npz needed; uses summary CSV)
   ============================================================================ *)

mcpFigGeo[data_Association] := Module[
  {cityList=data["cityList"], cityCoords=data["cityCoords"],
   summary=data["summary"], absLatRmse=data["absLatRmse"],
   coastLinesClean=data["coastlines"],
   rmseMin, rmseMax, t2mColor, t2mRMSEby, lats, lons,
   latLo, latHi, lonLo, lonHi, inWindow, windowedCoasts},
  {rmseMin, rmseMax} = MinMax[absLatRmse[[All,2]]];
  t2mColor[x_] := ColorData["TemperatureMap"][(x - rmseMin)/(rmseMax - rmseMin)];
  t2mRMSEby = Association @ Table[
     c -> First[Select[summary, #["city"]==c && #["variable"]=="T2m" &]]["rmse"],
     {c, cityList}];
  lats = #[[1]] & /@ Values[cityCoords];
  lons = #[[2]] & /@ Values[cityCoords];
  {latLo, latHi} = {Floor[Min[lats], 5] - 12, Ceiling[Max[lats], 5] + 12};
  {lonLo, lonHi} = {Floor[Min[lons], 5] - 18, Ceiling[Max[lons], 5] + 18};
  inWindow[line_] := With[{xs=line[[All,1]], ys=line[[All,2]]},
     Max[xs] >= lonLo && Min[xs] <= lonHi &&
     Max[ys] >= latLo && Min[ys] <= latHi];
  windowedCoasts = Select[coastLinesClean, inWindow];
  Graphics[{
    {RGBColor[0.85,0.92,0.97], Rectangle[{lonLo,latLo}, {lonHi,latHi}]},
    {Black, AbsoluteThickness[0.5], Line /@ windowedCoasts},
    {GrayLevel[0.7, 0.3], Thin,
       Line[{{lonLo, #}, {lonHi, #}}] & /@ Range[-90, 90, 15],
       Line[{{#, latLo}, {#, latHi}}] & /@ Range[-180, 180, 30]},
    Table[Module[{lat, lon, r},
       lat = cityCoords[c][[1]]; lon = cityCoords[c][[2]]; r = t2mRMSEby[c];
       {t2mColor[r], EdgeForm[Directive[Black, AbsoluteThickness[1.2]]],
        AbsolutePointSize[22], Point[{lon, lat}],
        Black, Text[Style[
           StringForm["``\n``\[Degree]C", c, NumberForm[r, {3,2}]],
           13, Bold, Background -> Directive[White, Opacity[0.85]]],
          {lon, lat}, {0, -1.7}]}],
      {c, cityList}]},
   PlotRange -> {{lonLo, lonHi}, {latLo, latHi}},
   AspectRatio -> (latHi - latLo)/(lonHi - lonLo), Frame -> True,
   FrameLabel -> {"Longitude (\[Degree])", "Latitude (\[Degree])"},
   Background -> White, ImageSize -> 1300,
   PlotLabel -> Style[
      "Mosaic 2 m T RMSE by city \[LongDash] 6 inits \[Times] 10-day forecasts, 2022\n\
disk colour = 10-day-averaged 2 m T RMSE (blue = best, red = worst)", 13]]];

mcpFigFit[data_Association] := Module[
  {absLatRmse=data["absLatRmse"], fit=data["fit"], cityList=data["cityList"],
   cityCoords=data["cityCoords"], bootIntercepts=data["bootIntercepts"],
   bootSlopes=data["bootSlopes"], slopeCI=data["slopeCI"], xs, band},
  xs = Range[30, 60, 0.5];
  band = Table[
     Module[{predictions = bootIntercepts + bootSlopes * xv},
       {xv, Quantile[predictions, 0.025], Quantile[predictions, 0.975]}],
     {xv, xs}];
  Show[
    ListPlot[{Transpose[{band[[All,1]], band[[All,2]]}],
              Transpose[{band[[All,1]], band[[All,3]]}]},
      Filling -> {1 -> {2}},
      FillingStyle -> Directive[GrayLevel[0.5], Opacity[0.18]],
      PlotStyle -> Directive[Opacity[0]]],
    Plot[fit[x], {x, 30, 60},
      PlotStyle -> Directive[Dashed, GrayLevel[0.3], Thickness[Medium]]],
    ListPlot[absLatRmse,
      PlotStyle -> Directive[AbsolutePointSize[10],
         RGBColor[0.85, 0.32, 0.21]]],
    Graphics[Table[Text[Style[c, 10, Bold],
       {Abs[cityCoords[c][[1]]] + 1.2,
        absLatRmse[[Position[cityList, c][[1, 1]], 2]] + 0.05}, {-1, 0}],
       {c, cityList}]],
    Frame -> True, GridLines -> Automatic,
    FrameLabel -> {"|latitude| (\[Degree])", "10-day T2m RMSE (\[Degree]C)"},
    PlotLabel -> Style[StringForm[
      "T2m RMSE vs |lat|: slope = `` \[Degree]C/\[Degree]lat  (95% bootstrap CI [``, ``])  R\.b2 = ``",
      NumberForm[Coefficient[Normal[fit], x], {3, 3}],
      NumberForm[slopeCI[[1]], {3, 3}],
      NumberForm[slopeCI[[2]], {3, 3}],
      NumberForm[fit["RSquared"], {3, 2}]], 11],
    ImageSize -> 700, PlotRange -> {{30, 60}, {0, 3}}]];

mcpFigCalib[data_Association] := Module[
  {summary=data["summary"], variableList=data["variableList"],
   varCol=data["varCol"], calibPoints},
  calibPoints = GroupBy[summary, #["variable"] &,
     Map[{#["rmse"], #["spread"]} &]];
  Show[
    Graphics[{Dashed, GrayLevel[0.6], Line[{{0,0},{7,7}}]}],
    Graphics[Text[Style["spread = RMSE\n(perfect calibration)", 9,
       GrayLevel[0.4]], {5.3, 6.1}, {0, -1}]],
    ListPlot[KeyValueMap[Tooltip[#2, #1] &, calibPoints],
      PlotStyle -> Table[Directive[AbsolutePointSize[8], varCol[v]],
        {v, variableList}],
      PlotLegends -> Placed[variableList, {0.85, 0.25}],
      Frame -> True, GridLines -> Automatic,
      FrameLabel -> {"RMSE (variable units)", "Ensemble spread"},
      PlotLabel -> Style[
        "Ensemble calibration \[LongDash] 6 cities \[Times] 6 variables", 12],
      AspectRatio -> 1, ImageSize -> 600, PlotRange -> All]]];

mcpFigPCA[data_Association] := Module[
  {cityList=data["cityList"], cityCol=data["cityCol"],
   pcScores=data["pcScores"], varExplained=data["varExplained"]},
  Graphics[{
     AbsolutePointSize[12], EdgeForm[Black],
     Table[{cityCol[cityList[[i]]], Point[pcScores[[i]]],
       Black, Text[Style[cityList[[i]], 11, Bold],
         pcScores[[i]], {-1.5, 0}]}, {i, Length[cityList]}]},
   Frame -> True, GridLines -> Automatic,
   FrameLabel -> {
     Style[StringForm["PC1 (`` % var)", NumberForm[100 varExplained[[1]], {3,1}]], 12],
     Style[StringForm["PC2 (`` % var)", NumberForm[100 varExplained[[2]], {3,1}]], 12]},
   PlotLabel -> Style[
     "Cities in the first two principal components of standardised skill", 12],
   ImageSize -> 700, AspectRatio -> 1]];

mcpFigHeat[data_Association] := Module[
  {variableList=data["variableList"], cityList=data["cityList"],
   norm=data["norm"], heat},
  heat = Table[norm[v][c], {v, variableList}, {c, cityList}];
  MatrixPlot[heat,
    ColorFunction -> "TemperatureMap", PlotLegends -> Automatic,
    FrameTicks -> {{Thread[{Range[Length[variableList]], variableList}], None},
                   {Thread[{Range[Length[cityList]],     cityList}], None}},
    PlotLabel -> Style["Normalised RMSE (per variable column)", 12],
    ImageSize -> 700]];

mcpFigBias[data_Association] := Module[
  {summary=data["summary"], cityList=data["cityList"]},
  BarChart[
    GroupBy[summary, #["variable"] &, Map[#["bias"] &]],
    ChartLabels  -> {Automatic, Placed[cityList, Center]},
    ChartLegends -> Placed[cityList, Right],
    Frame -> True, FrameLabel -> {None, "Bias (variable units)"},
    PlotLabel -> Style[
      "Per-(variable, city) bias \[LongDash] sign + magnitude", 12],
    ImageSize -> 900, Background -> White]];

mcpFigRadar[data_Association] := Module[
  {variableList=data["variableList"], cityList=data["cityList"],
   cityCol=data["cityCol"], norm=data["norm"],
   angles, buildFingerprint},
  angles = Table[2 Pi (k - 1)/Length[variableList],
     {k, Length[variableList]}];
  buildFingerprint[city_] := Module[{vals, pts},
    vals = Table[norm[v][city], {v, variableList}];
    pts = Table[{vals[[k]] Cos[Pi/2 - angles[[k]]],
                 vals[[k]] Sin[Pi/2 - angles[[k]]]},
      {k, Length[variableList]}];
    pts];
  Legended[
    Graphics[{
      {GrayLevel[0.85], Thin, Circle[{0,0}, #] & /@ {0.25, 0.5, 0.75, 1.0}},
      {GrayLevel[0.7], Thin,
        Line[{{0,0}, {1.05 Cos[Pi/2 - #], 1.05 Sin[Pi/2 - #]}}] & /@ angles},
      Table[Text[Style[variableList[[k]], 11, Bold],
         {1.18 Cos[Pi/2 - angles[[k]]], 1.18 Sin[Pi/2 - angles[[k]]]}],
       {k, Length[variableList]}],
      Table[{cityCol[city], Opacity[0.18],
         EdgeForm[Directive[cityCol[city], Thick, Opacity[1]]],
         Polygon[buildFingerprint[city]]}, {city, cityList}]},
      PlotRange -> 1.3 {{-1,1}, {-1,1}}, ImageSize -> 700,
      PlotLabel -> Style[
        "City skill fingerprints (normalised RMSE per variable; 0 = best)", 12]],
    Placed[SwatchLegend[Values[cityCol], cityList,
       LegendMarkerSize -> 15, LegendLabel -> Style["City", Bold]], Right]]];

(* ============================================================================
   Graceful "you need an .npz" notice. Each public function that takes an
   npzPath checks FileExistsQ first; if the path is the placeholder (or any
   non-existent file) we return this Pane instead of letting ExtractArchive
   blow up. That way "Evaluate Notebook" runs cleanly even before the reader
   has pointed npzPath at a real Mosaic forecast.
   ============================================================================ *)
needNpz[funcName_String, given_] := Pane[
  Column[{
    Style["Need a Mosaic .npz", Bold, FontSize -> 14,
       RGBColor[0.65, 0.1, 0.1]],
    Spacer[4],
    Row[{Style["Path tried:  ", Italic, GrayLevel[0.4]],
         Style[ToString[given], FontFamily -> "Courier",
            FontColor -> GrayLevel[0.25]]}],
    Spacer[2],
    Style[funcName <> " needs a Mosaic forecast .npz on local disk.",
       GrayLevel[0.2]],
    Style["Set npzPath at the top of the notebook to your file, then \
re-evaluate this cell.", GrayLevel[0.2]],
    Spacer[2],
    Style["(See section 2 of the post, or the repo README, for how to \
produce a .npz on Colab.)", Italic, FontSize -> 11, GrayLevel[0.45]]},
    Spacings -> 0.7],
  ImageMargins -> 6,
  FrameMargins -> 14,
  Background -> RGBColor[1.0, 0.97, 0.90]];

(* ============================================================================
   FIGURES 09-12 -- global temperature maps + Hovmoller (need a Mosaic .npz)
   ============================================================================ *)

mcpRenderGlobal[field2D_, title_, range_,
                colorSpec_:"TemperatureMap",
                legendLabel_:"2 m T (\[Degree]C)",
                gLon_, gLat_, coastlines_] := Module[
  {sortedLon, order, fr, vMin, vMax, cf, heatmap, coastPrim, coast},
  sortedLon = N @ If[# > 180, # - 360, #] & /@ gLon;
  order     = Ordering[sortedLon];
  fr        = Transpose[field2D][[All, order]];   (* (lat, lon) *)
  {vMin, vMax} = range;
  cf = If[StringQ[colorSpec],
     ColorData[{colorSpec, {vMin, vMax}}], colorSpec];
  heatmap = ArrayPlot[fr,
     ColorFunction -> cf, ColorFunctionScaling -> False,
     PlotRange    -> {vMin, vMax},
     DataRange    -> {{-180, 180}, {-90, 90}},
     DataReversed -> True,    (* gLat runs S->N; flip so row 1 sits at the bottom *)
     Frame -> True,
     FrameTicks -> {{Range[-90, 90, 30], None}, {Range[-180, 180, 60], None}},
     (* ArrayPlot FrameLabel uses {{bottom, top}, {left, right}} *)
     FrameLabel -> {{Style["Longitude (\[Degree])", 10], None},
                    {Style["Latitude (\[Degree])", 10], None}},
     PlotLegends -> BarLegend[{cf, {vMin, vMax}},
        LegendLabel -> legendLabel, LegendMarkerSize -> {12, 180}],
     AspectRatio -> 1/2, ImageSize -> 1400];
  coastPrim = {Black, AbsoluteThickness[0.55], Line /@ coastlines};
  coast = Graphics[coastPrim,
     PlotRange -> {{-180, 180}, {-90, 90}}, AspectRatio -> 1/2];
  Show[heatmap, coast,
     PlotLabel -> Style[title, 14, Bold], ImageSize -> 1400]];

(* Helper used by all .npz figures: load tensor + axes once, return Association. *)
loadGlobal[npzPath_String] := Module[{d, viT, lon, lat, mean, spread},
  d   = mcpReadNPZ[npzPath];
  viT = First @ First @ Position[d["variables"], "2m_temperature"];
  lon = N @ d["longitude"]; lat = N @ d["latitude"];
  mean   = Mean[d["forecasts"][[All, All, All, All, viT]]] - 273.15;   (* (steps, lon, lat) *)
  spread = StandardDeviation[d["forecasts"][[All, All, All, All, viT]]];
  <|"d" -> d, "viT" -> viT, "lon" -> lon, "lat" -> lat,
    "ensembleMean" -> mean, "ensembleSpread" -> spread|>];

(* default coastlines for the global figures: read from package dir *)
defaultCoastlines[] := If[FileExistsQ[defaultCoastFile[]],
   Get[defaultCoastFile[]], {}];

mcpFig3PanelGlobal[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFig3PanelGlobal", npzPath];
mcpFig3PanelGlobal[npzPath_String] := Module[
  {g = loadGlobal[npzPath], coast = defaultCoastlines[], panel},
  panel[d_] := mcpRenderGlobal[g["ensembleMean"][[d]],
     StringForm["Mosaic 2 m T ensemble mean \[LongDash] day `` (lead ``h)",
        d, d 24], {-35., 40.}, rdYlBuRScaled[-35., 40.],
     "2 m T (\[Degree]C)", g["lon"], g["lat"], coast];
  Column[{panel[1], panel[5], panel[10]},
     Spacings -> 0.3, Alignment -> Center]];

mcpFigGlobalSpread[npzPath_, day_Integer:5] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigGlobalSpread", npzPath];
mcpFigGlobalSpread[npzPath_String, day_Integer:5] := Module[
  {g = loadGlobal[npzPath], coast = defaultCoastlines[], sRange},
  sRange = {0, Quantile[Flatten[g["ensembleSpread"][[day]]], 0.99]};
  mcpRenderGlobal[g["ensembleSpread"][[day]],
     "Day " <> ToString[day] <>
       " \[Bullet] ensemble standard deviation of 2 m T (uncertainty map)",
     sRange, "SunsetColors", "\[Sigma] 2 m T (\[Degree]C)",
     g["lon"], g["lat"], coast]];

mcpFigGlobalAnomaly[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigGlobalAnomaly", npzPath];
mcpFigGlobalAnomaly[npzPath_String] := Module[
  {g = loadGlobal[npzPath], coast = defaultCoastlines[], anomaly, aMax},
  anomaly = g["ensembleMean"][[10]] - g["ensembleMean"][[1]];
  aMax    = Max[Abs[Flatten[anomaly]]];
  mcpRenderGlobal[anomaly,
     "Ensemble mean 2 m T anomaly (Day 10 minus Day 1)",
     {-aMax, aMax}, scaledDivergingCmap[aMax],
     "\[CapitalDelta] 2 m T (\[Degree]C)",
     g["lon"], g["lat"], coast]];

mcpFigHov50N[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigHov50N", npzPath];
mcpFigHov50N[npzPath_String] := Module[
  {g = loadGlobal[npzPath], i50, hov, sortedLon, order, hovSorted, hRange},
  i50 = First @ Ordering[Abs[g["lat"] - 50], 1];
  hov = g["ensembleMean"][[All, All, i50]];      (* (days, lon) *)
  sortedLon = N @ If[# > 180, # - 360, #] & /@ g["lon"];
  order     = Ordering[sortedLon];
  hovSorted = hov[[All, order]];
  hRange    = MinMax[Flatten[hovSorted]];
  ArrayPlot[Reverse @ hovSorted,
    ColorFunction -> ColorData[{"TemperatureMap", hRange}],
    ColorFunctionScaling -> False, PlotRange -> hRange,
    DataRange -> {{-180, 180}, {1, 10}},
    PlotLabel -> Style[
      "Hovm\[ODoubleDot]ller diagram \[Bullet] 2 m T at 50\[Degree]N", 13, Bold],
    Frame -> True,
    FrameLabel -> {{Style["Longitude (\[Degree])", 11], None},
                   {Style["Forecast day", 11], None}},
    FrameTicks -> {{Range[1, 10], None}, {Range[-180, 180, 60], None}},
    PlotLegends -> BarLegend[
       {ColorData[{"TemperatureMap", hRange}], hRange},
       LegendLabel -> "2 m T (\[Degree]C)", LegendMarkerSize -> {12, 200}],
    AspectRatio -> 0.6, ImageSize -> 1100]];

mcpAnimateGlobal[npzPath_, varName_String:"2m_temperature",
                 outGif_String:"global.gif"] /; !FileExistsQ[npzPath] :=
   needNpz["mcpAnimateGlobal", npzPath];
mcpAnimateGlobal[npzPath_String, varName_String:"2m_temperature",
                 outGif_String:"global.gif"] := Module[
  {d, vi, ens, lonArr, latArr, leadH, field, vMin, vMax, frames},
  d = mcpReadNPZ[npzPath];
  vi = First @ First @ Position[d["variables"], varName];
  ens = Mean[d["forecasts"]];                    (* (steps, lon, lat, channels) *)
  field = ens[[All, All, All, vi]] -
     If[StringContainsQ[varName, "temperature"], 273.15, 0];
  lonArr = d["longitude"]; latArr = d["latitude"];
  leadH = d["lead_time_hours"];
  {vMin, vMax} = Quantile[Flatten[field], {0.01, 0.99}];
  frames = Table[Module[{f, order},
     f = Transpose[field[[i]]];
     order = Ordering[N @ If[# > 180, # - 360, #] & /@ lonArr];
     ArrayPlot[f[[All, order]],
       ColorFunction -> ColorData[{"TemperatureMap", {vMin, vMax}}],
       ColorFunctionScaling -> False, PlotRange -> {vMin, vMax},
       DataRange -> {{-180, 180}, {-90, 90}},
       PlotLabel -> StringForm["`` \[LongDash] Day `` (lead = `` h)",
          varName, i, leadH[[i]]],
       FrameLabel -> {{"Longitude (\[Degree])", None}, {"Latitude (\[Degree])", None}},
       AspectRatio -> 1/2, ImageSize -> 700,
       PlotLegends -> BarLegend[
          {ColorData[{"TemperatureMap", {vMin, vMax}}], {vMin, vMax}}]]],
     {i, Length[field]}];
  Export[outGif, frames,
     "AnimationRepetitions" -> Infinity, "DisplayDurations" -> 0.6];
  frames];

mcpAnimateEnsembleMean[npzPath_, outGif_String:"global.gif"] /;
   !FileExistsQ[npzPath] :=
   needNpz["mcpAnimateEnsembleMean", npzPath];
mcpAnimateEnsembleMean[npzPath_String, outGif_String:"global.gif"] := Module[
  {g = loadGlobal[npzPath], coast = defaultCoastlines[], frames},
  frames = Table[mcpRenderGlobal[g["ensembleMean"][[d]],
     StringForm["Day `` \[Bullet] ensemble mean 2 m T", d],
     {-35., 40.}, rdYlBuRScaled[-35., 40.], "2 m T (\[Degree]C)",
     g["lon"], g["lat"], coast],
    {d, Length[g["ensembleMean"]]}];
  Export[outGif, frames,
     "AnimationRepetitions" -> Infinity, "DisplayDurations" -> 0.7];
  frames];

(* ============================================================================
   FIGURES 13-18 -- per-cell + ensemble-skill analyses (need a Mosaic .npz
   saved with truth: with_truth=True)
   ============================================================================ *)

loadGlobalWithTruth[npzPath_String] := Module[
  {d, viT, lon, lat, leadH, fc, tr, nMem, nStep, nLat, validDates},
  d = mcpReadNPZ[npzPath];
  viT = First @ First @ Position[d["variables"], "2m_temperature"];
  lon = N @ d["longitude"]; lat = N @ d["latitude"];
  leadH = d["lead_time_hours"];
  fc = d["forecasts"]; tr = d["truth"];
  {nMem, nStep} = Dimensions[fc][[1 ;; 2]];
  nLat = Length[lat];
  validDates = Table[DatePlus[DateObject[{2022, 8, 15, 0, 0}],
     {leadH[[t]], "Hour"}], {t, nStep}];
  <|"d" -> d, "viT" -> viT, "lon" -> lon, "lat" -> lat,
    "leadH" -> leadH, "fc" -> fc, "tr" -> tr,
    "nMem" -> nMem, "nStep" -> nStep, "nLat" -> nLat,
    "validDates" -> validDates|>];

nearestIdx[arr_, x_] := First @ Ordering[Abs[arr - x], 1];

mcpFigAberdeenCompare[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigAberdeenCompare", npzPath];
mcpFigAberdeenCompare[npzPath_String] := Module[
  {g = loadGlobalWithTruth[npzPath], li, lj, abMembers, abMean, abTruth,
   obs, obsPts, memberSeries, seriesAll, n2, n3, nMem, viT},
  nMem = g["nMem"]; viT = g["viT"];
  li = nearestIdx[g["lon"], Mod[-2.10, 360]];      (* Aberdeen *)
  lj = nearestIdx[g["lat"],  57.15];
  abMembers = g["fc"][[All, All, li, lj, viT]] - 273.15;
  abMean    = Mean[abMembers];
  abTruth   = g["tr"][[All, li, lj, viT]] - 273.15;
  obs = Quiet @ Check[WeatherData["Aberdeen", "Temperature",
       {{2022,8,16,0,0}, {2022,8,25,0,0}, "Day"}], $Failed];
  obsPts = If[Head[obs] === TemporalData,
     Transpose[{obs["Dates"], QuantityMagnitude[obs["Values"]]}], {}];
  memberSeries = Table[Transpose[{g["validDates"], abMembers[[m]]}], {m, nMem}];
  seriesAll = Join[memberSeries,
     {Transpose[{g["validDates"], abMean}],
      Transpose[{g["validDates"], abTruth}]},
     If[obsPts === {}, {}, {obsPts}]];
  n3 = If[obsPts === {}, 0, 1];
  DateListPlot[seriesAll,
    Joined -> Join[ConstantArray[True, nMem], {True, True},
       If[obsPts === {}, {}, {False}]],
    PlotStyle -> Join[
       ConstantArray[Directive[GrayLevel[0.7],
          AbsoluteThickness[0.6], Opacity[0.5]], nMem],
       {Directive[RGBColor[0.1, 0.3, 0.85], AbsoluteThickness[2.5]],
        Directive[Black, AbsoluteThickness[2], Dashing[{6, 4}]]},
       If[obsPts === {}, {},
          {Directive[RGBColor[0.85, 0.15, 0.15], AbsolutePointSize[7]]}]],
    PlotMarkers -> Join[ConstantArray[None, nMem + 2],
       If[obsPts === {}, {}, {Automatic}]],
    PlotLegends -> Placed[LineLegend[
       {RGBColor[0.1,0.3,0.85], Black, RGBColor[0.85,0.15,0.15], GrayLevel[0.7]},
       {"Mosaic ensemble mean", "ERA5 truth",
        "Observed (WeatherData)", "16 members"}], Below],
    FrameLabel -> {"Valid date (2022)", "2 m temperature (\[Degree]C)"},
    PlotLabel -> "Aberdeen 2 m T \[LongDash] Mosaic forecast vs ERA5 truth vs station observations",
    GridLines -> Automatic, Frame -> True, ImageSize -> 760]];

$cityCoordsDefault = {
   "Aberdeen" -> {57.15, -2.10}, "London"   -> {51.51, -0.13},
   "Berlin"   -> {52.52, 13.40}, "New York" -> {40.71, -74.00},
   "Phoenix"  -> {33.45,-112.07}, "Tokyo"   -> {35.68, 139.65}};

mcpFigSkillVsLead[npzPath_, cities_:$cityCoordsDefault] /;
   !FileExistsQ[npzPath] := needNpz["mcpFigSkillVsLead", npzPath];
mcpFigSkillVsLead[npzPath_String, cities_:$cityCoordsDefault] := Module[
  {g = loadGlobalWithTruth[npzPath], cityNames, cityCol, leadDays, err, viT},
  viT = g["viT"];
  cityNames = cities[[All, 1]];
  cityCol = AssociationThread[cityNames,
     Take[ColorData[97, "ColorList"], Length[cityNames]]];
  leadDays = Range[g["nStep"]];
  err[ll_] := Module[{ij},
     ij = {nearestIdx[g["lon"], Mod[ll[[2]], 360]],
           nearestIdx[g["lat"], ll[[1]]]};
     Abs[Mean[g["fc"][[All, All, ij[[1]], ij[[2]], viT]]] -
         g["tr"][[All, ij[[1]], ij[[2]], viT]]]];
  ListLinePlot[
    Table[Transpose[{leadDays, err[c[[2]]]}], {c, cities}],
    PlotStyle -> (cityCol /@ cityNames), PlotMarkers -> Automatic,
    PlotLegends -> cityNames,
    FrameLabel -> {"Lead time (days)", "Ensemble-mean |error| (\[Degree]C)"},
    PlotLabel -> "Per-city 2 m T error vs lead time (init 2022-08-15)",
    GridLines -> Automatic, Frame -> True, ImageSize -> 760]];

mcpFigCrpsVsLead[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigCrpsVsLead", npzPath];
mcpFigCrpsVsLead[npzPath_String] := Module[
  {g = loadGlobalWithTruth[npzPath], nMem, nStep, viT, crpsLead},
  nMem = g["nMem"]; nStep = g["nStep"]; viT = g["viT"];
  crpsLead = Table[
     Module[{ensF, truthF, t1, pair, gN},
       ensF   = Flatten /@ (g["fc"][[All, t, All, All, viT]]);
       truthF = Flatten[g["tr"][[t, All, All, viT]]];
       gN = Length[truthF];
       t1 = Mean[Flatten[Abs[ensF - ConstantArray[truthF, nMem]]]];
       pair = Sum[Total[Abs[ensF[[i]] - ensF[[j]]]],
                  {i, nMem}, {j, nMem}];
       t1 - pair/(2 nMem^2 gN)],
     {t, nStep}];
  ListLinePlot[Transpose[{Range[nStep], crpsLead}],
    PlotStyle -> Directive[RGBColor[0.2,0.5,0.3], AbsoluteThickness[2.5]],
    PlotMarkers -> Automatic, Filling -> Axis,
    FrameLabel -> {"Lead time (days)", "CRPS (\[Degree]C)"},
    PlotLabel -> "Global-mean CRPS of 2 m T ensemble vs lead time",
    GridLines -> Automatic, Frame -> True, ImageSize -> 760]];

mcpFigSkillPersistence[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigSkillPersistence", npzPath];
mcpFigSkillPersistence[npzPath_String] := Module[
  {g = loadGlobalWithTruth[npzPath], nStep, viT, rmseGrid, ensMeanT,
   truthDay1, ssLead},
  nStep = g["nStep"]; viT = g["viT"];
  rmseGrid[a_, b_] := Sqrt[Mean[Flatten[(a - b)^2]]];
  ensMeanT  = Table[Mean[g["fc"][[All, t, All, All, viT]]], {t, nStep}];
  truthDay1 = g["tr"][[1, All, All, viT]];
  ssLead = Table[
     1 - rmseGrid[ensMeanT[[t]], g["tr"][[t, All, All, viT]]] /
         rmseGrid[truthDay1,     g["tr"][[t, All, All, viT]]],
     {t, 2, nStep}];
  ListLinePlot[Transpose[{Range[2, nStep], ssLead}],
    PlotStyle -> Directive[RGBColor[0.6,0.2,0.5], AbsoluteThickness[2.5]],
    PlotMarkers -> Automatic,
    PlotRange -> {All, {Min[0, Min[ssLead]] - 0.05, 1}},
    Epilog -> {Gray, Dashed, Line[{{2, 0}, {nStep, 0}}]},
    FrameLabel -> {"Lead time (days)", "Skill score vs persistence"},
    PlotLabel -> "2 m T skill score over day-1 persistence (positive = beats persistence)",
    GridLines -> Automatic, Frame -> True, ImageSize -> 760]];

mcpFigRankHistogram[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigRankHistogram", npzPath];
mcpFigRankHistogram[npzPath_String] := Module[
  {g = loadGlobalWithTruth[npzPath], nMem, nStep, viT, ranks},
  nMem = g["nMem"]; nStep = g["nStep"]; viT = g["viT"];
  ranks = Flatten @ Table[
     Module[{ensF, truthF},
       ensF   = Flatten /@ (g["fc"][[All, t, All, All, viT]]);
       truthF = Flatten[g["tr"][[t, All, All, viT]]];
       1 + Total[UnitStep[
          ConstantArray[truthF, nMem] - ensF]]],
     {t, nStep}];
  Histogram[ranks, {0.5, nMem + 1.5, 1},
    ChartStyle -> RGBColor[0.27, 0.46, 0.71], Frame -> True,
    FrameLabel -> {"Rank of truth among 16 members (1..17)", "Frequency"},
    PlotLabel  -> "Rank histogram (Talagrand) \[LongDash] U-shape = under-dispersive",
    ImageSize  -> 760]];

mcpFigHovLatLead[npzPath_] /; !FileExistsQ[npzPath] :=
   needNpz["mcpFigHovLatLead", npzPath];
mcpFigHovLatLead[npzPath_String] := Module[
  {g = loadGlobalWithTruth[npzPath], nStep, nLat, viT,
   ensMeanT, errLatTime, hovMat},
  nStep = g["nStep"]; nLat = g["nLat"]; viT = g["viT"];
  ensMeanT = Table[Mean[g["fc"][[All, t, All, All, viT]]], {t, nStep}];
  errLatTime = Table[
     Sqrt[Mean[(ensMeanT[[t]][[All, j]] - g["tr"][[t, All, j, viT]])^2]],
     {t, nStep}, {j, nLat}];
  hovMat = Reverse @ Transpose[errLatTime];   (* rows = lat, +90 at top *)
  ArrayPlot[hovMat,
    DataRange -> {{1, nStep}, {-90, 90}}, ColorFunction -> "TemperatureMap",
    AspectRatio -> 1/1.6, Frame -> True,
    (* ArrayPlot FrameLabel uses {{bottom, top}, {left, right}} *)
    FrameLabel -> {{"Lead time (days)", None}, {"Latitude (\[Degree])", None}},
    FrameTicks -> {{{{-90,"-90"},{-45,"-45"},{0,"0"},{45,"45"},{90,"90"}}, None},
                   {Range[1, nStep], None}},
    PlotLegends -> BarLegend[Automatic, LegendLabel -> "RMSE (\[Degree]C)"],
    PlotLabel -> "2 m T ensemble-mean RMSE by latitude \[Times] lead (Hovm\[ODoubleDot]ller)",
    ImageSize -> 780]];

End[];   (* `Private` *)
EndPackage[];
