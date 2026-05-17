"""Tests for world5.textures.promote — the candidate→world promotion tool.

Per plan 25 step 4. promote.py is net-new in W5 (doesn't exist in W4
where this step is done by hand in Explorer). Plan: "single
highest-leverage Phase 5 tooling deliverable."

Test cases cover:
- Base + sibling copy with canonical rename (v0_, v1_, ... prefix)
- Manifest update (adds sibling variants, preserves world_seed, etc.)
- Missing source files refuse (raises) before touching the world
- Existing world files are overwritten (idempotent re-run)
- All 4 PBR maps (albedo / normal / roughness / ao) copied per variant
- A diff summary returned (in/out/manifest deltas)
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from PIL import Image

from world5.textures import promote


# ---------- fixtures ----------


def _write_pbr_set(out_dir: Path, color: tuple[int, int, int] = (128, 128, 128)) -> None:
    """Write the standard 4-map PBR set to out_dir."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for map_name in ("albedo", "normal", "roughness", "ao"):
        # Each map a tiny solid color — just need real PNG files on disk.
        img_color = color if map_name == "albedo" else (200, 200, 200)
        Image.new("RGB", (4, 4), img_color).save(out_dir / f"{map_name}.png")


def _initial_manifest() -> dict:
    return {
        "_schema_version": 1,
        "world_seed": 42,
        "region_size_m": 512.0,
        "edge_blend_m": 48.0,
        "max_variants_per_slot": 8,
        "max_total_variant_layers": 256,
        "slots": [
            {
                "biome": "alpine",
                "slot": "ground",
                "variants": [
                    # Spec 24 schema: source is biome-relative (engine
                    # prepends biome_<biome>/ at resolution time).
                    {"id": "default", "source": "ground", "weight": 1.0}
                ],
            }
        ],
    }


@pytest.fixture
def world(tmp_path: Path) -> Path:
    """Set up a fake world dir with materials/ + an initial manifest."""
    world_root = tmp_path / "world"
    materials = world_root / "materials"
    materials.mkdir(parents=True)
    # Pre-existing default base set (the walking_demo "empty" state has
    # only the dir tree, no images, but promote shouldn't care).
    manifest_path = world_root / "material_variants.json"
    manifest_path.write_text(json.dumps(_initial_manifest(), indent=2))
    return world_root


@pytest.fixture
def candidates(tmp_path: Path) -> Path:
    """Set up a fake candidates tree with 5 ground PBR sets."""
    cand_root = tmp_path / "candidates" / "alpine" / "ground"
    for tag in ("03_firn_dense", "s05_firn", "s07_firn", "s09_firn", "s11_firn"):
        _write_pbr_set(cand_root / tag)
    return cand_root.parent.parent  # tmp_path/candidates


# ---------- happy path ----------


def test_promote_base_only(world: Path, candidates: Path) -> None:
    """Promote a single base tile (no siblings) into the world bundle."""
    result = promote.promote(
        world=world,
        candidates_root=candidates,
        biome="alpine",
        promotions=[
            promote.SlotPromotion(slot="ground", base="03_firn_dense", siblings=[]),
        ],
    )

    # 4 maps copied from candidates → world materials base dir
    base_dir = world / "materials" / "biome_alpine" / "ground"
    for m in ("albedo", "normal", "roughness", "ao"):
        assert (base_dir / f"{m}.png").exists(), f"{m}.png missing from base"

    # Manifest still has 1 variant for ground (the default)
    manifest = json.loads((world / "material_variants.json").read_text())
    ground = next(s for s in manifest["slots"] if s["slot"] == "ground")
    assert len(ground["variants"]) == 1

    assert result.files_copied >= 4
    # summary is a list of human-readable lines; one entry per
    # base/sibling copy. Substring-match each line against the tag.
    assert any("ground/base=03_firn_dense" in line for line in result.summary)


def test_promote_base_plus_siblings(world: Path, candidates: Path) -> None:
    """Promote base + 4 siblings; manifest gains the sibling entries."""
    result = promote.promote(
        world=world,
        candidates_root=candidates,
        biome="alpine",
        promotions=[
            promote.SlotPromotion(
                slot="ground",
                base="03_firn_dense",
                siblings=["s05_firn", "s07_firn", "s09_firn", "s11_firn"],
            ),
        ],
    )

    # Siblings land at biome_alpine/ground_variants/v0_*, v1_*, ...
    sib_dir = world / "materials" / "biome_alpine" / "ground_variants"
    assert sib_dir.exists()
    for i in range(4):
        for m in ("albedo", "normal", "roughness", "ao"):
            # Canonical layout: v<i>_<tag>/<map>.png (per plan 25
            # step 4 + spec 23 example layout)
            v_dirs = list(sib_dir.glob(f"v{i}_*"))
            assert len(v_dirs) == 1, f"expected one v{i}_* dir, got {v_dirs}"
            assert (v_dirs[0] / f"{m}.png").exists()

    # Manifest gained 4 sibling entries
    manifest = json.loads((world / "material_variants.json").read_text())
    ground = next(s for s in manifest["slots"] if s["slot"] == "ground")
    assert len(ground["variants"]) == 5  # 1 default + 4 siblings

    # World seed + region size preserved (mutations are additive)
    assert manifest["world_seed"] == 42
    assert manifest["region_size_m"] == 512.0

    assert result.files_copied >= 20  # 5 variants × 4 maps
    assert result.manifest_added == 4


