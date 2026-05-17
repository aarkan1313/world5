"""Promote candidate textures from `candidates/<biome>/<slot>/<tag>/`
into a world bundle's materials/ tree + update material_variants.json.

CLI usage:
    python -m world5.textures.promote \
        --world worlds/walking_demo \
        --candidates-root candidates \
        --biome alpine \
        --slot ground --base 03_firn_dense \
            --siblings s05_firn s07_firn s09_firn s11_firn \
        --slot mid    --base 12_mid_rock \
            --siblings s_mid_01 s_mid_03

`--slot` can repeat; each `--slot SLOT` consumes the next `--base TAG`
and an optional `--siblings TAG TAG ...` group. Group ends at the next
`--slot` or end of args.


Per plan 25 step 4 — the "single highest-leverage Phase 5 tooling
deliverable" (the manual W4 file gymnastics is 96 moves per biome).

Canonical layout produced:

    <world>/materials/biome_<biome>/<slot>/{albedo,normal,roughness,ao}.png
    <world>/materials/biome_<biome>/<slot>_variants/v<i>_<tag>/{...}.png
    <world>/material_variants.json   (additively updated; slot is replaced)

PBR map list comes from PBR_MAPS — promote only copies maps that
actually exist in the candidate dir (so a candidate without `ao.png`
just skips it, no error).

Validation gate: ALL referenced candidates must exist on disk before
the first file copy. A missing tag halts the whole promote call —
the world tree is never left in a half-written state.

Sibling cap: spec 24 max_variants_per_slot=8 (shader limit). Going
over raises before any copy.

Public surface:
    SlotPromotion(slot, base, siblings)
    PromoteResult(files_copied, manifest_added, summary)
    PromoteError
    promote(world, candidates_root, biome, promotions) -> PromoteResult
"""

from __future__ import annotations

import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path


PBR_MAPS: tuple[str, ...] = ("albedo", "normal", "roughness", "ao")

# Spec 24 max_variants_per_slot (shader 3-tap budget + room for selection
# bias). Total per slot = 1 base + N siblings; cap applies to N+1.
SIBLING_COUNT_CAP: int = 8


class PromoteError(Exception):
    """Raised when promote refuses to run (missing inputs, cap exceeded)."""


@dataclass(frozen=True)
class SlotPromotion:
    """One slot's promotion: which base tag, which sibling tags."""

    slot: str
    base: str
    siblings: list[str] = field(default_factory=list)


@dataclass
class PromoteResult:
    """Diff summary returned to the caller."""

    files_copied: int = 0
    manifest_added: int = 0  # new sibling variant entries (delta vs prior)
    summary: list[str] = field(default_factory=list)


def _candidate_dir(candidates_root: Path, biome: str, slot: str, tag: str) -> Path:
    return candidates_root / biome / slot / tag


def _validate_inputs(
    candidates_root: Path, biome: str, promotions: list[SlotPromotion]
) -> None:
    """Confirm every named candidate dir exists + sibling caps respected.

    Raises PromoteError before any file is touched.
    """
    for p in promotions:
        total = 1 + len(p.siblings)
        if total > SIBLING_COUNT_CAP:
            raise PromoteError(
                f"slot '{p.slot}': {total} variants exceeds shader cap of "
                f"{SIBLING_COUNT_CAP} (spec 24 max_variants_per_slot)"
            )
        missing: list[str] = []
        for tag in (p.base, *p.siblings):
            d = _candidate_dir(candidates_root, biome, p.slot, tag)
            if not d.is_dir():
                missing.append(str(d))
        if missing:
            raise PromoteError(
                f"slot '{p.slot}' references missing candidates: "
                + ", ".join(missing)
            )


def _copy_pbr_set(src_dir: Path, dst_dir: Path) -> int:
    """Copy every PBR_MAPS file from src to dst that exists. Returns N copied."""
    dst_dir.mkdir(parents=True, exist_ok=True)
    n = 0
    for m in PBR_MAPS:
        src = src_dir / f"{m}.png"
        if src.exists():
            shutil.copy2(src, dst_dir / f"{m}.png")
            n += 1
    return n


def _update_manifest_slot(
    manifest: dict, biome: str, slot: str, new_variants: list[dict]
) -> int:
    """Replace (biome, slot)'s variants with new_variants. Add the slot
    entry if it doesn't yet exist. Returns delta in sibling count
    (new sibling count = new_variants - 1 base; delta vs old)."""
    slots: list[dict] = manifest.setdefault("slots", [])
    for s in slots:
        if s.get("biome") == biome and s.get("slot") == slot:
            old_n = max(0, len(s.get("variants", [])) - 1)
            s["variants"] = new_variants
            return (len(new_variants) - 1) - old_n
    slots.append({"biome": biome, "slot": slot, "variants": new_variants})
    return len(new_variants) - 1


