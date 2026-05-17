"""W4 diversity batch driver — calls tx_pipeline (in-process).

Replaces the prior aaa_texture.py-subprocess version. tx_pipeline writes
canonical outputs directly into candidates/<biome>/<slot>/<NN>_<tag>/
with the manifest + qa.json + variants/ — no move/copy step needed.

Per-slot _index.json gets one entry per candidate (built from the
manifest's qa stage).

Usage:
    python diversity_run.py --biome alpine
    python diversity_run.py --biome alpine --slots ground
    python diversity_run.py --biome alpine --only ground/fresh_powder ground/windpack
    python diversity_run.py --biome alpine --size 1024 --variants 4
"""
from __future__ import annotations

import argparse
import json
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

# W5 port: proper package import; tx_pipeline is the sibling module
# in pipeline/world5/textures/.
from .tx_pipeline import PipelineSettings, run_pipeline  # noqa: E402

# Biome YAMLs live at pipeline/biomes/<name>.yaml at the project root
# (per spec 25 §"Per-biome YAML layout"). W5 may not have authored
# these yet — driver fails clean with a useful message on missing.
_W5_ROOT = Path(__file__).resolve().parents[3]
BIOMES_DIR = _W5_ROOT / "pipeline" / "biomes"
# Default candidates root inside the W5 layout. Override via
# --candidates-root for external dirs (e.g. d:/tmp/w5_candidates/).
CANDIDATES_ROOT = _W5_ROOT / "pipeline" / "textures" / "candidates"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _load_biome(biome: str) -> dict[str, Any]:
    p = BIOMES_DIR / f"{biome}.yaml"
    if not p.exists():
        raise FileNotFoundError(f"biome yaml not found: {p}")
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def _candidate_dir(biome: str, slot: str, idx: int, tag: str) -> Path:
    return CANDIDATES_ROOT / biome / slot / f"{idx:02d}_{tag}"


def _index_path(biome: str, slot: str) -> Path:
    return CANDIDATES_ROOT / biome / slot / "_index.json"


def _load_index(biome: str, slot: str) -> dict[str, Any]:
    p = _index_path(biome, slot)
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {"biome": biome, "slot": slot, "candidates": {}}


def _save_index(biome: str, slot: str, index: dict[str, Any]) -> None:
    p = _index_path(biome, slot)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(index, indent=2, default=float), encoding="utf-8")


def _already_done(biome: str, slot: str, idx: int, tag: str) -> bool:
    d = _candidate_dir(biome, slot, idx, tag)
    return (d / "manifest.json").exists() and \
           (d / "albedo.png").exists()


def _entry_from_manifest(manifest: dict, idx: int, tag: str,
                         prompt: str, size: int) -> dict[str, Any]:
    """Build the per-candidate _index.json entry from a tx_pipeline manifest."""
    qa_stage = next((s for s in manifest.get("stages", [])
                     if s.get("stage") == "qa"), {})
    failed = qa_stage.get("failed") or []
    grade = manifest.get("grade")
    status = "candidate" if grade == "A" else "rejected_auto"
    if manifest.get("status") == "failed":
        status = "failed"
    return {
        "id": f"{idx:02d}_{tag}",
        "prompt": prompt,
        "size": size,
        "grade": grade,
        "passed_checks": qa_stage.get("passed_checks"),
        "failed_checks": failed,
        "thresholds": qa_stage.get("thresholds"),
        "status": status,
        "promoted_to": None,
        "generated_at": manifest.get("completed_at") or _now_iso(),
        "pipeline_version": manifest.get("version"),
    }


