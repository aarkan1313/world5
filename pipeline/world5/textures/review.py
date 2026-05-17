"""Review-report tool — surfaces below-A candidates for human spot-check.

Reads candidates/<biome>/<slot>/_index.json across all slots, lists
every candidate the grader rated below A with the score breakdown +
reason. Used to calibrate auto-grading thresholds: spot-check each
flagged candidate, mark agree/disagree, retune.

Also produces a "rejects only" contact sheet so you can review the
flagged set as one image without opening 20 folders.

Usage:
    python diversity_review.py --biome alpine
    python diversity_review.py --biome alpine --slots ground
    python diversity_review.py --biome alpine --open-folders
        (also opens the rejected folders in Explorer)
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

# W5 port: defaults to in-repo candidates dir; override via CLI if needed
CANDIDATES_ROOT = Path(__file__).resolve().parents[3] / "pipeline" / "textures" / "candidates"


def _load_index(biome: str, slot: str) -> dict | None:
    p = CANDIDATES_ROOT / biome / slot / "_index.json"
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def _slots(biome: str, slots: list[str] | None) -> list[str]:
    biome_dir = CANDIDATES_ROOT / biome
    found = sorted(d.name for d in biome_dir.iterdir()
                   if d.is_dir() and not d.name.startswith("_"))
    if slots:
        return [s for s in found if s in slots]
    return found


def review(biome: str, slots: list[str] | None, open_folders: bool) -> int:
    flagged: list[tuple[str, str, dict]] = []
    a_count: dict[str, int] = {}
    total_count: dict[str, int] = {}

    for slot in _slots(biome, slots):
        idx = _load_index(biome, slot)
        if not idx:
            continue
        cands = idx.get("candidates", {})
        for cid, entry in sorted(cands.items()):
            total_count[slot] = total_count.get(slot, 0) + 1
            if entry.get("grade") == "A":
                a_count[slot] = a_count.get(slot, 0) + 1
            else:
                flagged.append((slot, cid, entry))

    print(f"=== {biome} review ===")
    for slot in _slots(biome, slots):
        t = total_count.get(slot, 0)
        a = a_count.get(slot, 0)
        print(f"  {slot}: {a}/{t} A-grade, {t - a} flagged for review")

    print(f"\nflagged candidates ({len(flagged)}):")
    print(f"{'slot':8s} {'id':24s} {'grade':6s} {'periodic':>10s} {'edge':>10s} {'junc':>8s} {'rich':>6s}  reason")
    for slot, cid, e in flagged:
        m = e.get("metrics") or {}
        per = m.get("periodic")
        edg = m.get("edge")
        jun = m.get("junction")
        ric = m.get("richness")
        per_s = f"{per:10.2f}" if per is not None else f"{'-':>10s}"
        edg_s = f"{edg:10.5f}" if edg is not None else f"{'-':>10s}"
        jun_s = f"{jun:8.2f}" if jun is not None else f"{'-':>8s}"
        ric_s = f"{ric:6.2f}" if ric is not None else f"{'-':>6s}"
        reason = e.get("below_A_reason") or "-"
        print(f"  {slot:8s} {cid:24s} {e.get('grade') or '-':6s} {per_s} {edg_s} {jun_s} {ric_s}  {reason}")

    if open_folders:
        print(f"\nopening {len(flagged)} folders in Explorer...")
        for slot, cid, _e in flagged:
            d = CANDIDATES_ROOT / biome / slot / cid
            subprocess.Popen(["explorer", str(d)])

    # write rejects.json for the contact-sheet tool
    rejects_path = CANDIDATES_ROOT / biome / "_rejects.json"
    rejects_path.write_text(json.dumps({
        "biome": biome,
        "flagged": [{"slot": s, "id": c, **e} for s, c, e in flagged],
    }, indent=2), encoding="utf-8")
    print(f"\nwrote {rejects_path}")
    print(f"to render rejects-only contact sheets:")
    print(f"  python pipeline/build_contact_sheet.py --biome {biome} --grade-filter B C D")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--biome", required=True)
    ap.add_argument("--slots", nargs="*")
    ap.add_argument("--open-folders", action="store_true",
                    help="open each flagged folder in Explorer for spot-check")
    args = ap.parse_args()
    return review(args.biome, args.slots, args.open_folders)


if __name__ == "__main__":
    raise SystemExit(main())
