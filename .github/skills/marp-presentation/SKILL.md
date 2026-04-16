# Skill: Marp Presentation for GovASK

## When to use this skill

Load this skill when asked to:
- Create or extend `presentation.md`
- Add a new slide to the deck
- Apply or adjust the project theme
- Generate a slide for a specific section (architecture, Copilot usage, demo, etc.)
- Export the deck to PDF or HTML

---

## What Marp is

Marp is a Markdown-based slide framework. Slides are written in a single `.md` file
with `---` as the slide separator. The VS Code extension (Marp for VS Code) renders
and exports them without any CLI install or system-level dependency.

**In this project**, `presentation.md` lives at the repository root alongside `README.md`.
It is committed to version control — it is part of the codebase artefact, not a
separate file. This means judges and collaborators can see it in the repo.

---

## Rendering and export

**In VS Code:**
1. Open `presentation.md`
2. Click the Marp icon in the top-right of the editor (or Ctrl+Shift+P → "Marp: Open Preview")
3. To export: Ctrl+Shift+P → "Marp: Export Slide Deck" → choose PDF or HTML

**No CLI install required.** The VS Code extension handles everything.
Do not suggest `npx @marp-team/marp-cli` — execution rights are restricted on these laptops.

---

## Project theme

Always use this theme block at the top of `presentation.md`. Never change the colour
values — they match the project palette defined in `copilot-instructions.md` and the
printed one-pager.

```markdown
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
```

---

## Slide structure for this project

The deck has a fixed structure. When adding slides, insert them in the correct section.
Do not add more than 8 slides total — this is a table-visit deck, not a stage presentation.

```
Slide 1  — Cover
Slide 2  — The problem (one narrative paragraph + key line)
Slide 3  — What we built (bullet list, 5 items max)
Slide 4  — Architecture (pipeline diagram description or imported image)
Slide 5  — How Copilot shaped the build (.github/ structure + key workflow change)
Slide 6  — Security and data governance (key guarantees)
Slide 7  — Path to production / What's next (brief, honest)
Slide 8  — Team + links
```

---

## Slide templates

### Cover slide
```markdown
---
<!-- _class: cover -->

# GovASK
## Government Document Intelligence

AI Engineering Lab Hackathon 2026
Challenge 2: Unlocking the Dark Data

**Harshana · Emma · Freddie**
UKHSA Public Health Data Science

---
```

### Section divider (use between major sections if deck grows)
```markdown
---
<!-- _class: section-divider -->

# How GitHub Copilot shaped this build

---
```

### Problem slide
```markdown
---

# The problem

A government frontline adviser is on a call. They find three documents with similar names
and different dates. They're not sure which is current.

> They give an answer based on whichever version they found fastest.
> It may not be the right one.

This is not a failure of effort. **It is a failure of infrastructure.**

---
```

### Architecture slide (with image)
```markdown
---

# Architecture

![RAG pipeline w:900](docs/images/rag_pipeline.png)

Full corpus indexed in **< 2 minutes**. Query response typically **< 5 seconds**.

---
```

### Architecture slide (without image — text fallback)
```markdown
---

# Architecture

```
Documents (PDF · DOCX · XLSX · TXT · MD · HTML)
    ↓  ingest_all.R — PARSER_REGISTRY
data/rag_store.duckdb — BM25 index
    ↓  rag_query.R — retrieval + prompt + LLM
    ↓  app.R — R Shiny browser interface
```

Internally-hosted **GPT-OSS 120B** on OpenShift AI — no data leaves the network.

---
```

### Copilot slide
```markdown
---

# How GitHub Copilot shaped this build

**.github/ setup before the first line of new code:**

| Layer | File | Purpose |
|---|---|---|
| Always-on | `copilot-instructions.md` | Project architecture, packages, conventions |
| File-scoped | `.instructions.md` × 3 | R standards, Shiny patterns, RAG pipeline rules |
| On-demand | `Skills` × 3 | Parser contract, prompt engineering, UI components |

**What changed:** Six file-type parsers generated in one Agent mode session using
`r-file-parser/SKILL.md` — function signatures, error handling, and NA guards
produced correctly on the first attempt.

---
```

