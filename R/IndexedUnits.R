#' Experimental numeric vectors with indexed units
#'
#' `IndexedUnits` stores doubles, a per-element integer unit index, and a
#' dictionary of units. It is independent of model and simulation classes and
#' is not a subclass of `units::mixed_units` or `units`.
#'
#' Subsetting, replacement, repetition, concatenation, and base data frames are
#' supported. Optional vctrs methods support tidyr pivots without scalar
#' list-columns. Unit dictionaries are merged without converting stored values.
#' Missing elements introduced by indexing or reshaping have unknown units
#' (`NA`), distinct from dimensionless values (`"1"`).
#' Scalar extraction with `[[` returns an ordinary `units` object, or `NULL`
#' for an element with an unknown unit, matching missing `mixed_units` elements.
#'
#' Arithmetic supports unary `+`/`-`, binary `+`, `-`, `*`, `/`, and comparisons.
#' Operations are grouped by unit pairs and delegated to `units`. Operands must
#' have equal lengths or one must be scalar. Plain numbers are accepted only
#' for multiplication and division; addition, subtraction, and comparisons
#' require two `IndexedUnits` operands, even when dimensionless. Explicitly
#' convert ordinary `units` operands with `indexed_units()` before arithmetic.
#' Math functions and summaries are deliberately unsupported in this prototype.
#' Duplicate detection and vctrs equality use the stored value and unit label,
#' not physical equivalence across convertible units. Sorting is unsupported.
#' This is an experimental API,
#' not a general replacement for `units`, and has no performance guarantee yet.
#'
#' @param x A numeric vector, or a `units` vector when `unit` is omitted.
#' @param unit Unit labels, scalar or matching the length of `x`. A scalar `x`
#'   is recycled to the length of `unit`, as in `units::mixed_units()`.
#'   Defaults to dimensionless (`"1"`). An unknown unit (`NA`) requires a missing value.
#' @returns `indexed_units()` returns an `IndexedUnits` vector;
#'   `indexed_unit_labels()` returns its per-element character unit labels.
#' @examples
#' x <- indexed_units(c(1, 2, 3), c("mg", "L", "mg"))
#' x[c(3, 1)]
#' x * 2
#' data.frame(value = x)
#' @export
indexed_units <- function(x = double(), unit = NULL) {
    if (inherits(x, "IndexedUnits") && is.null(unit)) return(x)
    if (inherits(x, "units")) {
        if (!is.null(unit)) stop("Omit unit when converting a units vector.", call. = FALSE)
        unit <- units::deparse_unit(x)
    }
    if (!is.numeric(x) || !is.null(dim(x)) || is.complex(x)) {
        stop("x must be a numeric vector.", call. = FALSE)
    }
    if (is.null(unit)) unit <- "1"
    if (!is.character(unit) || !(length(x) == 1L || length(unit) %in% c(1L, length(x)))) {
        stop("unit must be character; x or unit must have length one, or their lengths must match.", call. = FALSE)
    }
    if (length(x) == 1L && length(unit) != 1L) {
        nm <- names(x)
        x <- rep_len(as.double(x), length(unit))
        # mixed_units retains the original name and pads further names with NA.
        if (length(x) && !is.null(nm)) names(x) <- nm
    }
    if (!length(x)) unit <- character()
    if (any(is.na(unit) & !is.na(x))) {
        stop("An unknown unit requires a missing value.", call. = FALSE)
    }
    dictionary <- unique(unit[!is.na(unit)])
    canonical <- vapply(dictionary, function(u) {
        units::deparse_unit(units::set_units(1, u, mode = "standard"))
    }, character(1), USE.NAMES = FALSE)
    id <- rep_len(match(unit, dictionary), length(x))
    dictionary <- unique(canonical)
    .new_indexed_units(as.double(x), match(canonical, dictionary)[id], dictionary, names(x))
}

.new_indexed_units <- function(value, id, dictionary, names = NULL) {
    structure(value, unit_id = as.integer(id), unit_dictionary = dictionary,
              names = names, class = "IndexedUnits")
}

#' @rdname indexed_units
#' @export
indexed_unit_labels <- function(x) {
    .check_class(x, "IndexedUnits")
    attr(x, "unit_dictionary")[attr(x, "unit_id")]
}

.indexed_values <- function(x) {
    out <- unclass(x)
    attributes(out) <- if (is.null(names(x))) NULL else list(names = names(x))
    out
}

.remap_unit_ids <- function(x, dictionary) {
    source <- attr(x, "unit_dictionary")
    id <- attr(x, "unit_id")
    if (identical(source, dictionary)) return(id)
    match(source, dictionary)[id]
}

