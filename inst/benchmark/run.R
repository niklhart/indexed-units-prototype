# Run from the package root: Rscript inst/benchmark/run.R
out <- "inst/benchmark/results"
required <- c("bench", "lobstr", "pkgload", "units", "tidyr", "dplyr")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install benchmark dependencies: ", paste(missing, collapse = ", "))
stopifnot(file.exists("DESCRIPTION"), file.exists("R/IndexedUnits.R"))
pkgload::load_all(".", quiet = TRUE)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
set.seed(20260928)

# Compare public values and canonical labels, not class-specific attributes.
decode <- function(x) {
    if (inherits(x, "IndexedUnits")) {
        return(list(value = as.numeric(x), unit = indexed_unit_labels(x)))
    }
    stopifnot(inherits(x, "mixed_units"))
    list(value = vapply(unclass(x), function(z) {
        if (is.null(z)) NA_real_ else as.numeric(z)
    }, numeric(1)), unit = vapply(unclass(x), function(z) {
        if (is.null(z)) NA_character_ else units::deparse_unit(z)
    }, character(1)))
}
check_equal <- function(a, b) {
    if (is.data.frame(a)) {
        stopifnot(identical(names(a), names(b)), identical(nrow(a), nrow(b)))
        for (nm in names(a)) check_equal(a[[nm]], b[[nm]])
    } else if (inherits(a, "IndexedUnits")) {
        stopifnot(isTRUE(all.equal(decode(a), decode(b), tolerance = 1e-10)))
    } else stopifnot(isTRUE(all.equal(a, b, tolerance = 1e-10)))
    invisible(TRUE)
}
labels <- c("m", "s", "kg", "L", paste0("m^", 2:5))
converted <- c("cm", "min", "g", "mL", paste0("cm^", 2:5))
lengths <- c(100L, 1000L, 10000L)
grid <- expand.grid(n = lengths, k = c(1L, 2L, 8L))
grid$distribution <- "balanced_shuffled"
extra <- expand.grid(n = max(lengths), k = 8L,
                     distribution = c("balanced_grouped", "skewed_shuffled"))