def test_promote_overwrites_existing_files(world: Path, candidates: Path) -> None:
    """Re-running promote with the same base updates files in place."""
    base_dir = world / "materials" / "biome_alpine" / "ground"
    base_dir.mkdir(parents=True)
    # Pre-existing dummy file with distinctive content
    Image.new("RGB", (2, 2), (255, 0, 0)).save(base_dir / "albedo.png")

    promote.promote(
        world=world,
        candidates_root=candidates,
        biome="alpine",
        promotions=[
            promote.SlotPromotion(slot="ground", base="03_firn_dense", siblings=[]),
        ],
    )

    # The new albedo should match the candidate (4×4 grey) not the
    # 2×2 red we wrote first.
    new_img = Image.open(base_dir / "albedo.png")
    assert new_img.size == (4, 4)


# ---------- validation ----------


def test_missing_base_candidate_raises(world: Path, candidates: Path) -> None:
    """Missing candidate refuses before touching the world."""
    with pytest.raises(promote.PromoteError) as exc:
        promote.promote(
            world=world,
            candidates_root=candidates,
            biome="alpine",
            promotions=[
                promote.SlotPromotion(slot="ground", base="ghost", siblings=[]),
            ],
        )
    assert "ghost" in str(exc.value)
    # World untouched (manifest still has just the default variant)
    manifest = json.loads((world / "material_variants.json").read_text())
    ground = next(s for s in manifest["slots"] if s["slot"] == "ground")
    assert len(ground["variants"]) == 1


def test_missing_sibling_candidate_raises_before_any_copy(
    world: Path, candidates: Path
) -> None:
    """If a sibling is missing, refuse before any base copy happens."""
    with pytest.raises(promote.PromoteError):
        promote.promote(
            world=world,
            candidates_root=candidates,
            biome="alpine",
            promotions=[
                promote.SlotPromotion(
                    slot="ground",
                    base="03_firn_dense",
                    siblings=["s05_firn", "ghost"],
                ),
            ],
        )
    # Base must NOT have been copied — atomic validation gate
    base_dir = world / "materials" / "biome_alpine" / "ground"
    assert not (base_dir / "albedo.png").exists(), (
        "promote must validate ALL inputs before copying ANY file"
    )


def test_exceeding_sibling_cap_raises(world: Path, candidates: Path) -> None:
    """Spec 24 caps per-slot variants at 8 (shader limit)."""
    # Create 8 sibling candidates (so 1 base + 8 siblings = 9 → over cap)
    cand_root = candidates / "alpine" / "ground"
    for i in range(8):
        _write_pbr_set(cand_root / f"extra_{i}")
    with pytest.raises(promote.PromoteError) as exc:
        promote.promote(
            world=world,
            candidates_root=candidates,
            biome="alpine",
            promotions=[
                promote.SlotPromotion(
                    slot="ground",
                    base="03_firn_dense",
                    siblings=[f"extra_{i}" for i in range(8)],
                ),
            ],
        )
    assert "cap" in str(exc.value).lower() or "8" in str(exc.value)


# ---------- manifest correctness ----------


def test_manifest_pre_existing_siblings_replaced_not_appended(
    world: Path, candidates: Path
) -> None:
    """Re-promoting a slot replaces the slot's variants, doesn't append.

    Otherwise re-running with one less sibling would leave a stale entry.
    """
    # Seed manifest with pre-existing siblings
    manifest_path = world / "material_variants.json"
    m = json.loads(manifest_path.read_text())
    ground = next(s for s in m["slots"] if s["slot"] == "ground")
    ground["variants"] = [
        {"id": "default", "source": "ground", "weight": 1.0},
        {"id": "v0_stale", "source": "ground_variants/v0_stale",
         "weight": 1.0},
    ]
    manifest_path.write_text(json.dumps(m, indent=2))

    promote.promote(
        world=world,
        candidates_root=candidates,
        biome="alpine",
        promotions=[
            promote.SlotPromotion(
                slot="ground",
                base="03_firn_dense",
                siblings=["s05_firn"],
            ),
        ],
    )

    m_after = json.loads(manifest_path.read_text())
    ground_after = next(s for s in m_after["slots"] if s["slot"] == "ground")
    ids = [v["id"] for v in ground_after["variants"]]
    assert "v0_stale" not in ids, "stale sibling must be removed"
    assert "default" in ids
    assert any(i.startswith("v0_") for i in ids), "new sibling present"


# ---------- CLI ----------


def test_cli_missing_args_returns_2(capsys: pytest.CaptureFixture[str]) -> None:
    code = promote.main([])
    assert code == 2
    err = capsys.readouterr().err
    assert "missing required args" in err


def test_cli_happy_path(
    world: Path, candidates: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    code = promote.main([
        "--world", str(world),
        "--candidates-root", str(candidates),
        "--biome", "alpine",
        "--slot", "ground",
        "--base", "03_firn_dense",
        "--siblings", "s05_firn", "s07_firn",
    ])
    assert code == 0
    out = capsys.readouterr().out
    assert "files copied" in out
    # Files actually landed
    assert (world / "materials" / "biome_alpine" / "ground" / "albedo.png").exists()
    sib_dirs = list((world / "materials" / "biome_alpine" / "ground_variants").iterdir())
    assert len(sib_dirs) == 2