#' @export
`[.IndexedUnits` <- function(x, i, ...) {
    value <- .indexed_values(x)[i]
    ids <- attr(x, "unit_id")
    names(ids) <- names(x)
    .new_indexed_units(value, ids[i], attr(x, "unit_dictionary"), names(value))
}

#' @export
`[[.IndexedUnits` <- function(x, i, ...) {
    if (length(i) == 1L && (is.na(i) ||
        (is.character(i) && (i == "" || is.na(match(i, names(x))))))) return(NULL)
    value <- .indexed_values(x)[[i]]
    ids <- attr(x, "unit_id")
    names(ids) <- names(x)
    id <- ids[[i]]
    if (is.na(id)) return(NULL)
    units::set_units(value, attr(x, "unit_dictionary")[[id]], mode = "standard")
}

#' @export
`[<-.IndexedUnits` <- function(x, i, value) {
    value <- indexed_units(value)
    dictionary <- union(attr(x, "unit_dictionary"), attr(value, "unit_dictionary"))
    values <- .indexed_values(x)
    # union() retains the existing dictionary's order, so its IDs stay valid.
    ids <- attr(x, "unit_id")
    names(ids) <- names(x)
    values[i] <- .indexed_values(value)
    ids[i] <- .remap_unit_ids(value, dictionary)
    .new_indexed_units(values, ids, dictionary, names(values))
}

#' @export
`[[<-.IndexedUnits` <- function(x, i, value) {
    if (length(i) != 1L || length(value) != 1L) {
        stop("[[ replacement requires one index and one value.", call. = FALSE)
    }
    x[i] <- value
    x
}

#' @export
rep.IndexedUnits <- function(x, ...) x[rep(seq_along(x), ...)]

#' @export
c.IndexedUnits <- function(..., recursive = FALSE) {
    if (recursive) stop("Recursive concatenation is not supported.", call. = FALSE)
    xs <- Filter(Negate(is.null), list(...))
    if (!all(vapply(xs, inherits, logical(1), "IndexedUnits"))) {
        stop("All inputs must be IndexedUnits vectors.", call. = FALSE)
    }
    dictionary <- unique(unlist(lapply(xs, attr, "unit_dictionary"), use.names = FALSE))
    value <- do.call(c, lapply(xs, .indexed_values))
    ids <- unlist(lapply(xs, .remap_unit_ids, dictionary = dictionary), use.names = FALSE)
    .new_indexed_units(value %||% double(), ids, dictionary %||% character(), names(value))
}

#' @export
as.double.IndexedUnits <- function(x, ...) as.double(.indexed_values(x))

#' @export
as.data.frame.IndexedUnits <- function(x, row.names = NULL, optional = FALSE, ...) {
    out <- data.frame(value = .indexed_values(x), row.names = row.names)
    out[[1]] <- x
    names(out) <- if (optional) NULL else deparse(substitute(x))
    out
}

#' @export
format.IndexedUnits <- function(x, ...) {
    paste0(format(.indexed_values(x), ...), " [", indexed_unit_labels(x), "]")
}

#' @export
print.IndexedUnits <- function(x, ...) {
    cat("IndexedUnits (experimental):\n")
    print(format(x, ...), quote = FALSE)
    invisible(x)
}

