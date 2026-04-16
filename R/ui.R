library(shiny)
library(bslib)
library(DT)
library(shinycssloaders)

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  theme = bslib::bs_theme(bootswatch = "flatly"),
  titlePanel("GovAsk — Government Document Intelligence"),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      h5("Document corpus"),
      uiOutput("corpus_summary"),
      hr(),
      h5("Filter by file type"),
      uiOutput("type_filter")
    ),

    mainPanel(
      width = 9,

      # ── Question input ───────────────────────────────────────────────────
      textAreaInput(
        inputId     = "question",
        label       = "Ask a question about the indexed documents:",
        rows        = 3,
        width       = "100%",
        placeholder = "e.g. What is the eligibility threshold for housing support?"
      ),
      actionButton("submit", "Search documents", class = "btn-primary"),
      br(), br(),

      # ── Answer panel ─────────────────────────────────────────────────────
      shinycssloaders::withSpinner(
        uiOutput("answer_panel"),
        type  = 4,
        color = "#1A7A6E"
      ),
      br(),

      # ── Source citation table ─────────────────────────────────────────────
      conditionalPanel(
        condition = "output.has_sources",
        h5("Source documents retrieved"),
        DT::dataTableOutput("sources_table")
      )
    )
  )
)
