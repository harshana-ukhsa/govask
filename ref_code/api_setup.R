# =============================================================================
# api_setup.R — APIAsk RAG Pipeline: Document Ingestion & Indexing
# =============================================================================
#
# PURPOSE
# -------
# Builds the DuckDB store for the APIAsk tab by indexing all documents in
# data/govapi_files/. These are documents downloaded from the GOV.UK API
# (e.g. UKHSA guidance).
#
# USAGE
#   source("ref_code/api_setup.R")   # from R console (project root)
#
# PREREQUISITES
#   1. Documents downloaded to data/govapi_files/ (via govuk_api.R)
#   2. Packages installed: source("install_packages.R")
# =============================================================================

library(ragnar)
library(pdftools)
library(officer)
library(xml2)
library(rvest)
library(readr)
library(commonmark)
library(here)

# ── Paths ─────────────────────────────────────────────────────────────────────
DATA_DIR   <- here::here("data", "govapi_files")
STORE_PATH <- here::here("data", "api_store.duckdb")

# Create directory if it doesn't exist
if (!dir.exists(DATA_DIR)) {
  dir.create(DATA_DIR, recursive = TRUE)
  message("Created directory: ", DATA_DIR)
}

# ── Step 1: Discover files ────────────────────────────────────────────────────
all_files <- list.files(
  DATA_DIR,
  pattern     = "\\.(pdf|docx|html?|txt|md)$",
  full.names  = TRUE,
  recursive   = TRUE,
  ignore.case = TRUE
)

if (length(all_files) == 0) {
  message("No supported files found in APIAsk directory. Skipping store creation.")
  return(invisible(NULL))
}

message("Found ", length(all_files), " document(s) to ingest:")
for (f in all_files) message("  ", basename(f))

# ── Step 2: Text extraction functions ────────────────────────────────────────
extract_pdf <- function(path) {
  paste(pdftools::pdf_text(path), collapse = "\n\n")
}

extract_docx <- function(path) {
  doc     <- officer::read_docx(path)
  content <- officer::docx_summary(doc)
  paste(content$text[content$content_type == "paragraph"], collapse = "\n\n")
}

extract_html <- function(path) {
  page <- xml2::read_html(path)
  xml2::xml_remove(xml2::xml_find_all(page, "//script"))
  xml2::xml_remove(xml2::xml_find_all(page, "//style"))
  rvest::html_text(page, trim = TRUE)
}

extract_txt <- function(path) readr::read_file(path)

extract_md <- function(path) {
  trimws(commonmark::markdown_text(readr::read_file(path)))
}

extract_text <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    pdf  = extract_pdf(path),
    docx = extract_docx(path),
    html = extract_html(path),
    htm  = extract_html(path),
    txt  = extract_txt(path),
    md   = extract_md(path),
    stop("Unsupported file type: ", ext)
  )
}

# ── Step 3: Chunk all documents ───────────────────────────────────────────────
all_chunks <- lapply(all_files, function(path) {
  message("\nProcessing: ", basename(path))
  text <- tryCatch(
    extract_text(path),
    error = function(e) {
      message("  [skip] ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(text) || nchar(trimws(text)) == 0) {
    message("  -> empty, skipped")
    return(NULL)
  }
  doc    <- MarkdownDocument(text, origin = path)
  chunks <- markdown_chunk(doc, target_size = 1600L, target_overlap = 0.25)
  message("  -> ", nrow(chunks), " chunks")
  chunks
})

all_chunks <- Filter(Negate(is.null), all_chunks)

if (length(all_chunks) == 0) {
  message("No chunks produced — check that documents contain extractable text.")
  return(invisible(NULL))
}

# ── Step 4: Create the DuckDB store ──────────────────────────────────────────
message("\nCreating APIAsk store: ", STORE_PATH)
store <- ragnar_store_create(location = STORE_PATH, embed = NULL, overwrite = TRUE)

# ── Step 5: Insert chunks ─────────────────────────────────────────────────────
for (chunks in all_chunks) {
  ragnar_store_insert(store, chunks)
}

# ── Step 6: Build BM25 index ──────────────────────────────────────────────────
message("Building BM25 index...")
ragnar_store_build_index(store)

# ── Summary ───────────────────────────────────────────────────────────────────
total_chunks <- sum(vapply(all_chunks, nrow, integer(1L)))
message(
 "\nDone. Indexed ", length(all_chunks), " document(s), ",
  total_chunks, " chunk(s) total.\n",
  "Store saved to: ", STORE_PATH, "\n",
  "You can now run shiny::runApp(\"R\") to use the APIAsk tab."
)
