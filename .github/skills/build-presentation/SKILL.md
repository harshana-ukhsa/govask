# Skill: Build Presentation

## When to use this skill

Load this skill when the user says any of the following:
- "build the presentation"
- "rebuild the slides"
- "export the presentation"
- "the presentation needs rebuilding"
- "generate presentation output"

This skill is intentionally invoked — it does not run automatically.
It uses the Marp CLI bundled inside the Marp VS Code extension.
No system install, no npm, no GitHub Actions required.

---

## What this skill does

1. Finds the Marp CLI inside the installed VS Code extension
2. Exports `presentation.md` to `docs/presentation.html`
3. Stages the output files with git
4. Commits with a standard message

The entire process runs in the VS Code terminal using only tools already present
on the machine. Nothing is installed. No permissions are needed beyond what
VS Code already has.

---

## Step-by-step execution

When this skill is invoked, execute these steps in order.
Use the VS Code terminal (not a separate shell).
Report the result of each step before moving to the next.

### Step 1 — Find the Marp extension version

Run this command to find the installed Marp extension:

```sh
ls "$HOME/.vscode/extensions/" | grep "marp-team.marp-vscode-"
```

The output will be something like `marp-team.marp-vscode-3.4.0`.
Extract the version number (e.g. `3.4.0`).
Store the full path as:

```sh
MARP_CLI="$HOME/.vscode/extensions/marp-team.marp-vscode-<VERSION>/node_modules/@marp-team/marp-cli/lib/marp-cli.js"
```

If nothing is returned, stop and tell the user:
> "Marp for VS Code extension not found. Install it from the VS Code Extensions
> panel (search 'Marp for VS Code') and try again."

### Step 2 — Verify node is available

```sh
node --version
```

If this fails, stop and tell the user:
> "node is not available in the terminal PATH. VS Code's bundled node can be
> used instead — open the VS Code integrated terminal (Ctrl+`) and try again
> from there, as it inherits VS Code's PATH."

### Step 3 — Create the output directory

```sh
mkdir -p docs
```

### Step 4 — Export to HTML

```sh
node "$MARP_CLI" presentation.md \
  --html \
  --output docs/presentation.html \
  --allow-local-files
```

HTML export almost never fails — it does not require Chromium.

### Step 5 — Stage the output files

```sh
git add docs/presentation.html
```

If the file does not exist, stop and report what went wrong in step 4.

### Step 6 — Commit

```sh
git commit -m "docs: rebuild presentation from presentation.md"
```

If nothing to commit (outputs unchanged), report:
> "Presentation is already up to date — no commit needed."

### Step 7 — Report to the user

Tell the user what was built and committed:

```
✓ Presentation rebuilt and committed.

  🌐 docs/presentation.html

  Commit: docs: rebuild presentation from presentation.md
```

---

## How to invoke this skill

In VS Code Copilot Chat (agent mode), type:

```
build the presentation
```

or

```
@workspace rebuild the slides and commit the output
```

Copilot will load this skill and execute the steps above.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| Marp extension not found | Not installed or different path | Install from VS Code Extensions panel |
| `node: command not found` | Node not in PATH in this terminal | Open VS Code integrated terminal (Ctrl+`) |
| PDF fails, Chromium error | Corporate Chrome sandbox restriction | Use `--chrome-arg="--no-sandbox"` flag (Step 4 fallback) |
| PDF fails, permission error | Output directory not writable | Check `docs/` folder permissions |
| `git commit` fails | Nothing staged / nothing changed | Outputs may be unchanged — no action needed |
| Extension path not found | Version mismatch | Re-run Step 1 and check exact folder name |

---

## Important constraints

- **Never install anything.** Do not run `npm install`, `npm install -g`, `pip install`,
  or any package manager. Everything needed is already present in the VS Code extension.
- **Never use `npx`.** It attempts to download packages and will likely be blocked.
- **Use the VS Code integrated terminal.** It inherits the correct PATH including
  the node runtime VS Code uses internally.
- **Do not modify `presentation.md`.** This skill only builds output — editing the
  slides is a separate task.
- **Do not push.** Commit only. Pushing is a deliberate team action.
