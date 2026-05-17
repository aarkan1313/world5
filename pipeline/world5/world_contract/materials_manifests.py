"""Spec 24 + 25 preflight: validates the per-world material_variants.json
and per-biome detail_array.json against the schema + on-disk files.

Catches the post-promote class of bugs:
- manifest references a sibling source path that doesn't exist
- detail tile listed but its PBR images are missing
- variant cap exceeded (shader limit)
- malformed JSON

Only runs when `world_path` is supplied (this is a per-world check,
not a repo-wide check).
"""

from __future__ import annotations

import json
from pathlib import Path

from world5.world_contract._types import Issue, Severity

# Spec 24 cap (mirrored from MaterialPipeline.SIBLING_COUNT_CAP)
SIBLING_COUNT_CAP = 8
PBR_MAPS = ("albedo", "normal", "roughness", "ao")


def _load_json(path: Path) -> tuple[dict | None, str | None]:
    """Returns (parsed_dict, error_msg). One side is always None."""
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except OSError as e:
        return None, f"unreadable: {e}"
    except json.JSONDecodeError as e:
        return None, f"invalid JSON: {e}"


def _check_material_variants(world: Path) -> list[Issue]:
    issues: list[Issue] = []
    mv_path = world / "material_variants.json"
    if not mv_path.exists():
        # Missing is informational, not an error — a freshly-created
        # world bundle may not have a manifest yet (binders treat
        # unbound as the default-off macro-only path).
        return issues
    parsed, err = _load_json(mv_path)
    if err is not None:
        issues.append(Issue(
            severity=Severity.ERROR,
            code="materials_manifests.material_variants_unparseable",
            message=err,
            path=str(mv_path),
        ))
        return issues
    assert parsed is not None

    region = float(parsed.get("region_size_m", 0.0))
    edge = float(parsed.get("edge_blend_m", 0.0))
    if region <= 0.0:
        issues.append(Issue(
            severity=Severity.ERROR,
            code="materials_manifests.region_size_invalid",
            message=f"region_size_m must be > 0 (got {region})",
            path=str(mv_path),
        ))
    if region > 0 and edge >= region / 4.0:
        issues.append(Issue(
            severity=Severity.ERROR,
            code="materials_manifests.edge_blend_too_large",
            message=f"edge_blend_m ({edge}) must be < region_size_m/4 ({region/4.0})",
            path=str(mv_path),
        ))

    materials_root = world / "materials"
    total_layers = 0
    for slot_entry in parsed.get("slots", []):
        biome = slot_entry.get("biome", "?")
        slot = slot_entry.get("slot", "?")
        variants = slot_entry.get("variants", [])
        if len(variants) > SIBLING_COUNT_CAP:
            issues.append(Issue(
                severity=Severity.ERROR,
                code="materials_manifests.variants_over_slot_cap",
                message=f"slot '{biome}/{slot}' has {len(variants)} variants > cap {SIBLING_COUNT_CAP}",
                path=str(mv_path),
            ))
        total_layers += len(variants)
        for v in variants:
            source = v.get("source", "")
            if not source:
                continue
            # Spec 24 schema: source is biome-relative; the renderer
            # resolves it under materials/biome_<biome>/<source>/.
            src_dir = materials_root / f"biome_{biome}" / source
            albedo = src_dir / "albedo.png"
            if albedo.exists():
                continue
            # Distinguish "not promoted yet" from "broken promote":
            # - src_dir missing OR contains no PBR map → not promoted
            #   (the .gitkeep'd scaffold state Phase 5 entry shipped)
            # - src_dir has some PBR maps but not albedo → broken
            #   (half-written state from an aborted promote run)
            has_any_pbr = False
            if src_dir.exists():
                for m in PBR_MAPS:
                    if (src_dir / f"{m}.png").exists():
                        has_any_pbr = True
                        break
            if not has_any_pbr:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="materials_manifests.variant_not_yet_promoted",
                    message=f"variant '{v.get('id', '?')}' has no PBR maps yet (slot not promoted)",
                    path=str(src_dir),
                    details={"biome": biome, "slot": slot, "source": source},
                ))
            else:
                issues.append(Issue(
                    severity=Severity.ERROR,
                    code="materials_manifests.variant_albedo_missing",
                    message=f"variant '{v.get('id', '?')}' albedo missing from partly-populated source dir",
                    path=str(albedo),
                    details={"biome": biome, "slot": slot, "source": source},
                ))
    max_total = int(parsed.get("max_total_variant_layers", 256))
    if total_layers > max_total:
        issues.append(Issue(
            severity=Severity.ERROR,
            code="materials_manifests.total_layers_over_cap",
            message=f"total variant layers {total_layers} > cap {max_total}",
            path=str(mv_path),
        ))
    return issues


