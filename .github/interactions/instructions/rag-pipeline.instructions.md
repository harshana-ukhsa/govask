---
applyTo: "rag_*.R, ingest*.R"
---

# RAG Pipeline Conventions

## File responsibilities

| File | Responsibility |
|---|---|
| `ingest_all.R` | Discover files → dispatch to parsers → chunk → store → build index. Run once. |
| `rag_query.R` | Connect to store → retrieve chunks → build prompt → call LLM → parse answer. |
| `app.R` | Shiny wrapper — calls functions from `rag_query.R` reactively. |

`ingest_all.R` replaces the original `rag_setup.R`. Do not edit `rag_setup.R` — treat it as the PDF-only baseline for reference.

## Store constants — define once at the top

```r
STORE_PATH <- "data/rag_store.duckdb"
DATA_DIR   <- "challenge-2"
TOP_K      <- 5L
CHUNK_SIZE <- 1600L
CHUNK_OVERLAP <- 0.25
```

Never hardcode these values inside functions.

## PARSER_REGISTRY pattern

All file type dispatch must go through a named list of functions. Add new parsers here — do not add `if/else` branches scattered through the ingestion loop:

```r
PARSER_REGISTRY <- list(
  pdf  = extract_text_pdf,
  docx = extract_text_docx,
  xlsx = extract_text_xlsx,
  txt  = extract_text_txt,
  md   = extract_text_md,
  html = extract_text_html
)
```

The dispatch loop pattern:

```r
for (path in all_files) {
  ext <- tolower(tools::file_ext(path))
  if (!ext %in% names(PARSER_REGISTRY)) {
    message("Skipping unsupported file type: ", ext, " (", basename(path), ")")
    next
  }
  text <- tryCatch(
    PARSER_REGISTRY[[ext]](path),
    error = function(e) {
      message("Parser failed for ", basename(path), ": ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(text) || nchar(trimws(text)) == 0) next
  # proceed to chunk and insert
}
```

## Parser function signature

Every parser must follow this exact signature:

```r
#' Extract plain text from a [FORMAT] file
#'
#' @param file_path Path to the file
#' @return character(1) — single collapsed string of plain text, or stop() on failure
extract_text_<format> <- function(file_path) {
  # implementation
}
```

- Return type: `character(1)` always — a single string, not a vector of lines or pages.
- On unrecoverable error: `stop()` with a message — the dispatch loop handles it via `tryCatch()`.
- Collapse pages/sheets/paragraphs with `"\n\n"` as the separator.

## MarkdownDocument metadata

Always attach both `origin` and a `file_type` field when wrapping text:

```r
doc <- ragnar::MarkdownDocument(
  text,
  origin    = path,
  file_type = tolower(tools::file_ext(path))
)
```

This allows the Shiny UI to filter results by document type.

## Store creation

Always use `overwrite = TRUE` during the hackathon — no incremental update logic needed:

```r
store <- ragnar::ragnar_store_create(
  location  = STORE_PATH,
  embed     = NULL,      # BM25 only — no embedding model
  overwrite = TRUE
)
```

## Retrieval

Always wrap `ragnar_retrieve_bm25()` in `tryCatch()`. Check for empty results before building the prompt:

```r
top_chunks <- tryCatch(
  ragnar::ragnar_retrieve_bm25(store, question, top_k = TOP_K),
  error = function(e) {
    message("Retrieval failed: ", conditionMessage(e))
    NULL
  }
)

if (is.null(top_chunks) || nrow(top_chunks) == 0) {
  return("No relevant content found in the indexed documents.")
}
```

## Confidence flag

After retrieval, check the top BM25 score. If it is below the threshold, flag it in the prompt and pass the flag to the Shiny UI:

```r
LOW_CONFIDENCE_THRESHOLD <- 1.0

is_low_confidence <- max(top_chunks$metric_value, na.rm = TRUE) < LOW_CONFIDENCE_THRESHOLD
```

## Prompt construction

Each context block must be labelled with the source filename:

```r
build_rag_prompt <- function(question, chunks_tbl, low_confidence = FALSE) {
  context_blocks <- mapply(function(text, origin) {
    paste0("--- Source: ", basename(origin), " ---\n", text)
  }, chunks_tbl$text, chunks_tbl$origin, SIMPLIFY = FALSE)

  context <- paste(context_blocks, collapse = "\n\n")

  confidence_note <- if (low_confidence) {
    "Note: the retrieved context may not directly address this question.\n\n"
  } else ""

  paste0(
    "Answer the question using ONLY the information in the context below.\n",
    "Begin your answer with: 'According to [document name]...'\n",
    "If the answer is not in the context, say: ",
    "'I cannot answer this from the provided documents.'\n",
    "Keep your answer to 3 sentences or fewer unless a list is more appropriate.\n\n",
    confidence_note,
    "Context:\n\n", context, "\n\n",
    "Question: ", question, "\n\n",
    "Answer:"
  )
}
```

## LLM call

Use `httr2` against `/v1/completions`. Never default to `/v1/chat/completions` for this project's internal endpoint:

```r
call_llm <- function(prompt) {
  resp <- httr2::request(paste0(Sys.getenv("LLM_URL"), "/v1/completions")) |>
    httr2::req_headers(Authorization = paste("Bearer", Sys.getenv("GPT_TOKEN"))) |>
    httr2::req_body_json(list(
      model       = Sys.getenv("LLM_MODEL"),
      prompt      = prompt,
      max_tokens  = 400L,
      temperature = 0.1
    )) |>
    httr2::req_timeout(40) |>
    httr2::req_perform()

  trimws(httr2::resp_body_json(resp)$choices[[1]]$text)
}
```

## Answer parsing

Strip the `assistantfinal` reasoning prefix if present. Fall back to the last non-empty line:

```r
parse_answer <- function(raw) {
  marker <- "assistantfinal"
  if (grepl(marker, raw, fixed = TRUE)) {
    trimws(strsplit(raw, marker, fixed = TRUE)[[1]][2])
  } else {
    lines <- trimws(strsplit(trimws(raw), "\n")[[1]])
    lines <- lines[nchar(lines) > 0]
    if (length(lines) > 0) lines[length(lines)] else trimws(raw)
  }
}
```
