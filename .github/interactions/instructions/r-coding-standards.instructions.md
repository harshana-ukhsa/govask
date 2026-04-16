---
applyTo: "**/*.R"
---

# R Coding Standards

## Style

- Use `snake_case` for all variable and function names.
- Use the base R pipe `|>` — never `%>%`.
- Opening braces `{` go on the same line as the statement. Closing `}` on their own line.
- Indent with 2 spaces. No tabs.
- Maximum line length: 100 characters.
- One blank line between top-level function definitions.

## Imports

- Always use explicit `library()` calls at the top of the script, one per line.
- Use `package::function()` for non-base functions called only once or twice in a script.
- Never use `require()` — use `library()` which fails loudly if the package is missing.

## Functions

- Every function must have a roxygen2-style comment block even in non-package scripts:

```r
#' Brief one-line description
#'
#' @param x Description of parameter x
#' @return Description of return value
my_function <- function(x) {
  # implementation
}
```

- Use early returns for error/guard conditions rather than deeply nested `if` blocks.
- Validate inputs at the top of the function. Use `stopifnot()` or `stop()` with a clear message.
- Functions should do one thing. If a function is longer than ~40 lines, consider splitting it.

## Error handling

- Wrap all I/O, network calls, and external package calls in `tryCatch()`:

```r
result <- tryCatch(
  some_function(x),
  error = function(e) {
    message("Operation failed: ", conditionMessage(e))
    NULL
  }
)
```

- Never silently swallow errors. Always `message()` what went wrong.
- Return `NULL` from error handlers so callers can check with `is.null()`.

## Output

- Use `message()` for progress and diagnostic output — it goes to stderr and doesn't pollute pipe output.
- Never use `print()` or `cat()` for progress messages in pipeline scripts.
- Use `cat()` only when writing formatted output intentionally to stdout.

## Naming

- Constants: `UPPER_SNAKE_CASE` (e.g. `STORE_PATH`, `DATA_DIR`, `TOP_K`).
- File path variables: suffix with `_path` or `_dir` (e.g. `store_path`, `data_dir`).
- Tibble/data frame variables: suffix with `_tbl` or `_df` (e.g. `chunks_tbl`, `results_df`).
- Boolean variables: prefix with `is_`, `has_`, or `use_` (e.g. `is_empty`, `use_cache`).

## Data

- Prefer `tibble` over `data.frame` for new code.
- Prefer `readr` functions (`read_csv`, `read_file`) over base R equivalents for consistency and informative messages.
- Use `vapply()` over `sapply()` when the return type is known — it fails loudly on type mismatches.