def _check_detail_arrays(world: Path) -> list[Issue]:
    issues: list[Issue] = []
    materials_root = world / "materials"
    if not materials_root.exists():
        return issues
    for biome_dir in sorted(materials_root.glob("biome_*")):
        da_path = biome_dir / "detail_array.json"
        if not da_path.exists():
            continue
        parsed, err = _load_json(da_path)
        if err is not None:
            issues.append(Issue(
                severity=Severity.ERROR,
                code="materials_manifests.detail_array_unparseable",
                message=err,
                path=str(da_path),
            ))
            continue
        assert parsed is not None
        biome = parsed.get("biome", "")
        detail_tiles: list[str] = list(parsed.get("detail_tiles", []))
        known_tiles = set(detail_tiles)
        detail_dir = biome_dir / "detail"
        # Each declared tile must have at least albedo on disk. Treat
        # "whole detail/ dir missing" as warning (not yet promoted);
        # specific-file missing while detail/ exists as error (broken
        # state).
        detail_dir_exists = detail_dir.exists()
        for tile in detail_tiles:
            albedo = detail_dir / f"{tile}_albedo.png"
            if albedo.exists():
                continue
            if not detail_dir_exists:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="materials_manifests.detail_dir_not_yet_promoted",
                    message=f"detail/ dir missing for biome '{biome}'; tile '{tile}' not promoted",
                    path=str(detail_dir),
                    details={"biome": biome, "tile": tile},
                ))
            else:
                issues.append(Issue(
                    severity=Severity.ERROR,
                    code="materials_manifests.detail_tile_albedo_missing",
                    message=f"detail tile '{tile}' albedo missing from existing detail/ dir",
                    path=str(albedo),
                    details={"biome": biome, "tile": tile},
                ))
        # slot_blends must only reference declared tiles + weights in [0,1]
        for slot, weights in (parsed.get("slot_blends") or {}).items():
            if not isinstance(weights, dict):
                continue
            for tile, w in weights.items():
                if tile not in known_tiles:
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="materials_manifests.detail_unknown_tile_ref",
                        message=f"slot '{slot}' references undeclared tile '{tile}'",
                        path=str(da_path),
                        details={"biome": biome, "slot": slot, "tile": tile},
                    ))
                try:
                    wf = float(w)
                except (TypeError, ValueError):
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="materials_manifests.detail_weight_not_number",
                        message=f"slot '{slot}' tile '{tile}' weight not a number",
                        path=str(da_path),
                    ))
                    continue
                if wf < 0.0 or wf > 1.0:
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="materials_manifests.detail_weight_out_of_range",
                        message=f"slot '{slot}' tile '{tile}' weight {wf} out of [0,1]",
                        path=str(da_path),
                    ))
    return issues


def run(repo_root: Path, world_path: Path | None, tier: str) -> list[Issue]:
    if world_path is None:
        return []  # repo-only mode; nothing to check
    issues: list[Issue] = []
    issues.extend(_check_material_variants(world_path))
    issues.extend(_check_detail_arrays(world_path))
    return issues
