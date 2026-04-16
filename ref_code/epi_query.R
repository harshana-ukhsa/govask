# =============================================================================
# epi_query.R — EpiAsk RAG Pipeline: Query Helpers
# =============================================================================
#
# PURPOSE
# -------
# EpiAsk-specific query helpers, sourced by app.R alongside rag_query.R.
# Provides derive_epi_categories() — derives broad document-type groupings
# from the EpiAsk store filenames using the LLM, with a pattern-matching
# fallback if the LLM is unavailable.
#
# call_llm() and parse_answer() are defined in rag_query.R and must be
# sourced before this file.
# =============================================================================

# =============================================================================
# EpiAsk: Derive broad document-type categories from filenames
# =============================================================================

#' Derive EpiAsk category labels from a vector of origin file paths
#'
#' Groups filenames into broad document-type categories (e.g. Standard
#' Operating Procedures, Technical Documentation). Response is requested as
#' a single comma-separated line to prevent chain-of-thought leakage.
#'
#' @param origins character vector of file paths (from the EpiAsk DuckDB store)
#' @return sorted character vector of document-type category labels
derive_epi_categories <- function(origins) {
  filenames <- paste(sort(basename(origins)), collapse = "\n")

  prompt <- paste0(
    "Below is a list of internal data science document filenames.\n",
    "Group them into 3-4 broad document-type categories.\n",
    "Describe the TYPE of document, not its subject matter.\n",
    "Example categories: 'Standard Operating Procedures', 'Technical Documentation',\n",
    "'Project & Programme Management', 'Reports & Reviews'.\n",
    "Return the categories as a SINGLE comma-separated line with no other text.\n\n",
    "Documents:\n", filenames, "\n\nCategories:"
  )

  raw <- tryCatch(call_llm(prompt), error = function(e) NULL)

  if (!is.null(raw)) {
    answered <- parse_answer(raw)
    # Take only the first non-empty line (guards against multi-line leakage)
    first_line <- trimws(strsplit(answered, "\n")[[1]])
    first_line <- first_line[nchar(first_line) > 0][1]
    if (!is.na(first_line) && nchar(first_line) > 0) {
      cats <- trimws(strsplit(first_line, ",")[[1]])
      cats <- cats[nchar(cats) > 2 & nchar(cats) < 60]
      cats <- cats[!grepl("\\.pdf|\\.docx|\\.xlsx|\\.pptx|\\.html|\\.md|\\.txt", cats)]
      if (length(cats) > 0) return(sort(cats))
    }
  }

  # Pattern-matching fallback
  message("[EpiAsk] LLM category call failed or returned unusable output; using fallback.")
  rules <- list(
    list(pattern = "(?i)sop|standard.operating|on.call|inbox",
         label   = "Standard Operating Procedures"),
    list(pattern = "(?i)dashboard|documentation|technical|r.package|rds|igas",
         label   = "Technical Documentation"),
    list(pattern = "(?i)time.box|programme|project|review|weekly|update",
         label   = "Project & Programme Management"),
    list(pattern = "(?i)report|pptx|survey|assessment|minutes",
         label   = "Reports & Reviews")
  )
  basenames <- basename(origins)
  matched <- vapply(rules, function(r) {
    if (any(grepl(r$pattern, basenames, perl = TRUE))) r$label else NA_character_
  }, character(1))
  matched <- matched[!is.na(matched)]
  if (length(matched) == 0) matched <- "Other"
  sort(matched)
}