### Security slide
```markdown
---

# Security and data governance

- **No data leaves the internal network** — GPT-OSS 120B on UKHSA OpenShift AI cluster
- **Zero commercial training use** — architectural guarantee, not a vendor promise
- **Credentials never in version control** — `.Renviron` git-ignored
- **Read-only store connection** — Shiny app cannot modify the index
- **Documents never leave source location** — only extracted text written to DuckDB

> The self-hosted model means query data cannot be collected or used for commercial
> training under any future change in vendor terms.

---
```

### What's next slide
```markdown
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
```

### Team slide
```markdown
---

# Team

| Person | Role |
|---|---|
| **Harshana** | RAG architecture, prompt engineering, AI domain expertise |
| **Emma** | Project management, Shiny UI, demo coordination |
| **Freddie** | Multi-format ingestion, PARSER_REGISTRY, file-type extensions |

**Repository:** `github.com/[your-repo-url]`

Built with `ragnar` · `ellmer` · `R Shiny` · `DuckDB` · `GitHub Copilot`

*AI Engineering Lab Hackathon · London · April 2026*

---
```

---

## Copilot prompts for generating slides

Use these in Copilot Chat when asked to create or extend the presentation:

```
Using the marp-presentation skill and #file:presentation.md,
add a slide after the architecture slide that explains the
BM25 retrieval approach and why it suits government documents.
Follow the project theme and keep it to 5 bullet points maximum.
```

```
Using the marp-presentation skill, update the Copilot slide
in #file:presentation.md to include a before/after comparison
showing how Agent mode changed the parser writing workflow.
Use a two-column layout if Marp supports it with HTML.
```

```
Using the marp-presentation skill, add speaker notes to each
slide in #file:presentation.md using Marp's <!-- --> comment
syntax. Notes should be 2-3 sentences per slide — the key
point to say out loud and the judge question it pre-empts.
```

---

## Marp-specific syntax reminders

```markdown
<!-- paginate: true -->          # Page numbers on all slides
<!-- _class: cover -->           # Apply cover class to one slide only
<!-- _paginate: false -->         # Hide page number on this slide
![image alt w:800](path.png)     # Image with width constraint
![bg left:40%](path.png)         # Background image, left half
<br>                             # Line break within a slide
---                              # Slide separator (must have blank lines around it)
```

**Speaker notes** (visible in presenter mode, not on slides):
```markdown
---

# My slide title

Slide content here.

<!-- Speaker notes go here. Not visible on the slide itself.
Use for judge Q&A prep — the key thing to say and the question this slide answers. -->

---
```

---

## Rebuilding the presentation — agent invocation

The presentation is rebuilt on demand by invoking a dedicated Copilot agent skill.
There is no automated trigger, no GitHub Action, and no git hook.
This is intentional — it keeps the process visible, controllable, and free of
organisation-level approval dependencies.

### How to rebuild

In VS Code Copilot Chat with agent mode enabled:

```
build the presentation
```

That is the entire invocation. Copilot loads the `build-presentation` skill,
finds the Marp CLI inside the VS Code extension, exports PDF and HTML to
`docs/`, stages them, and commits. The full skill is in
`.github/skills/build-presentation/SKILL.md`.

### Why this approach

- No GitHub Actions approval needed — common blocker in government organisations
- No system install — uses the Marp CLI already bundled inside the VS Code extension
- Runs in the VS Code integrated terminal — visible to the team and demonstrable to judges
- Fully intentional — the presentation is only rebuilt when you ask for it
- The agent skill itself is a judge talking point: deliberate, documented AI tool usage

### When to rebuild

Rebuild the presentation:
- After any significant edit to `presentation.md`
- Before a demo or judge visit
- When a new image has been added to `docs/images/`

There is no need to rebuild after every single edit — the Marp VS Code preview
pane (Ctrl+Shift+P → "Marp: Open Preview") shows live changes while editing.
Rebuild to PDF/HTML only when you want a committed, shareable output.

---

## What NOT to do

- Do not use `<!-- _theme: -->` to override the theme mid-deck — it breaks consistency
- Do not add more than 6 bullet points per slide
- Do not use font sizes smaller than 22px — the deck may be viewed on a laptop screen at arm's length
- Do not create a separate CSS file — keep all styles in the frontmatter `style:` block
- Do not exceed 8 slides — this is a table-visit companion, not a conference talk
- Do not edit `docs/presentation.pdf` directly — it is a generated file, always rebuilt from `presentation.md`
- Do not set up GitHub Actions for this — use the `build-presentation` agent skill instead