grid <- rbind(grid, extra)
timings <- sizes <- statuses <- iterations <- list()
for (case in seq_len(nrow(grid))) {
    spec <- grid[case, ]
    rownames(spec) <- NULL
    n <- spec$n; k <- spec$k
    message(sprintf("[%d/%d] n=%d, units=%d, %s", case, nrow(grid), n, k, spec$distribution))
    ids <- rep_len(seq_len(k), n)
    if (spec$distribution == "skewed_shuffled") {
        ids <- c(seq_len(k), sample(seq_len(k), n - k, TRUE, prob = c(0.9, rep(0.1 / (k - 1), k - 1))))
    }
    ids <- if (spec$distribution == "balanced_grouped") sort(ids) else sample(ids)
    value <- runif(n, 1, 10)
    unit <- labels[ids]
    ix <- indexed_units(value, unit)
    mx <- units::mixed_units(value, unit)
    iy <- indexed_units(value / 2, converted[ids])
    my <- units::mixed_units(value / 2, converted[ids])
    # Different first-occurrence order, with overlapping and new dictionary entries.
    other_unit <- rep_len(rev(c(labels[seq_len(k)], "K")), n)
    iz <- indexed_units(value, other_unit)
    mz <- units::mixed_units(value, other_unit)
    independent_unit <- sample(unit)
    ip <- indexed_units(value, independent_unit)
    mp <- units::mixed_units(value, independent_unit)
    take <- sample.int(n, max(1L, n %/% 2L))
    replace_at <- seq_len(max(1L, n %/% 100L))
    replacement_i <- indexed_units(1, "K")
    replacement_m <- units::mixed_units(1, "K")
    frame <- function(x, z) {
        d <- data.frame(id = seq_len(n)); d$a <- x; d$b <- z; d
    }
    di <- frame(ix, iz); dm <- frame(mx, mz)
    pipeline <- function(d) {
        d <- dplyr::filter(d, id %% 2L == 0L)
        dplyr::mutate(d, a = a * 2)
    }
    pivot <- function(d) {
        long <- tidyr::pivot_longer(d, c(a, b))
        tidyr::pivot_wider(long, names_from = name, values_from = value)
    }
    replace <- function(x, replacement) { x[replace_at] <- replacement; x }
    jobs <- list(
        construct = list(function() indexed_units(value, unit), function() units::mixed_units(value, unit)),
        slice = list(function() ix[take], function() mx[take]),
        repetition = list(function() rep(ix, 2), function() rep(mx, 2)),
        replace = list(function() replace(ix, replacement_i), function() replace(mx, replacement_m)),
        concatenate = list(function() c(ix, iz), function() c(mx, mz)),
        scale = list(function() ix * 2, function() mx * 2),
        add_same = list(function() ix + ix, function() mx + mx),
        add_convert = list(function() ix + iy, function() mx + my),
        multiply_pairs = list(function() ix * ip, function() mx * mp),
        bind_rows = list(function() dplyr::bind_rows(di, di), function() dplyr::bind_rows(dm, dm)),
        filter_mutate = list(function() pipeline(di), function() pipeline(dm)),
        pivot_roundtrip = list(function() pivot(di), function() pivot(dm))
    )
    for (implementation in c("IndexedUnits", "mixed_units")) {
        x <- if (implementation == "IndexedUnits") ix else mx
        # Explicit attribute roots avoid undercounting the parallel ID vector
        # with lobstr 1.2.2 on R 4.5.2. Shared objects are counted only once.
        bytes <- as.numeric(do.call(lobstr::obj_size, c(list(x), unname(attributes(x)))))
        if (implementation == "IndexedUnits") stopifnot(bytes >= 12 * n)
        sizes[[length(sizes) + 1L]] <- cbind(spec, implementation, bytes,
            base_object_size_bytes = as.numeric(object.size(x)))
    }
    for (workload in names(jobs)) {
        f <- jobs[[workload]][[1]]; g <- jobs[[workload]][[2]]
        unsupported <- FALSE
        error <- tryCatch({
            a <- f(); b <- g()
            if (inherits(a, "IndexedUnits") && !inherits(b, "mixed_units")) {
                unsupported <- TRUE
                stop("mixed_units result lost its class (returned ", paste(class(b), collapse = "/"), ").")
            }
            check_equal(a, b); NULL
        }, error = conditionMessage)
        statuses[[length(statuses) + 1L]] <- cbind(spec, workload,
            status = if (unsupported) "unsupported" else if (is.null(error)) "pass" else "failed",
            detail = if (is.null(error)) "" else error)
        if (!is.null(error)) next
        # Check above is outside timing; native outputs intentionally have different classes.
        result <- bench::mark(IndexedUnits = f(), mixed_units = g(), check = FALSE,
                              min_iterations = 3, max_iterations = 5, min_time = 0.1,
                              filter_gc = FALSE)
        timings[[length(timings) + 1L]] <- cbind(spec, workload,
            observed_pairs = if (workload == "multiply_pairs") nrow(unique(data.frame(unit, independent_unit))) else NA_integer_,
            implementation = c("IndexedUnits", "mixed_units"),
            median_seconds = as.numeric(result$median), min_seconds = as.numeric(result$min),
            allocated_bytes = as.numeric(result$mem_alloc), iterations = result$n_itr,
            garbage_collections = result$n_gc)
        for (j in seq_len(nrow(result))) {
            elapsed <- as.numeric(result$time[[j]])
            iterations[[length(iterations) + 1L]] <- cbind(spec, workload,
                implementation = c("IndexedUnits", "mixed_units")[[j]],
                iteration = seq_along(elapsed), elapsed_seconds = elapsed)
        }
    }
}
results <- list(timings = timings, sizes = sizes, statuses = statuses, iterations = iterations)
for (name in names(results)) {
    write.csv(do.call(rbind, results[[name]]), file.path(out, paste0(name, ".csv")), row.names = FALSE)
}

# Sparse reshaping is a capability check: NULL and an unknown-unit NA are not
# treated as equivalent representations merely because decode() can normalize them.
sparse <- function(make) {
    d <- data.frame(id = 1:2)
    d$a <- make(c(1, 2), c("mg", "L")); d$b <- make(c(3, 4), c("s", "mg"))
    long <- tidyr::pivot_longer(d, c(a, b))
    wide <- tidyr::pivot_wider(long[-2, ], names_from = name, values_from = value)
    capture.output(print(wide))
}
capture.output({
    for (implementation in c("IndexedUnits", "mixed_units")) {
        cat(implementation, "sparse pivot and print:\n")
        make <- if (implementation == "IndexedUnits") indexed_units else units::mixed_units
        tryCatch(cat(sparse(make), sep = "\n"), error = function(e) cat("ERROR:", conditionMessage(e), "\n"))
    }
}, file = file.path(out, "capabilities.txt"))
capture.output({
    cat("Seed: 20260928\nRun:", format(Sys.time()), "\n")
    cat("Git revision:", system2("git", c("rev-parse", "HEAD"), stdout = TRUE), "\n")
    cat("Working tree:\n", system2("git", c("status", "--short"), stdout = TRUE), sep = "\n")
    cat("\nUDUNITS database:", system.file("share/udunits/udunits2.xml", package = "units"), "\n")
    print(sessionInfo())
}, file = file.path(out, "session.txt"))
if (any(vapply(statuses, function(x) x$status == "failed", logical(1)))) {
    stop("Some correctness checks failed; see statuses.csv. Failed workloads were not timed.")
}
message("Done. Measurements saved in inst/benchmark/results/.")