#' @export
Ops.IndexedUnits <- function(e1, e2) {
    op <- .Generic
    if (missing(e2)) {
        if (!op %in% c("+", "-")) stop("Operation not supported: ", op, call. = FALSE)
        return(.new_indexed_units(do.call(op, list(.indexed_values(e1))),
            attr(e1, "unit_id"), attr(e1, "unit_dictionary"), names(e1)))
    }
    if (!op %in% c("+", "-", "*", "/", "==", "!=", "<", "<=", ">", ">=")) {
        stop("Operation not supported: ", op, call. = FALSE)
    }
    if (op %in% c("+", "-", "==", "!=", "<", "<=", ">", ">=") &&
        (!inherits(e1, "IndexedUnits") || !inherits(e2, "IndexedUnits"))) {
        stop("Both operands must be IndexedUnits for addition, subtraction, or comparison.", call. = FALSE)
    }
    e1 <- indexed_units(e1)
    e2 <- indexed_units(e2)
    n1 <- length(e1)
    n2 <- length(e2)
    if (n1 != n2 && n1 != 1L && n2 != 1L && n1 && n2) {
        stop("Operands must have equal lengths or one must be scalar.", call. = FALSE)
    }
    n <- if (!n1 || !n2) 0L else max(n1, n2)
    comparison <- op %in% c("==", "!=", "<", "<=", ">", ">=")
    values <- if (comparison) rep(NA, n) else rep(NA_real_, n)
    a <- rep_len(.indexed_values(e1), n)
    b <- rep_len(.indexed_values(e2), n)
    d1 <- attr(e1, "unit_dictionary")
    d2 <- attr(e2, "unit_dictionary")
    groups <- vctrs::vec_group_loc(vctrs::new_data_frame(list(
        left = rep_len(attr(e1, "unit_id"), n),
        right = rep_len(attr(e2, "unit_id"), n)
    )))
    if (!comparison) {
        id <- rep(NA_integer_, n)
        labels <- rep(NA_character_, nrow(groups))
    }
    for (g in seq_len(nrow(groups))) {
        left <- groups$key$left[g]
        right <- groups$key$right[g]
        if (is.na(left) || is.na(right)) next
        i <- groups$loc[[g]]
        result <- do.call(op, list(
            units::set_units(a[i], d1[left], mode = "standard"),
            units::set_units(b[i], d2[right], mode = "standard")
        ))
        values[i] <- as.vector(result)
        if (!comparison) {
            id[i] <- g
            labels[g] <- units::deparse_unit(result)
        }
    }
    if (comparison) return(values)
    dictionary <- unique(labels[!is.na(labels)])
    .new_indexed_units(values, match(labels, dictionary)[id], dictionary)
}

#' @export
Math.IndexedUnits <- function(x, ...) stop("Math operation not supported: ", .Generic, call. = FALSE)

#' @export
Summary.IndexedUnits <- function(..., na.rm = FALSE) stop("Summary operation not supported: ", .Generic, call. = FALSE)

#' @export
mean.IndexedUnits <- function(x, ...) stop("Mean is not supported for IndexedUnits.", call. = FALSE)

#' @export
xtfrm.IndexedUnits <- function(x) stop("Sorting is not supported for IndexedUnits.", call. = FALSE)

#' @export
sort.IndexedUnits <- function(x, decreasing = FALSE, ...) {
    stop("Sorting is not supported for IndexedUnits.", call. = FALSE)
}

#' @export
duplicated.IndexedUnits <- function(x, incomparables = FALSE, ...) {
    duplicated(data.frame(value = .indexed_values(x), unit = attr(x, "unit_id")),
               incomparables = incomparables, ...)
}

#' @export
unique.IndexedUnits <- function(x, incomparables = FALSE, ...) {
    x[!duplicated(x, incomparables = incomparables, ...)]
}

#' @export
anyDuplicated.IndexedUnits <- function(x, incomparables = FALSE, ...) {
    indices <- which(duplicated(x, incomparables = incomparables, ...))
    if (length(indices)) indices[1L] else 0L
}

#' @exportS3Method vctrs::vec_proxy
vec_proxy.IndexedUnits <- function(x, ...) {
    vctrs::new_data_frame(list(value = .indexed_values(x), unit_id = attr(x, "unit_id")))
}

#' @exportS3Method vctrs::vec_proxy_equal
vec_proxy_equal.IndexedUnits <- function(x, ...) {
    vctrs::new_data_frame(list(value = .indexed_values(x), unit = indexed_unit_labels(x)))
}

#' @exportS3Method vctrs::vec_proxy_compare
vec_proxy_compare.IndexedUnits <- function(x, ...) {
    stop("Ordering is not supported for IndexedUnits.", call. = FALSE)
}

#' @exportS3Method vctrs::vec_restore
vec_restore.IndexedUnits <- function(x, to, ...) {
    .new_indexed_units(x$value, x$unit_id, attr(to, "unit_dictionary"))
}

#' @exportS3Method vctrs::vec_ptype2
vec_ptype2.IndexedUnits.IndexedUnits <- function(x, y, ...) {
    .new_indexed_units(double(), integer(), union(attr(x, "unit_dictionary"), attr(y, "unit_dictionary")))
}

#' @exportS3Method vctrs::vec_cast
vec_cast.IndexedUnits.IndexedUnits <- function(x, to, ...) {
    dictionary <- attr(to, "unit_dictionary")
    id <- .remap_unit_ids(x, dictionary)
    if (any(!is.na(attr(x, "unit_id")) & is.na(id))) {
        stop("Target unit dictionary does not contain all source units.", call. = FALSE)
    }
    .new_indexed_units(.indexed_values(x), id, dictionary, names(x))
}
