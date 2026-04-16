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

**Team EpiDS: Harshana Liyanage · Emma Parker · Frederick Sloots**
UKHSA Epidemiology Data Science

---

# The problem

A government frontline adviser is on a call. They find three documents with similar names and different dates. They're not sure which is current.

> They give an answer based on whichever version they found fastest.
> It may not be the right one.

This is not a failure of effort. **It is a failure of infrastructure.**

---

# What we built

A single Shiny app with **three complementary interfaces**:

- **GovAsk** — query a curated local corpus of government guidance; every answer cites its source
- **APIAsk** — fetches live UKHSA guidance from the GOV.UK API on startup; always current, no manual uploads
- **EpiAsk** — same pipeline pointed at internal documents; our path to querying UKHSA's Confluence knowledge base

All grounded in retrieved documents · all answers cite sources · BM25 confidence detection throughout

---

# Architecture

```
Local files · GOV.UK API · Internal docs
    ↓  rag_setup / api_setup / epi_setup — extract & chunk
rag_store.duckdb · api_store.duckdb · epids_store.duckdb
    ↓  rag_query.R — shared retrieval + prompt + LLM
    ↓  R/app.R — GovAsk │ APIAsk │ EpiAsk
```

**APIAsk:** on startup → GOV.UK Search API → Content API → live BM25 index

Internally-hosted LLM on OpenShift AI — no data leaves the network.
Indexed in **< 2 minutes** · query response **< 5 seconds**

---

# How GitHub Copilot shaped this build

**.github/ setup before the first line of new code:**

| Layer | File | Purpose |
|---|---|---|
| Always-on | `copilot-instructions.md` | Architecture, packages, LLM endpoint, conventions |
| File-scoped | `.instructions.md` × 3 | R standards · Shiny patterns · RAG pipeline rules |
| On-demand | `Skills` × 3 | Prompt engineering · UI components · presentation |

**What changed:** The GOV.UK API client, three-tab Shiny server, and all prompt engineering were generated in Agent mode using purpose-built Skills. Two team members built different tabs in parallel — consistent output because the Skills defined the contract in advance.

---

# Security and data governance

- **No data leaves the internal network** — GPT-OSS 120B on UKHSA's OpenShift AI cluster
- **Zero commercial training use** — architectural guarantee, not a vendor promise
- **Credentials never in version control** — `.Renviron` git-ignored
- **Read-only store connections** — Shiny app cannot corrupt the index
- **GOV.UK API calls are read-only and public** — no authentication, no data submission

> Self-hosted model = query data categorically cannot be used for commercial training, regardless of any future vendor terms change.

---

# Beyond the hackathon

**Our team's next step:** connect EpiAsk to UKHSA's **Confluence REST API**
→ instant cited answers from SOPs, data standards, and surveillance system docs
→ no architecture changes — one new folder, one new setup script, one new tab

**Roadmap:**

1. **Confluence integration** — live institutional knowledge queries
2. **Audit logging** — governance requirement, not a feature
3. **Hybrid retrieval** — BM25 + semantic re-ranking, closes synonym gap
4. **Evaluation framework** — controlled model upgrade process

**Before operational deployment:**
IG review · WCAG 2.1 AA audit · Human-in-the-loop policy

---

# Team

| Person | Role |
|---|---|
| **Harshana Liyanage** | RAG architecture, prompt engineering, AI domain expertise |
| **Emma Parker** | Project management, Shiny UI, demo coordination |
| **Frederick Sloots** | Multi-format ingestion, file-type extensions |

Built with `ragnar` · `ellmer` · `R Shiny` · `DuckDB` · `GitHub Copilot`

*AI Engineering Lab Hackathon · London · April 2026*
