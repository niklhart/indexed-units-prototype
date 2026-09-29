# IndexedUnits vs mixed_units

This benchmark compares the current prototype with `units::mixed_units`.
The current run uses GitHub `units` **1.0-1.6**, revision
[`a823fef`](https://github.com/r-quantities/units/commit/a823fef46d92ee4e1b2e2fa28ddf4c19d67cefb6), pinned in `renv.lock`.

Cases investigated:

- **Vector size and unit diversity:** 100, 1,000, and 10,000 elements with 1, 2, or 8 unit types.
- **Unit distribution:** shuffled units, contiguous groups, and a skewed distribution where one unit dominates.
- **Construction and storage:** creating vectors from values and unit labels, and measuring retained memory.
- **Vector operations:** slicing, repetition, replacing 1% of entries, and concatenating vectors with overlapping unit dictionaries.
- **Arithmetic:** scalar multiplication, addition with and without conversion, and multiplication across different unit pairs.
- **Explicit conversion:** `set_units()` on `mixed_units`, checked against conversions of homogeneous `units` vectors. Only `mixed_units` is timed here because `IndexedUnits` has no conversion API.
- **Pipelines:** row binding, filtering with arithmetic in `mutate()`, and long/wide pivot round trips.
- **Missing values:** a sparse pivot followed by printing, checked separately from timings.

Current findings (10,000 elements, two balanced unit types):

- **Much smaller storage and faster arithmetic:** about 15× less retained memory; addition with conversion was about 800× faster and scalar multiplication about 970× faster.
- **Factor proxies recover pipeline performance:** compared with the previous character proxy, row binding fell from 1.17 to 0.45 ms and pivots from 6.40 to 3.86 ms. Both are faster than `mixed_units` again (0.72 and 5.01 ms). Slicing and concatenation remain slower.
- **Less reported allocation:** row binding fell from 3.81 to 1.36 MB and pivots from 12.19 to 5.64 MB. These are profiler-reported allocations, not total memory use; small-object allocations are undercounted, favoring `mixed_units`.
- **Some behavior differs:** repetition still loses the `mixed_units` class and a sparse pivot fails when printed. These are not counted as speedups.

Results are exploratory medians of 3–5 warm-process iterations, including garbage collection. Values and unit labels are checked before timing. Fixtures are prepared outside timings except for construction; retained memory and temporary allocations are measured separately. This run uses integer IDs with factor levels during reshaping, retaining dictionaries for nonempty unknown-unit buffers and internal prototypes. Small timing differences should be treated cautiously given the few iterations.

The runtime figure shows the two-unit, balanced/shuffled cases. The memory figure's top row shows retained object size for 1, 2, and 8 unit types; the remaining panels show profiler-reported allocations per operation with two unit types. These allocations are not peak memory. Each panel has its own logarithmic scale. The full grid is in the raw results.

![Runtime comparison, including explicit unit conversion](results/runtime.png)

![Retained object size and allocation comparison](results/memory.png)

To reproduce, run from the package root (see the [project README](../../README.md) for the UDUNITS system dependency):

```sh
Rscript -e 'renv::restore()'
Rscript inst/benchmark/run.R
```

The script overwrites [raw results](results/) in one fixed location. These include timings, allocations, object sizes, individual iterations, correctness checks, and [session details](results/session.txt). The script documents the attribute-size workaround used with `lobstr` on this R version.
