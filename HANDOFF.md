# Handoff: redesigning `mixed_units` in a `units` fork

## Objective and agreed constraint

Implement a dictionary-based `mixed_units` representation in the user's existing
`units` fork, on its dedicated development branch. Main was left unchanged and
should serve as the baseline. The fork path and branch name are not recorded here.

**Conversions must use `set_units()`, dispatching on an ordinary homogeneous
`units` vector to the unchanged `set_units.units` method.**
`set_units.mixed_units` may be redesigned. Do not bypass this requirement with
`ud_convert`, custom conversion factors, or a rewritten `set_units.units`.
Other maintainer feedback should be supplied separately; this document does not
imply approval for other public API changes.

This requirement needs a conversion method that the prototype does not yet have;
it does not inherently require abandoning the dictionary representation.

## Reference implementation

Reference repository: `indexedunits`, commit
`5ae1c2a90e5c392b9eecf5bade3153b89103bc29` (before this handoff).
Local path: `/Users/niklashartung/work/Forschung/Projekte/PBPK Toolbox/R/indexedunits`.

- [Implementation](R/IndexedUnits.R): constructors, dictionary remapping,
  grouped arithmetic, subsetting, replacement, and vctrs methods.
- [Regression tests](tests/testthat/test-indexed-units.R): scalar behavior,
  reordered dictionaries, missing buffers, and pivot round trips.
- [Benchmark script](inst/benchmark/run.R), [summary](inst/benchmark/README.md),
  and [raw results](inst/benchmark/results/).
- [renv lockfile](renv.lock): reproducible prototype dependencies.

Use these as references, not as a replacement for the fork's own API, tests, or
package configuration. The prototype is an independent `IndexedUnits` class;
the target is the existing `mixed_units` class.

## Representation and algorithms

The prototype stores doubles with a parallel integer `unit_id` attribute and a
`unit_dictionary` of distinct canonical unit labels. IDs index the dictionary;
unknown units have `NA_integer_` IDs and must have missing numeric values.
A missing numeric value with a known unit is a different case.

Match dictionaries and remap integer IDs when combining objects. Avoid expanding
labels to a character vector of length n in ordinary processing. Canonicalize
only distinct unit labels, merging aliases that resolve to the same unit.
The fork may choose existing symbolic-unit objects as dictionary entries if
that better preserves `units` semantics; character labels are a prototype choice.

Arithmetic groups elements by observed operand unit-ID pairs, builds homogeneous
`units` vectors for each group, delegates arithmetic to `units`, and scatters
results back into their original positions. The result dictionary is assembled
from group-level unit metadata. Cost depends on observed pairs, not just length:
eight unit types can produce 64 pairs in multiplication.

## Adding compatible unit conversion

Implement `set_units.mixed_units` around source/target unit pairs:

1. Validate and normalize the requested targets using the existing public
   contract. Inspect the fork's method and tests for recycling, accepted target
   representations, `mode`, names, empty inputs, and errors; do not infer these
   from the prototype.
2. Build a target dictionary and target IDs. Group indices by **both** source
   ID and target ID: values with the same source can request different targets.
3. For each group, construct an ordinary homogeneous `units` vector carrying
   the source unit, then call `set_units()` with that vector and the target unit.
   This second call must dispatch to the unchanged `set_units.units`.
4. Collect the converted numeric values and returned unit metadata, scatter to
   the original positions, and build/remap the output dictionary. Preserve names
   and applicable missing-value behavior.

Conceptual group operation, for character labels already normalized by the method:

```r
source <- set_units(values[index], source_label, mode = "standard")
converted <- set_units(source, target_label, mode = "standard")
# source is an ordinary units vector; the second call uses set_units.units.
```

The first call attaches the source unit to bare numbers; it is not a conversion
from a source unit. Attaching the target directly to bare numbers would silently
relabel values instead of converting them. Obtain output metadata from the
returned object rather than assuming the target spelling is canonical.

Do not compute a scale factor from a single converted value: affine conversions
such as temperatures require offsets too. Delegating the actual group values to
`set_units.units` preserves its conversion rules and errors. Resolve unknown-unit
conversion policy against the upstream contract rather than inventing units for
missing values.

Test same-unit conversions, multiple source/target pairs, scalar and per-element
targets where supported, aliases, incompatible dimensions, offset conversions,
known-unit missing values, names, and empty inputs. Compare with the unchanged
baseline and ordinary `units` conversions. Verify dispatch to `set_units.units`
and that its implementation remains unchanged.

