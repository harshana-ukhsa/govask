# =============================================================================
# rag_query.R — RAG Pipeline: Stage 2 — Retrieval & Generation
# =============================================================================
#
# PURPOSE
# -------
# This script is the second stage of the RAG pipeline. It:
#   1. Connects to the DuckDB store built by rag_setup.R
#   2. Accepts a plain-English question from the user
#   3. RETRIEVES the most relevant document chunks using BM25 search
#   4. AUGMENTS a prompt with those chunks as context
#   5. GENERATES an answer by sending the prompt to the internal LLM
#   6. Prints the answer, then loops back for the next question
#
# This separation matters: rag_setup.R is slow (reads and indexes PDFs);
# rag_query.R is fast (just searches an existing index and calls the LLM).
# You only need to re-run rag_setup.R when documents change.
#
# PREREQUISITES
# -------------
#   1. Run rag_setup.R to create data/rag_store.duckdb
#   2. Fill in .Renviron with LLM_URL, LLM_MODEL, GPT_TOKEN
#
# USAGE
#   source("rag_query.R")         # from R console
#   Rscript rag_query.R           # from terminal
# =============================================================================

library(ragnar)  # retrieval from the DuckDB store
library(ellmer)  # OpenAI-compatible LLM client
library(here)    # here: reliable path resolution regardless of working directory

# =============================================================================
# STEP 1: Load secrets from .Renviron
# =============================================================================
# R's convention for project-level environment variables is a .Renviron file
# in the project root. It is loaded automatically when R starts, but we call
# readRenviron() explicitly here so the script works whether sourced from a
# fresh session or an existing one.
#
# The .Renviron file is git-ignored — secrets never enter version control.
# This is the R equivalent of Python's `export GPT_TOKEN=...` shell approach,
# but scoped to the project and stored persistently for the developer.
#
# Using here::here() ensures we find .Renviron even if the working directory
# isn't the project root.

readRenviron(here::here(".Renviron"))

llm_url   <- Sys.getenv("LLM_URL")
llm_model <- Sys.getenv("LLM_MODEL")
gpt_token <- Sys.getenv("GPT_TOKEN")

# Fail loudly if the user hasn't filled in .Renviron yet
if (nchar(llm_url) == 0 || llm_url == "https://your-llm-endpoint-here") {
  stop("Set LLM_URL in .Renviron before running.")
}
if (nchar(gpt_token) == 0 || gpt_token == "your_token_here") {
  stop("Set GPT_TOKEN in .Renviron before running.")
}

# =============================================================================
# STEP 2: Connect to the DuckDB store (read-only)
# =============================================================================
# ragnar_store_connect() opens the .duckdb file without loading it into memory.
# read_only = TRUE means this session cannot accidentally modify the index —
# important if multiple users or processes share the same store file.
#
# The BM25 index built by rag_setup.R is already inside this file; there is
# nothing to rebuild here.

STORE_PATH <- here::here("data", "rag_store.duckdb")

if (!file.exists(STORE_PATH)) {
  stop("Store not found at '", STORE_PATH, "'. Run rag_setup.R first.")
}

store <- ragnar_store_connect(STORE_PATH, read_only = TRUE)
message("Store connected: ", STORE_PATH)

# =============================================================================
# STEP 3: Define the RAG prompt builder
# =============================================================================
# The prompt is the most important design decision in a RAG system.
# A well-designed prompt:
#   - Grounds the LLM in the retrieved context (prevents hallucination)
#   - Gives explicit fallback behaviour ("say X if you don't know")
#   - Keeps the answer style consistent and concise
#
# The structure used here is called a "stuffing" prompt — we literally
# stuff the retrieved text into the prompt alongside the question.
# This is the simplest RAG pattern and works well when chunks are small.
#
# The function takes:
#   question   — the user's raw question string
#   chunks_tbl — a tibble returned by ragnar_retrieve_bm25(), with a `text`
#                column containing the retrieved chunk content

build_rag_prompt <- function(question, chunks_tbl) {
  # Join all retrieved chunks into one context block.
  # Separating chunks with "\n\n" helps the LLM treat them as distinct passages.
  context <- paste(chunks_tbl$text, collapse = "\n\n")

  # The prompt instructs the LLM to use ONLY the provided context.
  # This is the core RAG constraint — without it, the LLM may draw on its
  # training data and produce answers that aren't in your documents.
  paste0(
    "Answer the question using only the information in the context.\n",
    "Keep your answer short and helpful.\n",
    "Do not explain how you got the answer.\n",
    "Do not mention the context.\n",
    "If the answer is not in the context, say: ",
    "\"I cannot answer this from the provided documents.\"\n\n",
    "Context:\n", context, "\n\n",
    "Question: ", question, "\n\n",
    "Answer:"
  )
}

