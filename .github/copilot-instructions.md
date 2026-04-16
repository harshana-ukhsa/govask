# GitHub Copilot — Project Instructions

## What this project is

This is a RAG (Retrieval-Augmented Generation) document intelligence pipeline built entirely in R.
It ingests government guidance documents in multiple formats, indexes them in a persistent DuckDB store using BM25 full-text search, and answers plain-English questions using an internally-hosted LLM — all via a Shiny web interface.

This is a cross-government hackathon entry (Challenge 2: Unlocking the Dark Data).
The team is from UKHSA Public Health Data Science.

## Language and ecosystem

- Language: **R only**. Do not suggest Python, Node.js, shell scripts, or any external binaries.
- Style: **tidyverse conventions** — snake_case, pipe operator `|>`, explicit `library()` calls at the top of each script.
- All dependencies must be **pure CRAN packages** — no system-level installs are possible (restricted government laptops).

## Key packages and their roles

| Package | Role |
|---|---|
| `ragnar` | Document chunking, DuckDB store creation, BM25 retrieval |
| `ellmer` | OpenAI-compatible LLM client (fallback path) |
| `httr2` | Primary LLM caller via `/v1/completions` (legacy endpoint) |
| `pdftools` | PDF text extraction |
| `officer` | DOCX text extraction |
| `readxl` | XLSX/XLS extraction |
| `readr` | TXT and CSV extraction |
| `commonmark` | Markdown to plain text stripping |
| `xml2` + `rvest` | HTML text extraction |
| `shiny` | Web interface |
| `bslib` | Shiny theming |
| `DT` | Interactive source citation table in Shiny |
| `shinycssloaders` | Loading spinner for LLM response wait |

## Architecture (top to bottom)

```
challenge-2/ documents (PDF, DOCX, XLSX, TXT, MD, HTML)
    ↓  ingest_all.R  — PARSER_REGISTRY dispatch by file extension
data/rag_store.duckdb  — ragnar chunks + BM25 index + metadata
    ↓  rag_query.R  — BM25 retrieval, prompt builder, LLM call
    ↓  app.R  — R Shiny interface
Browser  — question in, grounded answer + source citation table out
```

## LLM endpoint

- The internal LLM uses the **legacy `/v1/completions` API**, not `/v1/chat/completions`.
- Credentials are loaded from `.Renviron`: `LLM_URL`, `LLM_MODEL`, `GPT_TOKEN`.
- All LLM calls use `httr2`. Do not default to `ellmer::chat_openai_compatible()` unless explicitly asked.
- Response shape: `choices[[1]]$text` — trim whitespace and strip the `assistantfinal` reasoning prefix.

## Coding conventions

- Wrap **all** LLM and ragnar calls in `tryCatch()` with informative error messages.
- Use `req()` in Shiny server functions to guard inputs before use.
- Define file path constants (`STORE_PATH`, `DATA_DIR`) once at the top of each script — never hardcode paths inside functions.
- Every file parser must return `character(1)` — a single collapsed string of plain text.
- Attach `origin = file_path` and `file_type = tools::file_ext(file_path)` as metadata when creating `MarkdownDocument()` objects.
- Use `message()` for progress output, not `print()` or `cat()`.
- Do not use `attach()` or `<<-` for global state.

## What NOT to suggest

- Do not suggest `reticulate` or any Python bridge.
- Do not suggest installing system packages (e.g. `apt-get`, `brew`, `choco`).
- Do not suggest `magrittr` `%>%` — use base R `|>`.
- Do not suggest `plumber` or API servers — the interface is Shiny only.
- Do not suggest external vector databases (Pinecone, Weaviate, etc.) — the store is DuckDB only.
