library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)
library(ragnar)
library(httr2)
library(here)
library(duckdb)
library(commonmark)

get_app_dir <- function() {
  file_arg_prefix <- "--file="
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grepl(file_arg_prefix, args)]

  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub(file_arg_prefix, "", file_arg[1]))))
  }

  if (!is.null(sys.frames()[[1]]$ofile)) {
    return(dirname(normalizePath(sys.frames()[[1]]$ofile)))
  }

  normalizePath(getwd())
}

APP_DIR <- get_app_dir()

source(file.path(APP_DIR, "ui.R"))
options(.govask_shiny_mode = TRUE)

# Load credentials from .Renviron (LLM_URL, LLM_MODEL, GPT_TOKEN)
# before loading any helper code that may read them at source-time.
readRenviron(here::here(".Renviron"))

# =============================================================================
# RAG PIPELINE: Run setup scripts to rebuild stores before querying
# =============================================================================
# This pipeline ensures stores are up-to-date each time the app starts:
#   1. govuk_api.R  — download UKHSA guidance from GOV.UK API
#   2. rag_setup.R  — ingest documents into data/rag_store.duckdb
#   3. epi_setup.R  — ingest epids docs into data/epids_store.duckdb
#   4. api_setup.R  — ingest govapi docs into data/api_store.duckdb
#   5. rag_query.R  — load query helpers (sourced below)

message("Running RAG pipeline...")

message("  [1/5] Downloading UKHSA content from GOV.UK API...")
tryCatch({
  govuk_env <- new.env(parent = globalenv())
  source(here::here("ref_code", "govuk_api.R"), local = govuk_env)
  # Download UKHSA health protection guidance from GOV.UK
  govuk_env$download_govuk_documents(
    query              = "health protection guidance",
    count              = 20,
    output_dir         = here::here("data", "govapi_files"),
    filter_organisations = "uk-health-security-agency",
    file_format        = "txt",
    delay              = 0.15
  )
}, error = function(e) {
  warning("govuk_api.R failed: ", conditionMessage(e))
})

message("  [2/5] Running rag_setup.R...")
tryCatch(

  source(here::here("ref_code", "rag_setup.R"), local = new.env()),
  error = function(e) {
    warning("rag_setup.R failed: ", conditionMessage(e))
  }
)

message("  [3/5] Running epi_setup.R...")
tryCatch(
  source(here::here("ref_code", "epi_setup.R"), local = new.env()),
  error = function(e) {
    warning("epi_setup.R failed: ", conditionMessage(e))
  }
)

message("  [4/5] Running api_setup.R...")
tryCatch(
  source(here::here("ref_code", "api_setup.R"), local = new.env()),
  error = function(e) {
    warning("api_setup.R failed: ", conditionMessage(e))
  }
)

message("  [5/5] Loading rag_query.R helpers...")

# Load reusable RAG helpers into an app-scoped environment so that
# CLI-oriented top-level code does not pollute the Shiny app environment.
rag_query_env <- new.env(parent = globalenv())
rag_query_error <- tryCatch(
  {
    sys.source(here::here("ref_code", "rag_query.R"), envir = rag_query_env)
    NULL
  },
  error = function(e) {
    e
  }
)

if (length(ls(rag_query_env, all.names = TRUE)) > 0) {
  list2env(
    mget(ls(rag_query_env, all.names = TRUE), envir = rag_query_env),
    envir = environment()
  )
}

if (inherits(rag_query_error, "error") &&
    length(ls(rag_query_env, all.names = TRUE)) == 0) {
  stop(
    paste(
      "Failed to load RAG query helpers for the Shiny app:",
      conditionMessage(rag_query_error)
    )
  )
}

message("RAG pipeline complete.")