def run_candidate(biome: str, slot: str, slot_yaml: dict, idx: int,
                  cand: dict, prefix: str, suffix: str,
                  settings: PipelineSettings,
                  skip_existing: bool) -> dict | None:
    tag = cand["tag"]
    body = cand["body"]
    if skip_existing and _already_done(biome, slot, idx, tag):
        print(f"[skip] {biome}/{slot}/{idx:02d}_{tag} — manifest already exists")
        return None
    full_prompt = prefix + body + suffix
    out_dir = _candidate_dir(biome, slot, idx, tag)
    category = slot_yaml.get("category", settings.category)

    # Per-candidate settings: clone the base, override category
    cand_settings = PipelineSettings(
        **{**settings.__dict__, "category": category}
    )

    print(f"\n========== {biome}/{slot}/{idx:02d}_{tag} ==========")
    print(f"  prompt: {full_prompt}")
    asset_id = f"div_{biome}_{slot}_{idx:02d}_{tag}"
    try:
        manifest = run_pipeline(full_prompt, asset_id, out_dir, cand_settings)
    except Exception as e:
        print(f"  !! FAILED: {e}")
        traceback.print_exc()
        return {
            "id": f"{idx:02d}_{tag}",
            "prompt": full_prompt,
            "size": cand_settings.size,
            "status": "failed",
            "error": str(e),
            "generated_at": _now_iso(),
        }
    # prompt.txt for convenience
    (out_dir / "prompt.txt").write_text(full_prompt, encoding="utf-8")
    return _entry_from_manifest(manifest, idx, tag, full_prompt,
                                cand_settings.size)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--biome", required=True)
    ap.add_argument("--slots", nargs="*")
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--variants", type=int, default=4)
    ap.add_argument("--seed-base", type=int, default=42)
    ap.add_argument("--pbr-backend", choices=["hybrid", "derive", "sm"],
                    default="hybrid")
    ap.add_argument("--heal-denoise", type=float, default=0.35)
    ap.add_argument("--heal-mode", choices=["flux_heal", "none"],
                    default="flux_heal")
    ap.add_argument("--delight-strength", type=float, default=0.4)
    ap.add_argument("--no-skip", action="store_true",
                    help="re-run even if manifest already exists")
    args = ap.parse_args()

    spec = _load_biome(args.biome)
    slots_spec = spec["slots"]
    prefix = spec.get("prompt_prefix", "")
    suffix = spec.get("prompt_suffix", "")

    if args.slots:
        slots_to_run = [s for s in args.slots if s in slots_spec]
    else:
        slots_to_run = list(slots_spec.keys())

    only_pairs = set(args.only)
    base_settings = PipelineSettings(
        size=args.size,
        variants=args.variants,
        seed_base=args.seed_base,
        pbr_backend=args.pbr_backend,
        heal_denoise=args.heal_denoise,
        heal_mode=args.heal_mode,
        delight_strength=args.delight_strength,
    )
    total = sum(len(slots_spec[s]["candidates"]) for s in slots_to_run)
    print(f"[diversity_run] biome={args.biome} slots={slots_to_run} "
          f"size={args.size} variants={args.variants} "
          f"pbr={args.pbr_backend} heal={args.heal_mode}@{args.heal_denoise} "
          f"total={total}")

    failures: list[str] = []
    for slot in slots_to_run:
        slot_yaml = slots_spec[slot]
        cands = slot_yaml["candidates"]
        index = _load_index(args.biome, slot)
        for i, cand in enumerate(cands, start=1):
            if only_pairs and f"{slot}/{cand['tag']}" not in only_pairs:
                continue
            entry = run_candidate(args.biome, slot, slot_yaml, i, cand,
                                  prefix, suffix, base_settings,
                                  skip_existing=not args.no_skip)
            if entry is not None:
                index["candidates"][f"{i:02d}_{cand['tag']}"] = entry
                _save_index(args.biome, slot, index)
                if entry.get("status") == "failed":
                    failures.append(f"{slot}/{cand['tag']}")

    print(f"\n[diversity_run] done. failures={len(failures)}")
    for f in failures:
        print(f"  - {f}")

    # Grade summary
    print("\n[diversity_run] grade summary:")
    for slot in slots_to_run:
        index = _load_index(args.biome, slot)
        by_grade: dict[str, int] = {}
        for e in index.get("candidates", {}).values():
            g = e.get("grade") or "-"
            by_grade[g] = by_grade.get(g, 0) + 1
        cnts = " ".join(f"{g}={n}" for g, n in sorted(by_grade.items()))
        print(f"  {args.biome}/{slot}: {cnts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
