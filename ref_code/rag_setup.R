# =============================================================================
# rag_setup.R — RAG Pipeline: Stage 1 — Document Ingestion & Indexing
# =============================================================================
#
# PURPOSE
# -------
# This script is the first stage of a RAG (Retrieval-Augmented Generation)
# pipeline. It reads every PDF and DOCX file in the data/ folder, splits the
# text into overlapping chunks, and stores those chunks in a persistent DuckDB
# database with a BM25 full-text search index.
#
# You run this ONCE (or again whenever documents are added or updated). The
# query script (rag_query.R) then connects to the store without re-processing.
#
# WHAT IS HAPPENING — THE BIG PICTURE
# -------------------------------------
#  PDF/DOCX files  →  raw text  →  chunks  →  DuckDB store  →  BM25 index
#
# WHY CHUNK THE TEXT?
# -------------------
# LLMs have a context window limit — you can't send an entire 50-page document
# in a single prompt. Chunking splits the document into smaller, overlapping
# pieces so that the most relevant section can be selected and sent to the LLM.
# Overlap ensures that important sentences near a chunk boundary aren't lost.
#
# WHY BM25 (NOT VECTOR EMBEDDINGS)?
# ----------------------------------
# Two common search strategies exist for RAG:
#
#   1. BM25 (keyword search) — scores chunks based on matching words.
#      Fast, transparent, works offline, no AI model required.
#      This is the approach used here.
#
#   2. Vector similarity search — converts text to numerical "embeddings"
#      and finds semantically similar chunks even if exact words differ.
#      Requires a separate embedding model (local or API-based).
#
# For a first demonstrator, BM25 is ideal: no extra infrastructure, easy to
# understand, and very effective for structured documents like SOPs and reports.
#
# WHY DUCKDB?
# -----------
# DuckDB is an embedded analytical database — think of it like SQLite but
# optimised for analytical queries. ragnar stores all chunks and the BM25
# index inside a single .duckdb file. This means:
#   - The index persists between R sessions (no re-processing on every run)
#   - You can inspect, back up or share the store as a single file
#   - Adding more PDFs is as simple as re-running this script
#
# DEPENDENCIES
# ------------
#   install.packages("ragnar")    # chunking, storage, retrieval
#   install.packages("pdftools")  # pure-R PDF text extraction (no Python)
#   install.packages("officer")   # DOCX text extraction
#   install.packages("here")      # reliable path resolution
#
# USAGE
#   source("rag_setup.R")         # from R console
#   Rscript rag_setup.R           # from terminal
# =============================================================================

library(ragnar)   # ragnar: the core RAG toolkit (chunking, DuckDB, BM25)
library(pdftools) # pdftools: PDF text extraction using libpoppler — pure R,
                  # no Python or internet download required
library(officer)  # officer: DOCX text extraction — reads Word documents
library(xml2)       # xml2: HTML/XML parsing
library(rvest)      # rvest: HTML text extraction
library(readr)      # readr: TXT and CSV file reading
library(commonmark) # commonmark: Markdown to plain text stripping
library(here)       # here: reliable path resolution regardless of working directory

# Where to save the DuckDB store file and where to look for documents
# Using here::here() ensures paths resolve correctly even if the working
# directory isn't the project root (e.g. when sourcing from a subdirectory)
STORE_PATH       <- here::here("data", "rag_store.duckdb")
DATA_DIRS        <- c(
  here::here("data", "structured_files"),
  here::here("data", "unstructured_files"),
  here::here("data", "epids_files")
)

# =============================================================================
# STEP 1: Discover all supported files across both data folders
# =============================================================================
# list.files() with a regex pattern picks up matching files automatically.
# This means you never need to hardcode filenames — just drop documents into
# either data folder and re-run this script to include them in the index.

discover <- function(dirs, pattern) {
  unlist(lapply(dirs, list.files,
                pattern = pattern, full.names = TRUE, recursive = FALSE))
}

pdf_files  <- discover(DATA_DIRS, "\\.pdf$")
docx_files <- discover(DATA_DIRS, "\\.docx$")
html_files <- discover(DATA_DIRS, "\\.html?$")
txt_files  <- discover(DATA_DIRS, "\\.txt$")
md_files   <- discover(DATA_DIRS, "\\.md$")
all_files  <- c(pdf_files, docx_files, html_files, txt_files, md_files)

if (length(all_files) == 0) {
  stop("No supported files found in data folders. Add documents and try again.")
}

message("Found ", length(all_files), " document(s) to ingest:")
message("  ", length(pdf_files), " PDF(s), ", length(docx_files), " DOCX(s), ",
        length(html_files), " HTML(s), ", length(txt_files), " TXT(s), ", length(md_files), " MD(s)")
for (f in all_files) message("  ", f)

# =============================================================================
# STEP 2: Define text extraction functions
# =============================================================================
# Different file formats require different extraction methods.

# PDF → plain text using pdftools
# Returns one character string per page, collapsed with paragraph separators.
extract_pdf <- function(path) {
  pages <- pdftools::pdf_text(path)
  paste(pages, collapse = "\n\n")
}

# DOCX → plain text using officer
# Reads the Word document and extracts text from all paragraphs.
extract_docx <- function(path) {
  doc <- officer::read_docx(path)
  content <- officer::docx_summary(doc)
  # Filter to paragraph content and collapse
  paragraphs <- content$text[content$content_type == "paragraph"]
  paste(paragraphs, collapse = "\n\n")
}

