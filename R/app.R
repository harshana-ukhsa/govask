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
source(file.path(APP_DIR, "rag_query.R"))

# Load credentials from .Renviron (LLM_URL, LLM_MODEL, GPT_TOKEN)
readRenviron(here::here(".Renviron"))

# ── Constants ─────────────────────────────────────────────────────────────────
STORE_PATH <- here::here("data", "rag_store.duckdb")
TOP_K      <- 5L

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Shared state ────────────────────────────────────────────────────────────
  state <- reactiveValues(
    answer         = NULL,
    sources        = NULL,
    low_confidence = FALSE,
    loading        = FALSE
  )

  # ── Store connection (once per session) ─────────────────────────────────────
  store <- tryCatch(
    ragnar::ragnar_store_connect(STORE_PATH, read_only = TRUE),
    error = function(e) {
      shiny::showNotification(
        paste("Store connection failed:", conditionMessage(e)),
        type     = "error",
        duration = NULL
      )
      NULL
    }
  )

  # Separate direct DuckDB connection for metadata queries (sidebar counts/filters).
  # ragnar's store object does not reliably expose $con for DBI queries.
  meta_con <- tryCatch(
    DBI::dbConnect(duckdb::duckdb(), dbdir = STORE_PATH, read_only = TRUE),
    error = function(e) {
      message("Metadata connection failed: ", conditionMessage(e))
      NULL
    }
  )
  session$onSessionEnded(function() {
    if (!is.null(meta_con)) DBI::dbDisconnect(meta_con, shutdown = TRUE)
  })

  # ── Sidebar: corpus summary ──────────────────────────────────────────────────
  output$corpus_summary <- renderUI({
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

  # ── Sidebar: file-type filter ────────────────────────────────────────────────
  # The ragnar chunks table has no file_type column; derive from origin paths.
  output$type_filter <- renderUI({
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
      inputId  = "file_type_filter",
      label    = NULL,
      choices  = types,
      selected = types
    )
  })

  # ── Submit: RAG retrieval + LLM generation ───────────────────────────────────
  observeEvent(input$submit, {
    req(input$question)
    req(nchar(trimws(input$question)) > 0)
    req(store)

    state$loading        <- TRUE
    state$answer         <- NULL
    state$sources        <- NULL
    state$low_confidence <- FALSE

    # Retrieve top-K chunks via BM25
    top_chunks <- tryCatch(
      ragnar::ragnar_retrieve_bm25(store, input$question, top_k = TOP_K),
      error = function(e) {
        shiny::showNotification(
          paste("Retrieval error:", conditionMessage(e)),
          type = "error", duration = 8
        )
        NULL
      }
    )

    if (is.null(top_chunks) || nrow(top_chunks) == 0) {
      state$answer  <- "No relevant content found in the indexed documents."
      state$loading <- FALSE
      return()
    }

    # Apply file-type filter — derive type from origin as ragnar has no file_type column
    selected_types <- input$file_type_filter
    if (!is.null(selected_types) && length(selected_types) > 0) {
      derived_types <- tools::file_ext(top_chunks$origin)
      top_chunks    <- top_chunks[derived_types %in% selected_types, ]
    }

    if (nrow(top_chunks) == 0) {
      state$answer  <- "No results matched the selected file-type filters."
      state$loading <- FALSE
      return()
    }

    # Flag low confidence when the best BM25 score is below threshold
    state$low_confidence <- max(top_chunks$metric_value, na.rm = TRUE) < 1.0

    # Build grounded prompt and call LLM
    prompt <- build_rag_prompt(input$question, top_chunks)

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
                     "LLM call failed — check LLM_URL and GPT_TOKEN in .Renviron."
    state$sources <- top_chunks
    state$loading <- FALSE
  })

  # ── Answer panel ─────────────────────────────────────────────────────────────
  output$answer_panel <- renderUI({
    if (is.null(state$answer)) {
      return(
        tags$div(
          style = "color:#888; font-style:italic;",
          "Enter a question above and click \u2018Search documents\u2019 to begin."
        )
      )
    }

    warning_div <- if (isTRUE(state$low_confidence)) {
      tags$div(
        style = "color:#D4860B; font-weight:bold; margin-bottom:10px;",
        "\u26A0 Low confidence \u2014 retrieved context may not directly address this question."
      )
    } else {
      NULL
    }

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

  # ── Source citation table ────────────────────────────────────────────────────
  output$has_sources <- reactive({ !is.null(state$sources) })
  outputOptions(output, "has_sources", suspendWhenHidden = FALSE)

  output$sources_table <- DT::renderDataTable({
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

shinyApp(ui, server)
