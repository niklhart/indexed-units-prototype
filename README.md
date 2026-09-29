# IndexedUnits: a representation proposal for mixed units

This prototype explores an alternative representation for `units::mixed_units`,
intended for discussion with the `units` package authors. It stores a numeric
vector with two attributes: an integer unit ID per element and a dictionary of
distinct units. This avoids allocating a separate `units` object for every value.

- **Compact storage:** most useful for long vectors containing few distinct units.
- **Grouped arithmetic:** values sharing a unit pair are processed together through
  `units`, retaining its conversion and dimensional rules.
- **Pipeline support:** vctrs methods preserve values and units through row binding
  and tidyr pivots, including missing elements, without scalar list-columns.

```r
x <- indexed_units(c(1, 2, 3), c("mg", "L", "mg"))
x * 2
data.frame(value = x)
```

Against GitHub `units` 1.0-1.6, the benchmark case with 10,000 elements and two
unit types used about **15× less retained memory** and showed large arithmetic
speedups. Factor proxies also make row binding and pivots faster in this case;
slicing and concatenation remain slower. Allocation measurements undercount small
objects and should not be interpreted as total memory use. See the
[benchmark summary and figures](inst/benchmark/README.md) for checked results
and measurement limitations.

This is a representation prototype, not a drop-in replacement. Explicit unit
conversion and full integration with the `units` API remain outside its current
scope.

To reproduce, run `renv::restore()` from the project root, then
`Rscript inst/benchmark/run.R`. The lockfile pins the GitHub revision of `units`.
Building it requires UDUNITS (`brew install udunits` on macOS or
`libudunits2-dev` on Debian/Ubuntu).