# =============================================================================
# STEP 4: Define the LLM caller
# =============================================================================
# ellmer provides a clean R interface to any OpenAI-compatible API.
# chat_openai_compatible() works with any server that implements the
# /v1/chat/completions endpoint — including vLLM, Ollama, and many others.
#
# We create a FRESH chat object for each question (inside the loop below).
# This is intentional: it prevents conversation history from accumulating
# across questions, which would waste context window space and could cause
# earlier answers to influence later ones.
#
# ENDPOINT NOTE
# If your server only exposes the older /v1/completions (non-chat) API,
# uncomment the httr2 fallback block below and comment out the ellmer block.
# The Python version uses /v1/completions — if you see authentication errors
# or 404s, this is the most likely cause.

call_llm <- function(prompt) {

  # The internal endpoint exposes the legacy /v1/completions API (not the newer
  # /v1/chat/completions). We use httr2 to POST directly — this mirrors exactly
  # what the Python version does with the `requests` library.
  #
  # httr2 uses a pipe-based builder pattern:
  #   request()          — create a request object for the URL
  #   req_headers()      — add HTTP headers (auth token, content type)
  #   req_body_json()    — attach the JSON payload (auto-sets Content-Type)
  #   req_timeout()      — fail cleanly if the server is slow
  #   req_perform()      — send the request and return the response
  #   resp_body_json()   — parse the JSON response body
  resp <- httr2::request(paste0(llm_url, "/v1/completions")) |>
    httr2::req_headers(
      Authorization = paste("Bearer", Sys.getenv("GPT_TOKEN"))
    ) |>
    httr2::req_body_json(list(
      model       = llm_model,
      prompt      = prompt,
      max_tokens  = 300L,
      temperature = 0.1   # low temperature = more deterministic, less creative
    )) |>
    httr2::req_timeout(40) |>
    httr2::req_perform()

  # The /v1/completions response has the shape:
  #   { "choices": [ { "text": "..." } ] }
  # We extract the first choice's text, trimming any leading whitespace.
  trimws(httr2::resp_body_json(resp)$choices[[1]]$text)

  # ---- Alternative: ellmer chat_openai_compatible (/v1/chat/completions) ----
  # Uncomment below (and comment out httr2 block above) if your endpoint is
  # upgraded to support the newer /v1/chat/completions API.
  #
  # chat <- ellmer::chat_openai_compatible(
  #   base_url    = llm_url,
  #   name        = "internal-llm",
  #   model       = llm_model,
  #   credentials = \() Sys.getenv("GPT_TOKEN"),
  #   echo        = "none"
  # )
  # chat$chat(prompt)
}

# =============================================================================
# STEP 5: Parse the raw LLM output
# =============================================================================
# This model prefixes its answer with internal reasoning before a special
# "assistantfinal" marker. We strip everything up to and including that marker
# so only the clean answer is shown to the user.
# If the marker is absent (e.g. a different model is used), we fall back to
# returning the last non-empty line of the response.
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

# =============================================================================
# STEP 6: Interactive query loop
# =============================================================================
# The loop runs until the user types "exit". For each question it:
#   1. Retrieves the top-3 most relevant chunks from DuckDB using BM25
#   2. Builds a grounded prompt (context + question)
#   3. Calls the LLM and prints the answer
#   4. Wraps the LLM call in tryCatch() so a failed API call doesn't crash
#      the session — the user gets an informative error and can try again

message("\nRAG demo ready. Type 'exit' to quit.\n")

repeat {
  question <- readline("Ask a question about the indexed documents:\n> ")
  question <- trimws(question)

  if (tolower(question) == "exit") {
    message("Goodbye.")
    break
  }

  if (nchar(question) == 0) next

  # ---------------------------------------------------------------------------
  # RETRIEVE: BM25 search against the DuckDB index
  # ---------------------------------------------------------------------------
  # ragnar_retrieve_bm25() runs the BM25 algorithm across all stored chunks
  # and returns a tibble ordered by relevance score (highest first).
  #
  # top_k = 3: retrieve the 3 most relevant chunks.
  # More chunks = more context for the LLM, but also a larger prompt.
  # 3 is a good starting point; try 5 if answers seem incomplete.
  #
  # The returned tibble has columns: origin, doc_id, chunk_id, start, end,
  # metric_name, metric_value, context, text
  # We use `text` (the chunk content) in the prompt.
  top_chunks <- ragnar_retrieve_bm25(store, question, top_k = 3L)

  if (nrow(top_chunks) == 0) {
    message("No relevant content found in the indexed documents.\n")
    next
  }

  # ---------------------------------------------------------------------------
  # AUGMENT: build the grounded prompt
  # ---------------------------------------------------------------------------
  prompt <- build_rag_prompt(question, top_chunks)

  message("\nAsking LLM...\n")

  # ---------------------------------------------------------------------------
  # GENERATE: call the LLM, parse the answer, and print it
  # ---------------------------------------------------------------------------
  raw_answer <- tryCatch(
    call_llm(prompt),
    error = function(e) {
      paste0(
        "LLM call failed: ", conditionMessage(e),
        "\nCheck LLM_URL/GPT_TOKEN in .Renviron, or switch to the httr2 ",
        "fallback in call_llm() if your endpoint uses /v1/completions."
      )
    }
  )

  answer <- parse_answer(raw_answer)

  message("Question: ", question, "\n")
  message("Answer:\n")
  message(answer, "\n")
}
