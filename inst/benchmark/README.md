# IndexedUnits vs mixed_units

This benchmark compares the current prototype with `units::mixed_units`.

Cases investigated:

- **Vector size and unit diversity:** 100, 1,000, and 10,000 elements with 1, 2, or 8 unit types.
- **Unit distribution:** shuffled units, contiguous groups, and a skewed distribution where one unit dominates.
- **Construction and storage:** creating vectors from values and unit labels, and measuring retained memory.
- **Vector operations:** slicing, repetition, replacing 1% of entries, and concatenating vectors with overlapping unit dictionaries.
- **Arithmetic:** scalar multiplication, addition with and without conversion, and multiplication across different unit pairs.
- **Pipelines:** row binding, filtering with arithmetic in `mutate()`, and long/wide pivot round trips.
- **Missing values:** a sparse pivot followed by printing, checked separately from timings.

Current findings (10,000 elements, two balanced unit types):

- **Much smaller storage and faster arithmetic:** about 48× less retained memory; addition with conversion was about 19× faster and scalar multiplication about 780× faster.
- **Benefits vary by operation:** pivots and row binding were roughly twice as fast, replacement was modestly faster, and concatenation was similar.
- **Some behavior differs:** with `units` 1.0.1, repetition loses the `mixed_units` class and a sparse pivot fails when printed. These are not counted as speedups.

Results are exploratory medians of 3–5 warm-process iterations, including garbage collection. Values and unit labels are checked before timing. Fixtures are prepared outside timings except for construction; retained memory and temporary allocations are measured separately. This run includes dictionary-level remapping and arithmetic grouped by integer unit IDs.

To reproduce, install `bench`, `lobstr`, `pkgload`, `dplyr`, and `tidyr`, then run from the package root:

```sh
Rscript inst/benchmark/run.R
```

The script overwrites [raw results](results/) in one fixed location. These include timings, allocations, object sizes, individual iterations, correctness checks, and [session details](results/session.txt). The script documents the attribute-size workaround used with `lobstr` on this R version.