## Reshaping and dictionary cleanup: tested pitfalls

The vctrs proxy is a data frame of numeric values and a **factor** whose integer
codes are unit IDs and whose levels are the dictionary. Construct it directly
from codes/levels; do not create a full character vector first. Restore from its
codes and levels, then compact the dictionary.

Unused entries are removed from ordinary subsets/results, including empty slices.
Two exceptions retain dictionary metadata:

- Nonempty vectors whose unit IDs are entirely unknown: these can be destination
  buffers that reshaping initializes before assigning values.
- Internal type prototypes (`vec_ptype`, `vec_ptype2`): these have no values but
  describe available unit types for casting and combining.

Cleaning all-missing buffers erased the meaning of assigned integer codes and
broke assignment and pivots. A factor proxy alone did not fix that; retaining the
buffer dictionary did. Full character-label proxies worked but increased runtime
and allocations. Empty user-facing slices do not need to retain dictionaries.

Casting aligns IDs with the target dictionary before assignment. Known units
absent from that dictionary must error, including when the target dictionary is
empty; silently returning the source can lose unit meaning during assignment.
Combining objects can instead establish a common dictionary first.

Retain regression coverage for reordered dictionaries, all-missing buffers,
known-unit NA values, empty slices versus prototypes, sparse pivots, entirely
missing output columns, and equality across different dictionary orders.

## Compatibility boundaries

The prototype deliberately omits explicit conversion and full `units()` /
`units<-` / `as_units()` / `drop_units()` integration. Those omissions are not
acceptable assumptions for redefining the existing class; inventory upstream
methods and callers before porting.

Scalar recycling and scalar extraction were aligned with `mixed_units` in the
prototype: `[` preserves the mixed class, while `[[` returns an ordinary `units`
scalar (or NULL for unknown-unit extraction). Plain numeric addition/comparison
is rejected even for dimensionless values. Check upstream behavior comprehensively.

Prototype extensions include `rep()`, additional operators, and explicit unknown
unit IDs. Do not automatically adopt all of them in the fork. Likewise, prototype
duplicate/equality semantics use stored values and unit labels, not physical
equivalence after conversion. Resolve these against upstream tests and feedback.
Changing away from a list also affects callers relying on list inheritance,
unclassed storage, iteration, coercion, and serialization; distinguish deliberate
representation changes from accidental public behavior regressions.

## Evidence and validation plan

The prototype benchmark uses GitHub `units` 1.0-1.6, revision
`a823fef46d92ee4e1b2e2fa28ddf4c19d67cefb6`. These are reference results, not
predictions for the fork. The main presentation uses 10,000 elements and eight
balanced/shuffled unit types, with two types as a comparison. Eight-type retained
size was approximately 121 KB versus 1.76 MB. Arithmetic advantages diminish with
unit-pair diversity; concatenation was slower. See the linked summary for timings.

Numeric values and canonical unit labels are checked outside timing; the check
does not establish full API or metadata compatibility. There are 132 passing
benchmark checks and 11 unsupported repetition cases in the saved run. Explicit
conversion currently times only `mixed_units`, because IndexedUnits has no such
API. Adapt that workload to compare both implementations in the fork.

Timings are exploratory medians of 3–5 iterations including GC. Distinguish
retained size from profiler-reported allocations: R's profiler undercounts small
objects, favoring scalar-list implementations. These allocation totals are neither
complete allocation estimates nor peak memory. Retained-size measurement includes
an attribute-accounting workaround documented in the script.

Suggested implementation sequence:

1. Record the fork branch and baseline commit; run upstream tests unchanged.
2. Inventory public methods and internal list-storage assumptions. Add regression
   cases from this prototype where relevant without replacing upstream coverage.
3. Port representation and dictionary operations, then implement compatible
   conversion via unchanged `set_units.units` and grouped arithmetic.
4. Validate vctrs integration and the dictionary exceptions above. Decide dependency
   policy with maintainers; the prototype's use of vctrs is not an upstream mandate.
5. Run the full package tests and package checks. Benchmark baseline and redesign
   in separate libraries/sessions against identical fixtures and dependencies,
   comparing decoded values/units and checking public behavior separately.

Keep benchmark presentation concise, use eight types as the main scenario and
two as comparison, retain runtime and memory figures, and do not add the 100,000
-element case (explicitly excluded because it takes too long).