# ── Constants ─────────────────────────────────────────────────────────────────
STORE_PATH     <- here::here("data", "rag_store.duckdb")
EPI_STORE_PATH <- here::here("data", "epids_store.duckdb")
API_STORE_PATH <- here::here("data", "api_store.duckdb")
TOP_K          <- 5L

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Helper: build server-side logic for one RAG tab ─────────────────────────
  # ns       — ID prefix matching ui.R ("gov", "epi", or "api")
  # store_path — path to the tab's DuckDB store
  rag_server <- function(ns, store_path) {

    state <- reactiveValues(
      answer         = NULL,
      sources        = NULL,
      low_confidence = FALSE
    )

    # Store connection
    store <- tryCatch(
      ragnar::ragnar_store_connect(store_path, read_only = TRUE),
      error = function(e) {
        shiny::showNotification(
          paste0("[", ns, "] Store connection failed: ", conditionMessage(e)),
          type = "error", duration = NULL
        )
        NULL
      }
    )

    # Direct DuckDB connection for metadata queries
    meta_con <- tryCatch(
      DBI::dbConnect(duckdb::duckdb(), dbdir = store_path, read_only = TRUE),
      error = function(e) {
        message("[", ns, "] Metadata connection failed: ", conditionMessage(e))
        NULL
      }
    )
    session$onSessionEnded(function() {
      if (!is.null(meta_con)) DBI::dbDisconnect(meta_con, shutdown = FALSE)
    })

    # ── Corpus summary ─────────────────────────────────────────────────────────
    output[[paste0(ns, "_corpus_summary")]] <- renderUI({
      if (is.null(meta_con)) {
        return(tags$p(style = "color:red;", "Store not connected."))
      }
      n_docs <- tryCatch(
        DBI::dbGetQuery(meta_con, "SELECT COUNT(DISTINCT origin) AS n FROM chunks")$n,
        error = function(e) NA_integer_
      )
      n_chunks <- tryCatch(
        DBI::dbGetQuery(meta_con, "SELECT COUNT(*) AS n FROM chunks")$n,
        error = function(e) NA_integer_
      )
      tags$div(
        tags$p(paste0(n_docs, " documents indexed")),
        tags$p(paste0(n_chunks, " chunks searchable"))
      )
    })

    # ── File-type filter ───────────────────────────────────────────────────────
    output[[paste0(ns, "_type_filter")]] <- renderUI({
      if (is.null(meta_con)) {
        return(tags$p(style = "color:#888; font-style:italic;", "Store not connected."))
      }
      origins <- tryCatch(
        DBI::dbGetQuery(
          meta_con,
          "SELECT DISTINCT origin FROM chunks WHERE origin IS NOT NULL"
        )$origin,
        error = function(e) character(0)
      )
      types <- sort(unique(tools::file_ext(origins)))
      types <- types[nchar(types) > 0]
      if (length(types) == 0) {
        return(tags$p(style = "color:#888; font-style:italic;", "No file types found."))
      }
      checkboxGroupInput(
        inputId  = paste0(ns, "_file_type_filter"),
        label    = NULL,
        choices  = types,
        selected = types
      )
    })

    # ── Submit ─────────────────────────────────────────────────────────────────
    observeEvent(input[[paste0(ns, "_submit")]], {
      req(input[[paste0(ns, "_question")]])
      req(nchar(trimws(input[[paste0(ns, "_question")]])) > 0)
      req(store)

      state$answer         <- NULL
      state$sources        <- NULL
      state$low_confidence <- FALSE

      top_chunks <- tryCatch(
        ragnar::ragnar_retrieve_bm25(store, input[[paste0(ns, "_question")]], top_k = TOP_K),
        error = function(e) {
          shiny::showNotification(
            paste("Retrieval error:", conditionMessage(e)),
            type = "error", duration = 8
          )
          NULL
        }
      )

      if (is.null(top_chunks) || nrow(top_chunks) == 0) {
        state$answer <- "No relevant content found in the indexed documents."
        return()
      }

      selected_types <- input[[paste0(ns, "_file_type_filter")]]
      if (!is.null(selected_types) && length(selected_types) > 0) {
        derived_types <- tools::file_ext(top_chunks$origin)
        top_chunks    <- top_chunks[derived_types %in% selected_types, ]
      }

      if (nrow(top_chunks) == 0) {
        state$answer <- "No results matched the selected file-type filters."
        return()
      }

      state$low_confidence <- max(top_chunks$metric_value, na.rm = TRUE) < 1.0

      prompt <- build_rag_prompt(
        input[[paste0(ns, "_question")]],
        top_chunks,
        low_confidence = state$low_confidence
      )

      raw <- tryCatch(
        call_llm(prompt),
        error = function(e) {
          shiny::showNotification(
            paste("LLM error:", conditionMessage(e)),
            type = "error", duration = 8
          )
          NULL
        }
      )

      state$answer  <- if (!is.null(raw)) parse_answer(raw) else
                       "LLM call failed \u2014 check LLM_URL and GPT_TOKEN in .Renviron."
      state$sources <- top_chunks
    })

    # ── Answer panel ───────────────────────────────────────────────────────────
    output[[paste0(ns, "_answer_panel")]] <- renderUI({
      if (is.null(state$answer)) {
        return(tags$div(
          style = "color:#888; font-style:italic;",
          "Enter a question above and click \u2018Search documents\u2019 to begin."
        ))
      }
      warning_div <- if (isTRUE(state$low_confidence)) {
        tags$div(
          style = "color:#D4860B; font-weight:bold; margin-bottom:10px;",
          "\u26A0 Low confidence \u2014 retrieved context may not directly address this question."
        )
      } else NULL

      tags$div(
        warning_div,
        tags$div(
          style = paste(
            "background:#E6F4F1; padding:14px;",
            "border-left:5px solid #1A7A6E;",
            "border-radius:4px;",
            "font-size:15px; line-height:1.6;"
          ),
          HTML(commonmark::markdown_html(state$answer))
        )
      )
    })

    # ── Source citation table ──────────────────────────────────────────────────
    output[[paste0(ns, "_has_sources")]] <- reactive({ !is.null(state$sources) })
    outputOptions(output, paste0(ns, "_has_sources"), suspendWhenHidden = FALSE)

    output[[paste0(ns, "_sources_table")]] <- DT::renderDataTable({
      req(state$sources)
      sources_df <- data.frame(
        Document = basename(state$sources$origin),
        Type     = tools::file_ext(state$sources$origin),
        Score    = round(state$sources$metric_value, 2),
        Excerpt  = substr(state$sources$text, 1, 200),
        stringsAsFactors = FALSE
      )
      DT::datatable(
        sources_df,
        options  = list(pageLength = 5, dom = "t", scrollX = TRUE),
        rownames = FALSE,
        colnames = c("Document", "Type", "BM25 Score", "Excerpt")
      )
    })
  }

  # ── Instantiate all tabs ─────────────────────────────────────────────────────
  rag_server("gov", STORE_PATH)
  rag_server("epi", EPI_STORE_PATH)
  rag_server("api", API_STORE_PATH)
}

shinyApp(ui, server)
