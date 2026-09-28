expect_indexed <- function(x, value, unit) {
    expect_s3_class(x, "IndexedUnits")
    expect_type(x, "double")
    expect_equal(as.numeric(x), value)
    expect_equal(indexed_unit_labels(x), unit)
    expect_length(attr(x, "unit_id"), length(x))
}

test_that("indexed units validate inputs and store a compact dictionary", {
    x <- indexed_units(c(a = 1, b = 2, c = 3), c("mg", "L", "mg"))
    expect_indexed(x, c(1, 2, 3), c("mg", "L", "mg"))
    expect_named(x, c("a", "b", "c"))
    expect_length(attr(x, "unit_dictionary"), 2)
    expect_type(attr(x, "unit_id"), "integer")
    expect_indexed(indexed_units(units::set_units(c(1, 2), h)), c(1, 2), c("h", "h"))
    expect_indexed(indexed_units(), numeric(), character())
    expect_indexed(indexed_units(1), 1, "1")
    expect_error(indexed_units(1:3, c("mg", "L")), "length")
    expect_error(indexed_units("1", "mg"), "numeric")
    expect_error(indexed_units(matrix(1:4, 2), "mg"), "vector")
    expect_error(indexed_units(1, NA_character_), "missing")
    expect_error(indexed_units(1, "not_a_real_unit"))
})

test_that("base indexing, repetition, concatenation and replacement keep units aligned", {
    x <- indexed_units(c(a = 1, b = 2), c("mg", "L"))
    expect_indexed(x[c(2, 1, 2)], c(2, 1, 2), c("L", "mg", "L"))
    expect_indexed(x["b"], 2, "L")
    expect_indexed(x[[2]], 2, "L")
    expect_indexed(x[c(1, NA, 3)], c(1, NA, NA), c("mg", NA, NA))
    expect_indexed(rep(x, each = 2), c(1, 1, 2, 2), c("mg", "mg", "L", "L"))
    expect_indexed(c(x, indexed_units(3, "s")), c(1, 2, 3), c("mg", "L", "s"))
    x["b"] <- indexed_units(4, "s")
    expect_indexed(x, c(1, 4), c("mg", "s"))
    x[4] <- indexed_units(5, "kg")
    expect_indexed(x, c(1, 4, NA, 5), c("mg", "s", NA, "kg"))
    x[[1]] <- indexed_units(6, "L")
    expect_indexed(x[1], 6, "L")
    expect_error(c(x, 1), "IndexedUnits")
})

test_that("grouped arithmetic delegates dimensional rules to units", {
    x <- indexed_units(c(1, 2, 3), c("mg", "L", "mg"))
    y <- indexed_units(c(0.001, 1000, 0.002), c("g", "mL", "g"))
    expect_indexed(x + y, c(2, 3, 5), c("mg", "L", "mg"))
    expect_indexed(x * 2, c(2, 4, 6), c("mg", "L", "mg"))
    expect_indexed(-x, c(-1, -2, -3), c("mg", "L", "mg"))
    expect_equal(x == y, c(TRUE, FALSE, FALSE))
    expect_error(x + indexed_units(1, "s"))
    expect_error(x + indexed_units(1:2, "mg"), "length")
    expect_error(sum(x), "not supported")
    expect_error(log(x), "not supported")
    expect_error(x ^ 2, "not supported")
})

test_that("base data frames preserve indexed units through row operations", {
    x <- indexed_units(c(1, 2), c("mg", "L"))
    d <- data.frame(id = 1:2, value = x)
    expect_named(d, c("id", "value"))
    expect_indexed(d[c(2, 1), ]$value, c(2, 1), c("L", "mg"))
    expect_indexed(rbind(d, d)$value, c(1, 2, 1, 2), c("mg", "L", "mg", "L"))
    expect_output(print(d), "mg")
})

test_that("empty operations and missing values retain valid metadata", {
    x <- indexed_units(c(1, NA), c("mg", NA))
    expect_indexed(x[integer()], numeric(), character())
    expect_indexed(c(indexed_units(), x), c(1, NA), c("mg", NA))
    expect_indexed(x + indexed_units(1, "g"), c(1001, NA), c("mg", NA))
    expect_indexed(x * numeric(), numeric(), character())
    expect_indexed(indexed_units(c(2, 4), "mg") / 2, c(1, 2), c("mg", "mg"))
    expect_equal(2 * indexed_units(1, "mg"), indexed_units(2, "mg"))
    expect_error(indexed_units(units::set_units(1,h), "min"), "Omit unit")
})

test_that("duplicates respect both stored values and unit labels", {
    x <- indexed_units(c(1, 1, 1), c("mg", "L", "mg"))
    expect_identical(duplicated(x), c(FALSE, FALSE, TRUE))
    expect_identical(anyDuplicated(x), 3L)
    expect_identical(anyDuplicated(x[1:2]), 0L)
    expect_indexed(unique(x), c(1, 1), c("mg", "L"))
    expect_error(sort(x), "not supported")
    expect_error(mean(x), "not supported")
})

