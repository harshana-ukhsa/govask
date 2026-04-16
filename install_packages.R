# Install all packages required by the GovAsk RAG pipeline and Shiny app.
# Run this script once before launching the application.

pkgs <- c(
  # Shiny interface
  "shiny",
  "duckdb",
  "bslib",
  "DT",
  "shinycssloaders",

  # RAG pipeline
  "ragnar",
  "ellmer",
  "httr2",

  # Document parsers
  "pdftools",
  "officer",
  "readxl",
  "readr",
  "commonmark",
  "xml2",
  "rvest"
)

missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_pkgs) == 0) {
  message("All packages already installed.")
} else {
  message("Installing: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs)
  message("Done.")
}
