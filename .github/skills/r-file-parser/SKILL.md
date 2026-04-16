# Skill: R File Parser for RAG Pipeline

## When to use this skill

Load this skill when asked to:
- Add support for a new file format to the ingestion pipeline
- Write or fix a text extraction function
- Extend `ingest_all.R` to discover additional file types
- Debug a parser that is producing garbled or empty text

---

## The parser contract

Every parser must follow this exact signature. No exceptions.

```r
#' Extract plain text from a [FORMAT] file
#'
#' @param file_path Character string — path to the source file
#' @return character(1) — a single collapsed string of plain text
#'   Returns stop() with a descriptive message on unrecoverable failure.
extract_text_<format> <- function(file_path) {
  # validate input
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  # extract and collapse
  text <- ...
  paste(text, collapse = "\n\n")
}
```

Key rules:
- Always return `character(1)` — a **single string**, never a vector.
- Collapse multi-page or multi-sheet content with `"\n\n"` as the separator.
- Call `stop()` (not `warning()`) on unrecoverable errors — the dispatch loop in `ingest_all.R` handles them via `tryCatch()`.
- Never `library()` inside a parser function — assume packages are loaded at script top.

---

## Approved packages and approaches by file type

All packages are pure CRAN — no system install rights required.

### PDF — `pdftools`
```r
extract_text_pdf <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  pages <- pdftools::pdf_text(file_path)
  paste(pages, collapse = "\n\n")
}
```

### DOCX — `officer`
```r
extract_text_docx <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  doc     <- officer::read_docx(file_path)
  summary <- officer::docx_summary(doc)
  # Keep paragraph text and table cell text; skip images, charts, etc.
  text_rows <- summary[summary$content_type %in% c("paragraph", "table cell"), ]
  paste(text_rows$text, collapse = "\n\n")
}
```

Pitfall: `docx_summary()` returns an empty data frame for a protected or corrupted DOCX.
Guard with: `if (nrow(text_rows) == 0) stop("No extractable text found in: ", basename(file_path))`

### XLSX / XLS — `readxl`
```r
extract_text_xlsx <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  sheet_names <- readxl::excel_sheets(file_path)
  sheet_texts <- lapply(sheet_names, function(sheet) {
    df <- readxl::read_excel(file_path, sheet = sheet, col_types = "text")
    if (nrow(df) == 0) return("")
    # Prefix each row with "ColName: value" pairs for BM25-friendly text
    apply(df, 1, function(row) {
      pairs <- paste(names(row), row, sep = ": ", collapse = " | ")
      paste0("[", sheet, "] ", pairs)
    }) |> paste(collapse = "\n")
  })
  paste(sheet_texts, collapse = "\n\n")
}
```

Pitfall: cells may be `NA` — use `tidyr::replace_na()` or `ifelse(is.na(x), "", x)` before pasting.

### TXT — `readr`
```r
extract_text_txt <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  readr::read_file(file_path)
}
```

### Markdown — `commonmark`
```r
extract_text_md <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  raw <- readr::read_file(file_path)
  # commonmark::markdown_text() strips syntax and returns plain prose
  commonmark::markdown_text(raw)
}
```

Pitfall: `markdown_text()` adds a trailing newline — use `trimws()` on the result.

### HTML — `xml2` + `rvest`
```r
extract_text_html <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  page <- xml2::read_html(file_path)
  # Remove script and style nodes before extracting text
  xml2::xml_remove(xml2::xml_find_all(page, "//script"))
  xml2::xml_remove(xml2::xml_find_all(page, "//style"))
  rvest::html_text(page, trim = TRUE)
}
```

### CSV — `readr`
```r
extract_text_csv <- function(file_path) {
  if (!file.exists(file_path)) stop("File not found: ", file_path)
  df <- readr::read_csv(file_path, show_col_types = FALSE)
  apply(df, 1, function(row) {
    paste(names(row), row, sep = ": ", collapse = " | ")
  }) |> paste(collapse = "\n")
}
```

---

## Registering a new parser in `ingest_all.R`

Add an entry to `PARSER_REGISTRY`. The dispatch loop calls it automatically — no other changes needed.

```r
PARSER_REGISTRY <- list(
  pdf  = extract_text_pdf,
  docx = extract_text_docx,
  xlsx = extract_text_xlsx,
  xls  = extract_text_xlsx,   # same parser handles both
  txt  = extract_text_txt,
  md   = extract_text_md,
  html = extract_text_html,
  csv  = extract_text_csv
)
```

---

## Metadata to attach

Always pass `origin` and `file_type` to `MarkdownDocument()` so the Shiny UI can filter by type:

```r
doc <- ragnar::MarkdownDocument(
  text,
  origin    = path,
  file_type = tolower(tools::file_ext(path))
)
```

---

## Common pitfalls

| Issue | Cause | Fix |
|---|---|---|
| Empty chunks from DOCX | Protected file or no paragraph-type rows | Check `nrow(text_rows) > 0` before proceeding |
| NA values in XLSX text | Blank cells read as `NA` | Replace with `""` before pasting |
| Garbled PDF text | Scanned image PDF | `pdftools::pdf_text()` returns empty strings — consider skipping or flagging |
| Markdown not stripped | `readr::read_file()` used instead of `commonmark` | Use `commonmark::markdown_text()` |
| XLSX with merged cells | `readxl` fills with NA | Accept as limitation; the surrounding cells still provide useful context |