test_that("vctrs slices, merges dictionaries, assigns and initializes missing values", {
    skip_if_not_installed("vctrs")
    a <- indexed_units(c(1, 2), c("mg", "L"))
    b <- indexed_units(c(3, 4), c("s", "mg"))
    expect_indexed(vctrs::vec_slice(a, c(2, 1)), c(2, 1), c("L", "mg"))
    expect_indexed(vctrs::vec_c(a, b), 1:4, c("mg", "L", "s", "mg"))
    expect_indexed(vctrs::vec_init(a, 2), c(NA_real_, NA_real_), c(NA_character_, NA_character_))
    expect_indexed(vctrs::vec_assign(a, 1, a[2]), c(2, 2), c("L", "L"))
})

test_that("tidyr pivots round trip numeric values and units without list columns", {
    skip_if_not_installed("tidyr")
    a <- indexed_units(c(1, 2), c("mg", "L"))
    b <- indexed_units(c(3, 4), c("s", "mg"))
    d <- data.frame(id = 1:2, a = a, b = b)
    long <- tidyr::pivot_longer(d, c(a, b))
    expect_indexed(long$value, c(1, 3, 2, 4), c("mg", "s", "L", "mg"))
    wide <- tidyr::pivot_wider(long, names_from = name, values_from = value)
    expect_indexed(wide$a, c(1, 2), c("mg", "L"))
    expect_indexed(wide$b, c(3, 4), c("s", "mg"))
    sparse <- tidyr::pivot_wider(long[-2, ], names_from = name, values_from = value)
    expect_indexed(sparse$b, c(NA, 4), c(NA, "mg"))
    expect_false(is.list(long$value))
})

test_that("dictionary remapping preserves reordered, unused and unknown units", {
    x <- indexed_units(c(a = 1, b = 2, c = NA), c("mg", "L", NA))
    y <- indexed_units(c(3, 4), c("L", "mg"))
    expect_indexed(c(x, y), c(1, 2, NA, 3, 4), c("mg", "L", NA, "L", "mg"))
    x[c("a", "b")] <- y
    expect_indexed(x, c(3, 4, NA), c("L", "mg", NA))
    expect_named(x, c("a", "b", "c"))

    # A slice keeps unused dictionary entries; only used units must be castable.
    target <- indexed_units(c(0, 0), c("L", "mg"))[integer()]
    expect_indexed(vctrs::vec_cast(x, target), c(3, 4, NA), c("L", "mg", NA))
    expect_named(vctrs::vec_cast(x, target), names(x))
    expect_indexed(vctrs::vec_cast(x[c(2, 3)], indexed_units(0, "mg")),
                   c(4, NA), c("mg", NA))
    expect_error(vctrs::vec_cast(x, indexed_units(0, "mg")), "does not contain")
    expect_indexed(vctrs::vec_cast(x[3], indexed_units()), NA_real_, NA_character_)
})

test_that("constructors remap aliases and recycle scalar labels", {
    x <- indexed_units(c(1, 2, NA, 4), c("meter", "m", NA, "s"))
    expect_indexed(x, c(1, 2, NA, 4), c("m", "m", NA, "s"))
    expect_identical(attr(x, "unit_dictionary"), c("m", "s"))
    expect_indexed(indexed_units(c(1, NA, 3), "mg"), c(1, NA, 3), rep("mg", 3))
    expect_indexed(indexed_units(rep(NA_real_, 3), NA_character_), rep(NA_real_, 3), rep(NA_character_, 3))
    expect_indexed(indexed_units(numeric(), "mg"), numeric(), character())
})

test_that("arithmetic groups IDs and merges equal result units across pairs", {
    x <- indexed_units(c(1, 2, NA, 4, NA), c("m", "s", NA, "m", "m"))
    y <- indexed_units(c(3, 4, 5, 6, 7), c("s", "m", "kg", "m", "s"))
    result <- x * y
    expected <- units::deparse_unit(units::set_units(1, m) * units::set_units(1, s))
    expect_indexed(result, c(3, 8, NA, 24, NA), c(expected, expected, NA, "m2", expected))
    expect_length(attr(result, "unit_dictionary"), 2)
    expect_identical(attr(result, "unit_dictionary"), unique(indexed_unit_labels(result)[!is.na(indexed_unit_labels(result))]))
    expect_indexed(x / x, c(1, 1, NA, 1, NA), c("1", "1", NA, "1", "1"))
    expect_identical(x == x, c(TRUE, TRUE, NA, TRUE, NA))
    expect_indexed(indexed_units(NA_real_, NA_character_) * x, rep(NA_real_, 5), rep(NA_character_, 5))
    expect_indexed(x * numeric(), numeric(), character())
})
