library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)

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

# ── Constants ─────────────────────────────────────────────────────────────────
STORE_PATH <- file.path(APP_DIR, "..", "data", "rag_store.duckdb")
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

  # ── Sidebar: corpus summary placeholder ─────────────────────────────────────
  output$corpus_summary <- renderUI({
    tags$div(
      tags$p(
        style = "color:#888; font-style:italic;",
        "RAG store not yet connected."
      ),
      tags$p(
        style = "color:#888; font-style:italic;",
        "Ingest documents to populate the index."
      )
    )
  })

  # ── Sidebar: file-type filter placeholder ───────────────────────────────────
  output$type_filter <- renderUI({
    tags$p(
      style = "color:#888; font-style:italic;",
      "Available once documents are indexed."
    )
  })

  # ── Submit: placeholder — RAG pipeline not yet wired ────────────────────────
  observeEvent(input$submit, {
    req(input$question)
    req(nchar(trimws(input$question)) > 0)

    state$loading        <- TRUE
    state$answer         <- NULL
    state$sources        <- NULL
    state$low_confidence <- FALSE

    # TODO: replace this block with ragnar retrieval + LLM call once the
    #       RAG pipeline (rag_query.R) is available.
    state$answer  <- paste0(
      "[Placeholder] RAG pipeline not yet connected.\n\n",
      "Your question was: \u201C", trimws(input$question), "\u201D\n\n",
      "Once the document store has been built and rag_query.R is wired in, ",
      "a grounded answer will appear here."
    )
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
          "font-size:15px; line-height:1.6;",
          "white-space:pre-wrap;"
        ),
        state$answer
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
      Type     = state$sources$file_type,
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
