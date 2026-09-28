#' Helper function to check if an object inherits from a specified class
#'
#' Throws an error if `x` does not inherit from `class`
#'
#' @param x Object to check
#' @param class Expected class name (string)
#' @returns The function returns the input invisibly if the check passes, otherwise it throws an error
#' @noRd
.check_class <- function(x, class) {
    if (!inherits(x, class)) {
        stop("Expected object of class '", class, "', got '", class(x)[1], "'.")
    }
    invisible(x)
}