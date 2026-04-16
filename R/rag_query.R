library(httr2)

# Reusable RAG pipeline functions extracted from ref_code/rag_query.R.
# Credentials (LLM_URL, LLM_MODEL, GPT_TOKEN) must be present in the
# environment before calling call_llm() — load .Renviron beforehand.

#' Build a grounded RAG prompt
#'
#' @param question Plain-English question string
#' @param chunks_tbl Tibble from ragnar::ragnar_retrieve_bm25(), must have a `text` column
#' @return character(1) — complete prompt ready to send to the LLM
build_rag_prompt <- function(question, chunks_tbl) {
  context <- paste(chunks_tbl$text, collapse = "\n\n")
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

#' Call the internal LLM via the legacy /v1/completions endpoint
#'
#' @param prompt character(1) — full prompt string
#' @return character(1) — raw text response from the LLM
call_llm <- function(prompt) {
  llm_url   <- Sys.getenv("LLM_URL")
  llm_model <- Sys.getenv("LLM_MODEL")
  gpt_token <- Sys.getenv("GPT_TOKEN")

  missing_vars <- c(
    if (!nzchar(llm_url)) "LLM_URL",
    if (!nzchar(llm_model)) "LLM_MODEL",
    if (!nzchar(gpt_token)) "GPT_TOKEN"
  )

  if (length(missing_vars) > 0) {
    stop(
      "call_llm() requires non-empty environment variables: ",
      paste(missing_vars, collapse = ", "),
      call. = FALSE
    )
  }

  tryCatch({
    resp <- httr2::request(paste0(llm_url, "/v1/completions")) |>
      httr2::req_headers(
        Authorization = paste("Bearer", gpt_token)
      ) |>
      httr2::req_body_json(list(
        model       = llm_model,
        prompt      = prompt,
        max_tokens  = 300L,
        temperature = 0.1
      )) |>
      httr2::req_timeout(40) |>
      httr2::req_perform()

    resp_json <- httr2::resp_body_json(resp)

    if (
      is.null(resp_json$choices) ||
      length(resp_json$choices) < 1 ||
      is.null(resp_json$choices[[1]]$text) ||
      !is.character(resp_json$choices[[1]]$text) ||
      length(resp_json$choices[[1]]$text) < 1
    ) {
      stop(
        "unexpected LLM response shape: expected choices[[1]]$text",
        call. = FALSE
      )
    }

    trimws(resp_json$choices[[1]]$text)
  }, error = function(e) {
    stop("call_llm() failed: ", conditionMessage(e), call. = FALSE)
  })
}

#' Strip the internal reasoning prefix from a raw LLM response
#'
#' @param raw character(1) — raw text returned by call_llm()
#' @return character(1) — clean answer text
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