def promote(
    *,
    world: Path,
    candidates_root: Path,
    biome: str,
    promotions: list[SlotPromotion],
) -> PromoteResult:
    """Run the promote workflow. Returns a PromoteResult on success;
    raises PromoteError if validation fails."""
    world = Path(world)
    candidates_root = Path(candidates_root)
    _validate_inputs(candidates_root, biome, promotions)

    result = PromoteResult()
    materials_root = world / "materials" / f"biome_{biome}"

    for p in promotions:
        # --- base ---
        base_src = _candidate_dir(candidates_root, biome, p.slot, p.base)
        base_dst = materials_root / p.slot
        result.files_copied += _copy_pbr_set(base_src, base_dst)
        result.summary.append(f"{p.slot}/base={p.base} -> {base_dst}")
        # --- siblings ---
        variants_dir = materials_root / f"{p.slot}_variants"
        # Wipe stale sibling subdirs to make re-promote deterministic
        # (otherwise an old v3_* dir lingers when the new promote ships
        # only 3 siblings).
        if variants_dir.exists():
            for child in variants_dir.iterdir():
                if child.is_dir() and child.name.startswith("v"):
                    # Only nuke vN_ subdirs (don't touch unrelated files)
                    parts = child.name.split("_", 1)
                    if parts[0].startswith("v") and parts[0][1:].isdigit():
                        shutil.rmtree(child)
        for i, tag in enumerate(p.siblings):
            sib_src = _candidate_dir(candidates_root, biome, p.slot, tag)
            sib_dst = variants_dir / f"v{i}_{tag}"
            result.files_copied += _copy_pbr_set(sib_src, sib_dst)
            result.summary.append(f"{p.slot}/sib{i}={tag} -> {sib_dst}")

        # --- manifest update ---
        # Per spec 24 schema: `source` is biome-relative (the engine
        # resolver prepends `biome_<biome>/`). Short form keeps the
        # manifest compact and matches the schema example in plan 25.
        new_variants: list[dict] = [
            {
                "id": "default",
                "source": p.slot,
                "weight": 1.0,
            }
        ]
        for i, tag in enumerate(p.siblings):
            new_variants.append({
                "id": f"v{i}_{tag}",
                "source": f"{p.slot}_variants/v{i}_{tag}",
                "weight": 1.0,
            })
        manifest_path = world / "material_variants.json"
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        else:
            # No manifest yet — seed with sensible defaults per plan 25
            # spec 24 schema. Caller can post-edit if they want different
            # world_seed / region settings.
            manifest = {
                "_schema_version": 1,
                "world_seed": 42,
                "region_size_m": 512.0,
                "edge_blend_m": 48.0,
                "max_variants_per_slot": SIBLING_COUNT_CAP,
                "max_total_variant_layers": 256,
                "slots": [],
            }
        delta = _update_manifest_slot(manifest, biome, p.slot, new_variants)
        result.manifest_added += max(0, delta)
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )

    return result


# ---------- CLI ----------


def _parse_argv(argv: list[str]) -> tuple[dict, list[SlotPromotion]]:
    """Hand-rolled parser — argparse doesn't model 'repeating slot
    groups with variable-length siblings' cleanly. Returns (kwargs,
    promotions).
    """
    import sys

    common: dict[str, str] = {}
    promotions: list[SlotPromotion] = []
    i = 0
    current: dict | None = None

    def _flush() -> None:
        if current is None:
            return
        if "base" not in current:
            raise PromoteError(
                f"--slot {current['slot']} missing --base TAG"
            )
        promotions.append(SlotPromotion(
            slot=current["slot"],
            base=current["base"],
            siblings=list(current.get("siblings", [])),
        ))

    while i < len(argv):
        a = argv[i]
        if a in ("--world", "--candidates-root", "--biome"):
            i += 1
            if i >= len(argv):
                raise PromoteError(f"{a} expects a value")
            common[a.lstrip("-").replace("-", "_")] = argv[i]
            i += 1
        elif a == "--slot":
            _flush()
            i += 1
            if i >= len(argv):
                raise PromoteError("--slot expects a slot name")
            current = {"slot": argv[i], "siblings": []}
            i += 1
        elif a == "--base":
            if current is None:
                raise PromoteError("--base must follow --slot")
            i += 1
            current["base"] = argv[i]
            i += 1
        elif a == "--siblings":
            if current is None:
                raise PromoteError("--siblings must follow --slot")
            i += 1
            while i < len(argv) and not argv[i].startswith("--"):
                current["siblings"].append(argv[i])
                i += 1
        elif a in ("-h", "--help"):
            print(__doc__ or "")
            sys.exit(0)
        else:
            raise PromoteError(f"unknown arg: {a}")
    _flush()
    return common, promotions


def main(argv: list[str] | None = None) -> int:
    import sys

    if argv is None:
        argv = sys.argv[1:]
    try:
        common, promotions = _parse_argv(argv)
    except PromoteError as e:
        print(f"promote: {e}", file=sys.stderr)
        return 2

    missing_keys = [k for k in ("world", "candidates_root", "biome") if k not in common]
    if missing_keys:
        print(
            f"promote: missing required args: {', '.join('--' + k.replace('_', '-') for k in missing_keys)}",
            file=sys.stderr,
        )
        return 2
    if not promotions:
        print("promote: no --slot given; nothing to do", file=sys.stderr)
        return 2

    try:
        result = promote(
            world=Path(common["world"]),
            candidates_root=Path(common["candidates_root"]),
            biome=common["biome"],
            promotions=promotions,
        )
    except PromoteError as e:
        print(f"promote: {e}", file=sys.stderr)
        return 1

    print(f"promote: {result.files_copied} files copied, "
          f"{result.manifest_added} sibling entries added")
    for line in result.summary:
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
