# Run from the package root: Rscript inst/benchmark/run.R
out <- "inst/benchmark/results"
required <- c("bench", "lobstr", "pkgload", "units", "tidyr", "dplyr", "ggplot2")
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
    target <- converted[ids]
    # Reference conversion through ordinary homogeneous units vectors, untimed.
    expected_values <- numeric(n)
    for (j in seq_len(k)) {
        i <- which(ids == j)
        u <- units::set_units(value[i], labels[j], mode = "standard")
        expected_values[i] <- as.numeric(units::set_units(u, converted[j], mode = "standard"))
    }
    expected_conversion <- indexed_units(expected_values, target)
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
        # IndexedUnits has no explicit-conversion API: the first entry is only
        # a correctness reference and is deliberately excluded from timing.
        convert_units = list(function() expected_conversion, function() units::set_units(mx, target)),
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
        if (workload == "convert_units") {
            implementations <- "mixed_units"
            result <- bench::mark(mixed_units = g(), check = FALSE,
                                  min_iterations = 3, max_iterations = 5, min_time = 0.1,
                                  filter_gc = FALSE)
        } else {
            implementations <- c("IndexedUnits", "mixed_units")
            result <- bench::mark(IndexedUnits = f(), mixed_units = g(), check = FALSE,
                              min_iterations = 3, max_iterations = 5, min_time = 0.1,
                              filter_gc = FALSE)
        }
        timings[[length(timings) + 1L]] <- cbind(spec, workload,
            observed_pairs = if (workload == "multiply_pairs") nrow(unique(data.frame(unit, independent_unit))) else NA_integer_,
            implementation = implementations,
            median_seconds = as.numeric(result$median), min_seconds = as.numeric(result$min),
            allocated_bytes = as.numeric(result$mem_alloc), iterations = result$n_itr,
            garbage_collections = result$n_gc)
        for (j in seq_len(nrow(result))) {
            elapsed <- as.numeric(result$time[[j]])
            iterations[[length(iterations) + 1L]] <- cbind(spec, workload,
                implementation = implementations[[j]],
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
    units_version <- packageDescription("units")
    cat("units version:", units_version$Version, "\n")
    cat("units GitHub revision:", units_version$RemoteSha %||% "CRAN release", "\n")
    cat("Working tree:\n", system2("git", c("status", "--short"), stdout = TRUE), sep = "\n")
    cat("\nUDUNITS database:", system.file("share/udunits/udunits2.xml", package = "units"), "\n")
    print(sessionInfo())
}, file = file.path(out, "session.txt"))
if (any(vapply(statuses, function(x) x$status == "failed", logical(1)))) {
    stop("Some correctness checks failed; see statuses.csv. Failed workloads were not timed.")
}

# Issue-ready figures; the full grid remains available in the CSV files.
library(ggplot2)
plot_data <- subset(do.call(rbind, timings), k == 2 & distribution == "balanced_shuffled")
workload_labels <- c(construct = "Construction", convert_units = "Explicit conversion*",
    slice = "Slicing", replace = "Replacement", concatenate = "Concatenation",
    scale = "Scalar multiplication", add_same = "Addition: same units",
    add_convert = "Addition: unit conversion", multiply_pairs = "Multiplication: unit pairs",
    bind_rows = "Row binding", filter_mutate = "Filter + mutate", pivot_roundtrip = "Pivot round trip")
plot_data$workload <- factor(plot_data$workload, levels = names(workload_labels), labels = workload_labels)
p <- ggplot(plot_data, aes(n, median_seconds * 1000, colour = implementation)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2) +
    scale_x_log10(breaks = lengths, labels = c("100", "1,000", "10,000")) +
    scale_y_log10() + scale_colour_manual(values = c(IndexedUnits = "#0072B2", mixed_units = "#D55E00")) +
    facet_wrap(~workload, ncol = 3, scales = "free_y") +
    labs(title = "IndexedUnits and mixed_units",
         subtitle = paste0("Two balanced, shuffled unit types | units ", units_version$Version,
                           " (", substr(units_version$RemoteSha %||% "CRAN", 1, 7), ")"),
         x = "Number of elements (log scale)", y = "Median elapsed time, ms (log scale; panel-specific ranges)",
         colour = NULL,
         caption = "3–5 timed iterations, including GC. Values and unit labels checked before timing.\n*Explicit conversion: mixed_units only; IndexedUnits has no conversion API.\nRepetition loses the mixed_units class and is not timed.") +
    theme_bw(base_size = 11) + theme(legend.position = "top", plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "runtime.png"), p, width = 12, height = 10, dpi = 180, bg = "white")

# Distinguish retained storage from cumulative allocation during an operation.
storage <- subset(do.call(rbind, sizes), distribution == "balanced_shuffled")
storage_labels <- c("Retained size: 1 unit", "Retained size: 2 units", "Retained size: 8 units")
memory_data <- rbind(
    data.frame(n = storage$n, implementation = storage$implementation, bytes = storage$bytes,
               panel = paste0("Retained size: ", storage$k, ifelse(storage$k == 1, " unit", " units"))),
    data.frame(n = plot_data$n, implementation = plot_data$implementation, bytes = plot_data$allocated_bytes,
               panel = paste0("Allocated: ", as.character(plot_data$workload)))
)
memory_data$panel <- factor(memory_data$panel,
    levels = c(storage_labels, paste0("Allocated: ", unname(workload_labels))))
m <- ggplot(memory_data, aes(n, bytes / 1024, colour = implementation)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2) +
    scale_x_log10(breaks = lengths, labels = c("100", "1,000", "10,000")) +
    scale_y_log10() + scale_colour_manual(values = c(IndexedUnits = "#0072B2", mixed_units = "#D55E00")) +
    facet_wrap(~panel, ncol = 3, scales = "free_y") +
    labs(title = "IndexedUnits and mixed_units: memory",
         subtitle = paste0("Balanced, shuffled units | units ", units_version$Version,
                           " (", substr(units_version$RemoteSha %||% "CRAN", 1, 7), ")"),
         x = "Number of elements (log scale)", y = "Memory, KiB (log scale; panel-specific ranges)",
         colour = NULL,
         caption = "Top row: retained object-size estimates (lobstr, including shared metadata).\nOther rows: cumulative allocation per operation (bench), with two unit types; not peak memory or retained size.\n*Explicit conversion: mixed_units only. Repetition loses the mixed_units class and is not measured.") +
    theme_bw(base_size = 11) + theme(legend.position = "top", plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "memory.png"), m, width = 12, height = 12, dpi = 180, bg = "white")
message("Done. Measurements saved in inst/benchmark/results/.")
