# 🏛️ GovAsk — Government Document Intelligence

> **AI Engineering Lab Hackathon 2026 · Challenge 2: Unlocking the Dark Data**  
> Team EpiDS: Harshana Liyanage · Emma Parker · Frederick Sloots · UKHSA Epidemiology Data Science

[View presentation slides →](https://htmlpreview.github.io/?https://raw.githubusercontent.com/harshana-ukhsa/govask/dev/docs/presentation.html)

---

## The problem

Government produces an enormous volume of guidance, policy, and procedural documentation. Most of it is published. Very little of it is genuinely findable under time pressure — and almost none of it is queryable by a machine.

A frontline adviser needs the right guidance quickly. They find three documents with similar names and different dates. They give an answer based on whichever version they found fastest. It may not be the right one.

**This is not a failure of effort. It is a failure of infrastructure.**

<img src="docs/problem.png" alt="The problem" width="800">

---

## What we built

**GovAsk** is a Retrieval-Augmented Generation (RAG) document intelligence system with three complementary interfaces, all in a single browser-based Shiny app:

### GovAsk — Local document Q&A
Query a curated corpus of government guidance documents (PDF, DOCX, HTML, TXT, Markdown) indexed from local files. Answers are grounded in the source documents, every response cites the exact file it came from, and a collapsible source citation table shows BM25 relevance scores and excerpts for full auditability.

### APIAsk — Live GOV.UK content search
On every app startup, APIAsk automatically fetches current UKHSA guidance directly from the **GOV.UK Search and Content APIs** (`gov.uk/api/search.json` · `gov.uk/api/content/{path}`), indexes it into a live DuckDB store, and makes it immediately queryable. Users always see answers grounded in the latest published guidance — no manual document management required.

### EpiAsk — Internal knowledge base (extensibility demonstration)
EpiAsk demonstrates how the same pipeline can be pointed at any internal document collection. In our team's context, we intend to use this pattern to interrogate our **UKHSA Confluence documentation base** — SOPs, technical guides, and data standards — giving epidemiologists and data scientists instant answers from institutional knowledge that currently lives only in wikis and shared drives.

---

## GovASK Screenshot

<img src="docs/screen.png" alt="GovAsk screenshot" width="800">

---
## Architecture
<img src="docs/architecture.png" alt="GovAsk architecture" width="800">

---

## Key strengths

| Strength | Detail |
|---|---|
| **Live GOV.UK integration** | APIAsk fetches and indexes current UKHSA guidance on startup via public APIs — no stale documents |
| **Fully auditable answers** | Every answer cites the source filename; BM25 scores and excerpts shown in a collapsible citation table |
| **No data leaves the network** | All LLM calls go to GPT-OSS 120B on UKHSA's internal OpenShift AI cluster — architectural guarantee, not a vendor promise |
| **Extensible to any corpus** | The same three-tab pattern can be pointed at Confluence, SharePoint, or any document store — one folder change |
| **R-only, zero system installs** | Runs on restricted government laptops — no Python, no containers, no admin rights required |
| **Low-confidence detection** | When BM25 retrieval is weak, an amber warning is surfaced so users know to verify the answer |

---

## Architecture

```
data/
├── structured_files/   — Local policy documents (PDF, DOCX, HTML, TXT, MD)
├── govapi_files/       — Downloaded live from GOV.UK API on app startup
└── epids_files/        — Internal documents (e.g. Confluence export, SOPs)
         │
         ▼  rag_setup.R / api_setup.R / epi_setup.R
         │    (per-corpus ingestion: extract → chunk → BM25 index)
         │
data/rag_store.duckdb      ← GovAsk index
data/api_store.duckdb      ← APIAsk index  (rebuilt live on startup)
data/epids_store.duckdb    ← EpiAsk index
         │
         ▼  rag_query.R — shared BM25 retrieval + prompt builder + LLM call
         │
         ▼  R/app.R — R Shiny browser interface (three tabs)
              ┌────────────────────────────────────────────────┐
              │  GovAsk │ APIAsk │ EpiAsk                      │
              │  Question input → spinner → grounded answer    │
              │  ▼ Source citation table (doc · score · text)  │
              │  ⚠ Low-confidence warning if BM25 weak         │
              └────────────────────────────────────────────────┘
```

**GOV.UK API pipeline (APIAsk):**
```
App startup
    ↓  govuk_api.R — search GOV.UK for UKHSA guidance (Search API)
    ↓  download_govuk_documents() — fetch full text (Content API)
    ↓  api_setup.R — chunk and index into api_store.duckdb
    ↓  Live and queryable in the APIAsk tab
```

Full corpus indexing completes in under 2 minutes. Query response — retrieval plus LLM generation — is typically under 5 seconds.

### Technical choices

**BM25 retrieval** — transparent, offline, auditable. Every relevance score is explainable. No embedding model or GPU required. A hybrid BM25 + semantic re-ranking approach is the planned next step.

**DuckDB** — the entire index is a single `.duckdb` file that survives restarts, can be backed up, and never requires a running database server.

**Self-hosted LLM (GPT-OSS 120B)** — hosted on UKHSA's internal OpenShift AI cluster. No query data leaves the network. Zero commercial training use by design. The endpoint is OpenAI-compatible — swapping to a newer model requires changing one environment variable.

**R** — the language our analysts already work in. No Python bridge, no new tooling, immediately deployable to existing UKHSA analytical infrastructure. Demonstrates that GitHub Copilot is an effective development tool beyond Python and TypeScript.

---

## Supported file types

| Format | R package | Notes |
|--------|-----------|-------|
| `.pdf` | `pdftools` | Page-by-page extraction, pure R |
| `.docx` | `officer` | Paragraph extraction |
| `.txt` | `readr` | Direct read |
| `.md` | `commonmark` | Markdown syntax stripped to plain text |
| `.html` | `xml2` + `rvest` | Script/style nodes removed before extraction |

---

## How GitHub Copilot shaped this build

We set up the repository for Copilot **before writing any new code** — every suggestion was project-aware from the first prompt.

```
.github/
├── copilot-instructions.md          # Always-on: architecture, packages, conventions
├── instructions/
│   ├── r-coding-standards.instructions.md    # applyTo: **/*.R
│   ├── shiny-ui.instructions.md              # applyTo: R/app.R, R/ui.R
│   └── rag-pipeline.instructions.md          # applyTo: ref_code/*.R
└── skills/
    ├── rag-prompt-engineering/SKILL.md  # Prompt design, citation, confidence patterns
    ├── shiny-component/SKILL.md         # Shiny UI component patterns
    └── marp-presentation/SKILL.md       # Presentation slide templates
```

### Copilot features used

| Feature | Used for |
|---------|----------|
| **Agent mode** | GOV.UK API client (`govuk_api.R`), multi-tab Shiny server, file-type parsers |
| **Copilot Chat + `#file`** | Wiring the three-tab server to shared `rag_query.R` helpers |
| **Inline completions** | `httr2` pipe chains, `tryCatch()` blocks, DuckDB metadata queries |
| **`/explain`** | GOV.UK API response schema; `ragnar_store_connect()` read/write behaviour |
| **`/fix`** | Namespace collision between Shiny tab IDs |
| **Copilot code review** | Reviewing the GOV.UK API integration PR before merging |
| **Custom instructions** | R conventions, package choices, LLM endpoint enforced automatically |
| **Skills** | RAG prompt engineering and Shiny component patterns loaded on demand |

The GOV.UK API integration, multi-corpus Shiny architecture, and the three-tab namespaced reactive pattern were all built in Agent mode sessions using purpose-built Skills. Two team members worked on different tabs in parallel with consistent output because the Skills defined the contract in advance.

---

## Setup

### Prerequisites

```r
source("install_packages.R")
```

All dependencies are pure CRAN packages — no system install rights required.

### Configure LLM credentials

Create `.Renviron` in the project root (git-ignored — never commit it):

```
LLM_URL=https://your-internal-llm-endpoint
LLM_MODEL=your-model-name
GPT_TOKEN=your-token-here
```

### Launch the app

```r
shiny::runApp("R/app.R")
```

On startup the app automatically downloads current UKHSA guidance from GOV.UK, indexes all three corpora, and opens all three tabs ready for queries. No separate indexing step required.

---

## Project structure

```
govask/
├── .github/
│   ├── copilot-instructions.md
│   ├── instructions/            # File-scoped Copilot instructions
│   └── skills/                  # On-demand Copilot skill packages
├── R/
│   ├── app.R                    # Shiny server (three-tab RAG app)
│   └── ui.R                     # Shiny UI (reusable tab panel builder)
├── ref_code/
│   ├── govuk_api.R              # GOV.UK Search + Content API client
│   ├── rag_setup.R              # Ingest local docs → rag_store.duckdb
│   ├── api_setup.R              # Ingest GOV.UK API docs → api_store.duckdb
│   ├── epi_setup.R              # Ingest internal docs → epids_store.duckdb
│   └── rag_query.R              # Shared: BM25 retrieval, prompt builder, LLM call
├── data/
│   ├── structured_files/        # Local government guidance corpus
│   ├── govapi_files/            # Auto-downloaded from GOV.UK API on startup
│   └── epids_files/             # Internal documents (Confluence, SOPs, etc.)
├── docs/
│   └── presentation.html        # Hackathon slide deck
├── install_packages.R
└── README.md
```

---

## Beyond the hackathon — UKHSA use case

The EpiAsk tab demonstrates the direct next step for our team. UKHSA's Epidemiology Data Science division maintains a substantial knowledge base in Confluence: SOPs, data standards, onboarding guides, technical documentation for surveillance systems, and analytical methods. This material is authoritative but effectively unsearchable under time pressure.

Connecting EpiAsk to a Confluence export — or directly to the Confluence REST API — would give every team member instant, cited answers from institutional knowledge that currently requires knowing who to ask. The architecture requires no changes: one new data folder, one new setup script, one new tab.

---

## Security and data governance

- **No data leaves the internal network** — all LLM calls go to GPT-OSS 120B on UKHSA's OpenShift AI cluster
- **Zero commercial training use** — self-hosted model, architectural guarantee not a vendor promise
- **Credentials never in version control** — `.Renviron` is git-ignored
- **Read-only store connections** — the Shiny app cannot corrupt the index during a session
- **GOV.UK API calls are read-only and public** — no authentication, no data submission

---

## Known limitations

| Limitation | Notes |
|------------|-------|
| BM25 keyword matching | Synonym gaps: "housing allowance" won't match "accommodation support". Hybrid BM25 + semantic re-ranking is the planned fix. |
| No cross-document synthesis | LLM answers from top-k chunks only — cannot compare two policies holistically |
| Single-session state | No conversation history — each question is independent |
| Scanned PDFs | `pdftools` returns empty strings for image-only PDFs |
| GOV.UK API network dependency | APIAsk requires outbound access to gov.uk on startup |

---

## What's next

1. **Confluence integration** — connect EpiAsk to UKHSA's Confluence REST API for live institutional knowledge queries
2. **Audit logging** — complete question/answer/source trail for governance
3. **Hybrid retrieval** — BM25 + semantic re-ranking to close the synonym gap
4. **Structured evaluation framework** — repeatable test suite for model upgrade validation
5. **Conversation context** — pass prior turns to the prompt for follow-up questions
6. **WCAG 2.1 AA accessibility audit** — required before any staff-facing deployment

---

## Team

| Person | Role |
|--------|------|
| **Harshana Liyanage** | RAG architecture, GOV.UK API integration, prompt engineering, AI domain expertise |
| **Emma Parker** | Project management, Shiny UI, three-tab interface, demo coordination |
| **Frederick Sloots** | Multi-format ingestion, EpiAsk pipeline, file-type extensions |

Built with [ragnar](https://ragnar.tidyverse.org/) · [R Shiny](https://shiny.posit.co/) · [DuckDB](https://duckdb.org/) · [httr2](https://httr2.r-lib.org/) · [GitHub Copilot](https://github.com/features/copilot)

---

*AI Engineering Lab Hackathon · London · April 2026*  
*Proof-of-concept demonstrator. Not validated for operational or clinical use.*