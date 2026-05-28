# AI weather forecasts without a supercomputer

Companion repo for the Wolfram Community post **"AI weather forecasts without a supercomputer"** by Marco Thiel. The post takes you from a free, open-source AI weather model (Mosaic, ICML 2026) to a 16-member 10-day probabilistic ensemble forecast, with the whole analysis done in Wolfram Language.

This repo contains only the **post bundle** — the notebook, a companion Wolfram Language package, the city/coastline data, and pre-rendered figures. The Mosaic model itself, including the Python code and the model weights, lives upstream and is **not** reposted here:

- **Mosaic model + code**: https://github.com/maxxxzdn/mosaic
- **Mosaic model weights**: https://huggingface.co/maxxxzdn/mosaic

## Just want to read the post?

1. Click the green **"Code"** button at the top right → **"Download ZIP"**.
2. Unzip it. You'll get a folder called `mosaic-at-home-main`.
3. Open `mosaic_community.nb` in **Mathematica** or the free **Wolfram Player** (https://www.wolfram.com/player/).
4. That's it — the notebook is self-contained. Every figure is embedded, the 10-day animation plays automatically, the 36-row data table is embedded, and the text reads top-to-bottom like a blog post.

You do **not** need to install anything else, run any Python, or talk to a GPU just to read the post.

## What's in the bundle

| File / folder | What it is | When you need it |
| --- | --- | --- |
| `mosaic_community.nb` | The post (7.9 MB, Mathematica notebook) | Always — this is the post. |
| `mosaic_community_post.md` | Markdown source of the post | If you want to read it as plain text or contribute edits. |
| `mosaic_community_plots.wl` | Wolfram Language package: one function per embedded figure | Loaded by the notebook to re-render figures. |
| `coastlines_natural_earth.m` | Natural Earth 1:110 m coastlines (134 lines) | Loaded automatically by the package for the global maps. |
| `data/` | `assessment_summary.csv` + `cities.csv` | Both are also embedded inside the `.nb`, so you don't normally need to touch them. |
| `figures/` | Pre-rendered PNGs (figs 01–18) + the animation GIF | Same — already embedded in the `.nb`. Useful if you just want to grab an image. |

## Want to run it on your own forecast?

The static city-statistics figures (figs 01–08) work straight from the embedded data — just open the notebook and they're already there.

The **global maps** (§9), **animation**, and **skill curves** (§10.3, §12) were generated from a real Mosaic forecast. To re-render them against a different forecast — your own date, your own initial condition — you need a Mosaic `.npz` file on your local disk.

Here is the full path from zero to a re-rendered figure, for someone who has never used GitHub or Colab before:

### Step 1 — Get Mosaic running on Google Colab

This is the only step that needs a GPU. **It will not work on the free Colab tier** (the T4 GPU does not support the `flash-attn` kernel Mosaic depends on). You need either:

- **Colab Pro** (about $10/month) — gives you L4, sometimes A100 GPUs. The minimum that works.
- **Colab Pro+** (about $50/month) — better A100 / H100 availability. What we used.
- **Or your own A100 / H100 machine**, if you have one.

1. Open the upstream Mosaic repo: https://github.com/maxxxzdn/mosaic
2. Follow its README to get the model running in Colab. The post's **§2 "Practical setup"** walks through the surprises (the 12-hour `flash-attn` build, the Drive caching gotchas, the `TORCH_CUDA_ARCH_LIST` flag).

### Step 2 — Save a forecast as a `.npz` file

When you run Mosaic, save the output with both the forecast **and** the truth ("with_truth=True"), then download the resulting `.npz` to your computer. A typical file is about 95 MB (16 members × 10 days × 240 × 121 grid × 82 channels + matching truth).

### Step 3 — Tell the notebook where the file is

1. Open `mosaic_community.nb` in Mathematica.
2. Find the cell near the top that defines `npzPath`. It looks like this:
   ```mathematica
   npzPath = "/path/to/your/forecast.npz";
   ```
3. Replace the placeholder string with the actual path to your `.npz` file.
4. Evaluate that cell, then any of the one-line figure cells below it — for example:
   ```mathematica
   mcpFig3PanelGlobal[npzPath]
   ```
   will produce the day-1 / day-5 / day-10 global temperature panels, this time from **your** forecast.

The notebook's `Get[FileNameJoin[{NotebookDirectory[], "mosaic_community_plots.wl"}]]` line picks up the companion package automatically as long as the `.wl` file sits next to the `.nb` (it does, in this repo).

## What if I only have a free-tier Colab?

You can still **read** the post and look at the embedded figures. You just can't re-run the model. Everything else in the notebook — the statistics, the calibration analysis, the PCA, the figures from the embedded summary table, the WeatherData comparison — runs **locally in Mathematica or Wolfram Player**, no GPU required.

## License

This repo's contents are released under two licenses:

- **Code** (`mosaic_community_plots.wl`, `coastlines_natural_earth.m`): **MIT** — see [`LICENSE-MIT`](LICENSE-MIT).
- **Post and prose** (`mosaic_community.nb`, `mosaic_community_post.md`, the figures): **CC-BY-4.0** — see [`LICENSE-CC-BY-4.0`](LICENSE-CC-BY-4.0).

The upstream Mosaic model is **CC-BY-NC-4.0** by Zhdanov, Lucic, Welling, van de Meent — that license applies to anything you do with the model itself; see https://github.com/maxxxzdn/mosaic. This repo does not redistribute Mosaic.

## Credits

- **Mosaic**: M. Zhdanov, A. Lucic, M. Welling, J.W. van de Meent — *(Sparse) Attention to the Details: Preserving Spectral Fidelity in ML-based Weather Forecasting Models*, ICML 2026, arXiv:2604.16429.
- **WeatherBench2** (initial conditions + ERA5 truth): S. Rasp et al., 2023.
- **Natural Earth** coastlines, public domain (https://www.naturalearthdata.com/).
- **Wolfram Language** for the analyses, statistics, figures, and animation.

## Post URL

The Wolfram Community post will be linked here once it is live.
