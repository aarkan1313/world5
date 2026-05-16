# Build-Note: Phase 0 Repo Setup — 2026-05-16

> Append-only diary entry per spec 02 R6. What shipped, what changed
> vs the plan, lessons learned, open follow-ups.

## What shipped

W5 repo initialized + first commit + pushed.

- **Local repo**: `D:/assets/world 5/.git` with branch `main`
- **Remote**: `https://github.com/aarkan1313/world5.git` (origin)
- **First commit**: `f73b4f8` (144 files, 16,181 lines)
- **Parent untrack**: `D:/assets/.git` commit `5f06ce3d` added
  `world 5/` to parent `.gitignore`

Contents per Phase 0 checklist:
- Directory tree (66 dirs with `.gitkeep` placeholders for empty ones)
- `engine/plugin.cfg` + minimal `plugin.gd` (autoloads stub-commented
  for Phase 2)
- `engine/README.md` + `CHANGELOG.md` (Keep-a-Changelog) + `LICENSE`
  placeholder
- `demo/project.godot` (Godot 4.5+ Forward+) + `demo/README.md`
- `pipeline/pyproject.toml` editable-install package + `pipeline/world5/`
  importable Python module v0.0.1 + `pipeline/README.md`
- Top-level docs scaffold per spec 05 (was prepped in earlier session;
  shipped in this commit)
- `.gitignore` + `.gitattributes` + `.godotignore.template`
- Windows Junction at `demo/addons/world5` → `engine/` (per-machine;
  in .gitignore)

## What changed vs the plan

Three deviations from `docs/roadmap/phase_0_repo_setup.md`:

1. **Addon link mechanism**: planned symlink via `mklink /D`. User
   environment lacks Developer Mode + admin, so symlink creation
   failed. Fell back to **Windows Junction** via
   `New-Item -ItemType Junction`. Junctions work without admin and
   Godot treats them as regular dirs. SA-M2.11 (Windows mklink admin
   prereq) was already documented in spec 18; the junction fallback
   should also be added to spec 18 as a Windows option. Follow-up.

2. **Pre-existing `worldgen5/` dir**: discovered at `world 5/` root,
   dated 2026-05-16 13:43 (from earlier in the session, before W5
   work started). Looks like a user-created Godot scratch project
   (icon.svg, project.godot, .godot/ cache). Per investigate-before-
   delete rule: added to `.gitignore`, not touched. User can keep,
   move, or delete at their discretion.

3. **Added `.gitattributes`**: not in original checklist. CRLF/LF
   warnings appeared on first `git add`; added `.gitattributes` to
   lock repo to LF line endings. Lightweight addition; prevents
   future cross-platform line-ending churn.

## Lessons learned

- **Windows Junction is a valid Method C fallback** when neither admin
  nor Developer Mode is available. Should be documented in spec 18
  install methods as a Windows-specific option (junction is
  Windows-only; not portable, but neither is `mklink /D`).
- **Parent git's `ls-files` with quoted path argument returns truncated
  output if there are many tracked files in the parent**; the
  apparent "tracking" was actually files visible from a substring
  match in the truncated buffer. Verified definitively via
  `git ls-files --error-unmatch` which correctly errored out (=
  parent never tracked W5 files).
- **First commit message format**: used HEREDOC for multi-line per
  safety protocol. `🌱 W5 starts here.` emoji included since this is
  a meaningful milestone marker (user-facing repo history). Worth
  preserving as project tradition (one emoji per major milestone
  commit; sparingly).

## Open follow-ups

- [ ] Add Windows Junction option to spec 18 install methods (small
      edit; happens at first spec promotion sweep, or sooner if
      another Windows user hits the same wall)
- [ ] Phase 0 close task per checklist: **spec status sweep** — all
      47 specs say `Status: draft`; outside audit + self-audit both
      passed, so a batch promote `draft → reviewed` is warranted.
      Defer to start-of-Phase-2 prep
- [ ] Decide license placeholder before v0.1.0 (currently "TBD"
      placeholder); not blocking
- [ ] First Phase 2 task: write `docs/roadmap/phase_2_foundations.md`
      checklist + decide build order within Tier 0
- [ ] `setup.py` script for cross-machine addon link (currently
      manual junction creation on Windows; spec 18 Method C dev tool
      lands in Phase 2)
- [ ] Push the Phase 0 close commit (this build-note + STATE/ROADMAP
      updates) as commit #2 on origin/main

## Verification

Phase 0 checklist verification items confirmed:
- ✅ `git log --oneline` shows `f73b4f8 Phase 0: repo scaffold per spec 01 module layout`
- ✅ Branch `main` tracks `origin/main`
- ✅ No files outside the allowlist tracked (verified `git status`
      shows only Phase 0 + docs files)
- ⏳ `demo/project.godot` opens in Godot 4.5 — not user-tested yet
- ⏳ `pip install -e ./pipeline` succeeds — not user-tested yet
- ⏳ `import world5` works — not user-tested yet

User-test items will happen at start of Phase 2 sessions.

## Refs

- Spec 01 MODULE_LAYOUT (the contract this commit realizes)
- Spec 02 CONTRIBUTING_LIFECYCLE (this build-note follows the
  required template)
- Spec 04 GODOT_ROOT_ALLOWLIST (allowlist verified via this commit)
- Spec 18 PLUGIN_INSTALL_AND_DEV_LOOP (Windows junction fallback)
- `docs/roadmap/phase_0_repo_setup.md` (the checklist this build
  realized)