# HTML → plain text using xml2 + rvest
# Removes <script> and <style> nodes before extracting visible text.
extract_html <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path)
  page <- xml2::read_html(path)
  xml2::xml_remove(xml2::xml_find_all(page, "//script"))
  xml2::xml_remove(xml2::xml_find_all(page, "//style"))
  rvest::html_text(page, trim = TRUE)
}

# TXT → plain text using readr
extract_txt <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path)
  readr::read_file(path)
}

# Markdown → plain text using commonmark
# Strips Markdown syntax (headings, bold, links, etc.) leaving prose only.
extract_md <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path)
  raw <- readr::read_file(path)
  trimws(commonmark::markdown_text(raw))
}

# Dispatcher: choose extraction method based on file extension
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

# =============================================================================
# STEP 3: Extract text and split into chunks
# =============================================================================
# We process each document in turn with lapply(), collecting a tibble of chunks
# for every file and storing them all in the list `all_chunks`.

all_chunks <- lapply(all_files, function(path) {
  message("\nProcessing: ", basename(path))

  # --- 3a. Document → plain text ----------------------------------------------
  # The extract_text() dispatcher handles PDF vs DOCX automatically.
  text <- extract_text(path)

  # --- 3b. Wrap in a MarkdownDocument ----------------------------------------
  # ragnar works with MarkdownDocument objects. Even though our text isn't
  # formatted Markdown, wrapping it here achieves two things:
  #   - It attaches the source file path as `origin` metadata on every chunk,
  #     so you always know which document an answer came from.
  #   - It lets ragnar's chunker use its boundary-snapping logic (see below).
  doc <- MarkdownDocument(text, origin = path)

  # --- 3c. Split into overlapping chunks -------------------------------------
  # markdown_chunk() slides a window across the document, producing chunks of
  # ~1600 characters with a 25% overlap between adjacent chunks.
  #
  # target_size = 1600:
  #   Roughly 400 tokens or one A4 page of text. Small enough to fit into a
  #   prompt alongside the question; large enough to contain a complete idea.
  #
  # target_overlap = 0.25:
  #   Each chunk shares ~25% of its content with the next chunk. This prevents
  #   a sentence that straddles two chunks from being missed entirely.
  #   Example: if chunk 1 ends mid-paragraph, chunk 2 starts before that point
  #   so the full paragraph is captured in at least one chunk.
  #
  # ragnar also "snaps" cut points to the nearest semantic boundary
  # (heading > paragraph > sentence > word), so chunks rarely cut mid-sentence.
  chunks <- markdown_chunk(
    doc,
    target_size    = 1600L,
    target_overlap = 0.25
  )
  message("  -> ", nrow(chunks), " chunks")
  chunks
})

# =============================================================================
# STEP 4: Create the DuckDB store
# =============================================================================
# ragnar_store_create() opens (or creates) a DuckDB database file and sets up
# the schema ragnar needs.
#
# embed = NULL:
#   We are using BM25 keyword search only, so we do not need an embedding
#   model. Setting embed = NULL tells ragnar to skip the embeddings column.
#   If you later wanted to add semantic (vector) search, you would replace
#   NULL with an embedding function, e.g. embed_ollama() for a local model.
#
# overwrite = TRUE:
#   Rebuilds the store from scratch each time. Safe for a demo; for a
#   production pipeline you might use ragnar_store_update() to only re-index
#   files that have changed.

message("\nCreating store: ", STORE_PATH)
# Delete the file first so DuckDB never opens it in read-only mode,
# which would cause a DROP error when overwrite = TRUE is attempted.
if (file.exists(STORE_PATH)) {
  file.remove(STORE_PATH)
  message("  Removed existing store file.")
}
store <- ragnar_store_create(
  location  = STORE_PATH,
  embed     = NULL,
  overwrite = TRUE
)

# =============================================================================
# STEP 5: Insert all chunks into the store
# =============================================================================
# ragnar_store_insert() writes each chunk tibble (text, start, end, context,
# origin) into the DuckDB database. We loop over all_chunks so that every
# document is inserted in one pass.

for (chunks in all_chunks) {
  ragnar_store_insert(store, chunks)
}

# =============================================================================
# STEP 6: Build the BM25 full-text search index
# =============================================================================
# ragnar_store_build_index() creates a DuckDB full-text search index using
# the BM25 (Okapi Best Matching 25) algorithm.
#
# BM25 is the same algorithm that powers Elasticsearch and many search engines.
# It scores each chunk by:
#   - Term frequency: how often query words appear in the chunk
#   - Inverse document frequency: rare words score higher than common words
#   - Document length normalisation: longer chunks aren't unfairly penalised
#
# This index is stored inside the .duckdb file, so it only needs to be built
# once — rag_query.R can reuse it in every session without rebuilding.

message("Building BM25 index...")
ragnar_store_build_index(store)

# =============================================================================
# STEP 7: Summary
# =============================================================================
total_chunks <- sum(vapply(all_chunks, nrow, integer(1L)))
message(
  "\nDone. Indexed ", length(all_files), " document(s) (",
  length(pdf_files), " PDF, ", length(docx_files), " DOCX), ",
  total_chunks, " chunk(s) total.\n",
  "Store saved to: ", STORE_PATH, "\n",
  "You can now run rag_query.R to ask questions."
)
