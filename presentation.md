---
marp: true
theme: default
paginate: true
style: |
  :root {
    --color-background: #FFFFFF;
    --color-foreground: #1A1A1A;
    --color-highlight: #1A7A6E;
    --color-dimmed: #4A5568;
  }
  section {
    font-family: 'Segoe UI', Arial, sans-serif;
    font-size: 28px;
    color: #1A1A1A;
    background: #FFFFFF;
    padding: 48px 64px;
  }
  section h1 {
    color: #1A7A6E;
    font-size: 44px;
    border-bottom: 3px solid #1A7A6E;
    padding-bottom: 12px;
    margin-bottom: 24px;
  }
  section h2 {
    color: #1A1A1A;
    font-size: 36px;
  }
  section.cover {
    background: #0E5C52;
    color: #FFFFFF;
    justify-content: center;
    text-align: center;
  }
  section.cover h1 {
    color: #FFFFFF;
    border-bottom: 2px solid rgba(255,255,255,0.3);
    font-size: 52px;
  }
  section.cover p {
    color: rgba(255,255,255,0.85);
    font-size: 24px;
  }
  section.section-divider {
    background: #1A7A6E;
    color: #FFFFFF;
    justify-content: center;
    text-align: center;
  }
  section.section-divider h1 {
    color: #FFFFFF;
    border-bottom: none;
    font-size: 48px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 22px;
  }
  th {
    background: #1A7A6E;
    color: #FFFFFF;
    padding: 10px 14px;
    text-align: left;
  }
  td {
    padding: 8px 14px;
    border-bottom: 1px solid #E2E8F0;
  }
  tr:nth-child(even) td {
    background: #F0FAF8;
  }
  code {
    background: #F2F2F2;
    color: #0E5C52;
    padding: 2px 6px;
    border-radius: 3px;
    font-size: 24px;
  }
  blockquote {
    border-left: 4px solid #1A7A6E;
    background: #E6F4F1;
    padding: 12px 20px;
    margin: 16px 0;
    color: #1A1A1A;
    font-style: normal;
  }
  .amber {
    color: #D4860B;
    font-weight: bold;
  }
  footer {
    font-size: 18px;
    color: #4A5568;
  }
---

<!-- _class: cover -->
<!-- _paginate: false -->

# GovAsk
## Government Document Intelligence

AI Engineering Lab Hackathon 2026
Challenge 2: Unlocking the Dark Data

**Harshana · Emma · Freddie**
UKHSA Public Health Data Science

---

# The problem

A government frontline adviser is on a call. They find three documents with similar names and different dates. They're not sure which is current.

> They give an answer based on whichever version they found fastest.
> It may not be the right one.

This is not a failure of effort. **It is a failure of infrastructure.**

---

# What we built

- **R-only RAG pipeline** — no Python, no external binaries, runs on restricted government laptops
- **Multi-format ingestion** — PDF, DOCX, HTML, TXT, Markdown parsed and chunked automatically
- **BM25 full-text search** — fast, transparent keyword retrieval via DuckDB
- **Grounded LLM answers** — every response cites the source document by filename
- **Shiny web interface** — question in, auditable answer + source table out

---

# Architecture

```
Documents (PDF · DOCX · HTML · TXT · MD)
    ↓  rag_setup.R — extract & chunk
data/rag_store.duckdb — BM25 index
    ↓  rag_query.R — retrieval + prompt + LLM
    ↓  app.R — R Shiny browser interface
```

Internally-hosted LLM on OpenShift AI — no data leaves the network.
Full corpus indexed in **< 2 minutes**. Query response typically **< 5 seconds**.

---

# How GitHub Copilot shaped this build

**.github/ setup before the first line of new code:**

| Layer | File | Purpose |
|---|---|---|
| Always-on | `copilot-instructions.md` | Project architecture, packages, conventions |
| On-demand | `Skills` × 3 | Prompt engineering, UI components, presentation |

**What changed:** RAG prompt engineering, multi-format parsers, and Shiny UI components generated in Agent mode sessions using purpose-built skills — function signatures, error handling, and citation logic produced correctly on the first attempt.

---

# Security and data governance

- **No data leaves the internal network** — self-hosted LLM on UKHSA OpenShift AI cluster
- **Zero commercial training use** — architectural guarantee, not a vendor promise
- **Credentials never in version control** — `.Renviron` git-ignored
- **Read-only store connection** — Shiny app cannot modify the index
- **Documents never leave source location** — only extracted text written to DuckDB

> The self-hosted model means query data cannot be collected or used for commercial training under any future change in vendor terms.

---

# Path to production

**Engineering next steps (prioritised):**

1. **Audit logging** — governance requirement, not a feature
2. **Structured evaluation framework** — controlled model upgrade process
3. **Hybrid retrieval** — BM25 + semantic re-ranking, closes synonym gap
4. **GOV.UK Content API** — keeps corpus current automatically

**Before operational deployment:**
Information governance review · WCAG 2.1 AA accessibility audit ·
Human-in-the-loop policy · Load testing

---

# Team

| Person | Role |
|---|---|
| **Harshana** | RAG architecture, prompt engineering, AI domain expertise |
| **Emma** | Project management, Shiny UI, demo coordination |
| **Freddie** | Multi-format ingestion, file-type extensions |

Built with `ragnar` · `ellmer` · `R Shiny` · `DuckDB` · `GitHub Copilot`

*AI Engineering Lab Hackathon · London · April 2026*
