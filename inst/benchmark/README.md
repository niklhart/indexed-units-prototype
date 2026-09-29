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
- **Pipelines:** row binding, filtering with arithmetic in `mutate()`, and long/wide pivot round trips.
- **Missing values:** a sparse pivot followed by printing, checked separately from timings.

Current findings (10,000 elements, two balanced unit types):

- **Much smaller storage and faster arithmetic:** about 15× less retained memory; addition with conversion was about 810× faster and scalar multiplication about 850× faster.
- **Benefits vary by operation:** pivots, row binding, and replacement were faster, while concatenation was slightly slower.
- **Some behavior differs:** repetition still loses the `mixed_units` class and a sparse pivot fails when printed. These are not counted as speedups.

Results are exploratory medians of 3–5 warm-process iterations, including garbage collection. Values and unit labels are checked before timing. Fixtures are prepared outside timings except for construction; retained memory and temporary allocations are measured separately. This run includes dictionary-level remapping and arithmetic grouped by integer unit IDs.

To reproduce, run from the package root (see the [project README](../../README.md) for the UDUNITS system dependency):

```sh
Rscript -e 'renv::restore()'
Rscript inst/benchmark/run.R
```

The script overwrites [raw results](results/) in one fixed location. These include timings, allocations, object sizes, individual iterations, correctness checks, and [session details](results/session.txt). The script documents the attribute-size workaround used with `lobstr` on this R version.
