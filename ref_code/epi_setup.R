# =============================================================================
# epi_setup.R — EpiAsk RAG Pipeline: Document Ingestion & Indexing
# =============================================================================
#
# PURPOSE
# -------
# Builds the DuckDB store for the EpiAsk tab by indexing all documents in
# data/epids_files/. Identical pipeline to rag_setup.R — only the source
# directory and store output path differ.
#
# USAGE
#   source("ref_code/epi_setup.R")   # from R console (project root)
#
# PREREQUISITES
#   1. Documents placed in data/epids_files/
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
DATA_DIR   <- here::here("data", "epids_files")
STORE_PATH <- here::here("data", "epids_store.duckdb")

if (!dir.exists(DATA_DIR)) {
  stop("Directory not found: '", DATA_DIR, "'. Create it and add documents.")
}

# ── Delegate to the shared setup logic ────────────────────────────────────────
# Override the path constants then source rag_setup.R, skipping its own
# library() and path-definition lines by setting a flag first.
# We instead re-implement the steps directly to keep this self-contained.

# ── Step 1: Discover files ────────────────────────────────────────────────────
all_files <- list.files(
  DATA_DIR,
  pattern    = "\\.(pdf|docx|html?|txt|md)$",
  full.names = TRUE,
  recursive  = TRUE,
  ignore.case = TRUE
)

if (length(all_files) == 0) {
  stop("No supported files found in '", DATA_DIR, "'. Add documents and try again.")
}

message("Found ", length(all_files), " document(s) to ingest in ", DATA_DIR)
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
  stop("No chunks produced — check that documents contain extractable text.")
}

# ── Step 4: Create the DuckDB store ──────────────────────────────────────────
message("\nCreating EpiAsk store: ", STORE_PATH)
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
  "You can now run shiny::runApp(\"R\") to use the EpiAsk tab."
)
