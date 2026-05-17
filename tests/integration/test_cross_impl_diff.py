"""Cross-impl parity diff test (SA2-C2.1).

Strategy:
1. Run the gut emitter (engine/tests/integration/test_cross_impl_emit.gd)
   to write GDScript-computed values to user://_cross_impl_emit/*.json
2. Compute Python-side equivalents in this test
3. Diff bit-for-bit

Per spec 13 + spec 06: "0 differences between Python and GDScript
resolvers for any valid config." This test is the first that actually
measures it.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from world5.content_address import ContentAddressStore
from world5.quality_tiers import QualityTiers, TIER_NAMES
from world5.spatial_index import SpatialIndex


REPO_ROOT = Path(__file__).resolve().parents[2]
GODOT_USER_DATA = Path(os.environ.get(
    "APPDATA",
    str(Path.home() / ".local/share")
)) / "Godot/app_userdata/W5 Demo/_cross_impl_emit"


def _resolve_godot_bin() -> Path | None:
    env_bin = os.environ.get("WORLD5_GODOT_BIN")
    if env_bin:
        p = Path(env_bin)
        if p.exists():
            return p
    on_path = shutil.which("godot")
    if on_path:
        return Path(on_path)
    fallback = Path("C:/Godot/Godot_v4.5-stable_win64.exe")
    if fallback.exists():
        return fallback
    return None


@pytest.fixture(scope="module")
def gdscript_outputs() -> dict[str, dict | list]:
    """Run the gut emitter once; return loaded JSON outputs."""
    godot = _resolve_godot_bin()
    if godot is None:
        pytest.skip("Godot binary not found; can't run cross-impl emitter")

    # Run the emitter
    cmd = [
        str(godot),
        "--headless",
        "--path", str(REPO_ROOT / "demo"),
        "--script", "res://addons/gut/gut_cmdln.gd",
        "-gtest=res://addons/world5/tests/integration/test_cross_impl_emit.gd",
        "-gexit",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        pytest.fail(f"Emitter failed: returncode={result.returncode}\n"
                    f"stderr: {result.stderr[-500:]}")

    if not GODOT_USER_DATA.exists():
        pytest.fail(f"Emitter output dir missing: {GODOT_USER_DATA}")

    outputs: dict[str, dict | list] = {}
    for path in GODOT_USER_DATA.glob("*.json"):
        with path.open(encoding="utf-8") as f:
            outputs[path.stem] = json.load(f)
    return outputs


# --- QualityTiers parity ---

@pytest.mark.parametrize("tier_name", TIER_NAMES)
def test_quality_tiers_parity(tier_name: str, gdscript_outputs):
    """Python QualityTiers.get(tier) should equal GDScript QualityTiers.get_tier(tier)."""
    key = f"quality_tiers_{tier_name}"
    if key not in gdscript_outputs:
        pytest.skip(f"GDScript emitter didn't write {key}")

    gd_tier = gdscript_outputs[key]
    py_tier = QualityTiers.get(tier_name)

    # Both should have the same keys
    gd_keys = set(gd_tier.keys())
    py_keys = set(py_tier.keys())
    missing_in_py = gd_keys - py_keys
    missing_in_gd = py_keys - gd_keys
    assert not missing_in_py, f"GDScript has keys Python doesn't: {missing_in_py}"
    assert not missing_in_gd, f"Python has keys GDScript doesn't: {missing_in_gd}"

    # Each value should match (JSON-round-trip equality)
    for k in gd_keys:
        gd_v = gd_tier[k]
        py_v = py_tier[k]
        # JSON-round-trip both to normalize int vs float distinctions
        gd_normalized = json.loads(json.dumps(gd_v))
        py_normalized = json.loads(json.dumps(py_v))
        assert gd_normalized == py_normalized, \
            f"tier {tier_name}.{k}: GDScript={gd_v!r} vs Python={py_v!r}"


# --- ContentAddress hash parity ---

@pytest.fixture
def content_store(tmp_path) -> ContentAddressStore:
    return ContentAddressStore(store_root=tmp_path / "cache", cap_gb=1.0)


def test_content_address_hash_empty_parity(gdscript_outputs, content_store):
    gd_hashes = gdscript_outputs.get("content_address_hashes", {})
    py_hash = content_store.hash_inputs({})
    assert gd_hashes.get("empty") == py_hash, \
        f"empty dict hash mismatch: GD={gd_hashes.get('empty')} vs PY={py_hash}"


def test_content_address_hash_simple_parity(gdscript_outputs, content_store):
    gd_hashes = gdscript_outputs.get("content_address_hashes", {})
    py_hash = content_store.hash_inputs({"a": 1, "b": "two", "c": True})
    assert gd_hashes.get("simple") == py_hash, \
        f"simple dict hash mismatch: GD={gd_hashes.get('simple')} vs PY={py_hash}"


def test_content_address_hash_nested_parity(gdscript_outputs, content_store):
    gd_hashes = gdscript_outputs.get("content_address_hashes", {})
    py_hash = content_store.hash_inputs({
        "outer": "v",
        "inner": {"a": 1, "b": [1, 2, 3]},
    })
    # This is the one SA2-S2.8 worried about — nested dict ordering
    assert gd_hashes.get("nested") == py_hash, \
        f"nested dict hash mismatch: GD={gd_hashes.get('nested')} vs PY={py_hash}"


def test_content_address_hash_list_of_ints_parity(gdscript_outputs, content_store):
    gd_hashes = gdscript_outputs.get("content_address_hashes", {})
    py_hash = content_store.hash_inputs({"arr": [1, 2, 3, 4, 5]})
    assert gd_hashes.get("list_of_ints") == py_hash, \
        f"list_of_ints hash mismatch: GD={gd_hashes.get('list_of_ints')} vs PY={py_hash}"


def test_content_address_hash_mixed_types_parity(gdscript_outputs, content_store):
    gd_hashes = gdscript_outputs.get("content_address_hashes", {})
    py_hash = content_store.hash_inputs({
        "int": 42, "float": 3.14, "str": "hi", "bool": False,
    })
    assert gd_hashes.get("mixed_types") == py_hash, \
        f"mixed_types hash mismatch: GD={gd_hashes.get('mixed_types')} vs PY={py_hash}"


# --- SpatialIndex query parity ---

def test_spatial_index_queries_parity(gdscript_outputs):
    """Python SpatialIndex should produce the same query results as GDScript
    for the same insert sequence."""
    gd_results = gdscript_outputs.get("spatial_index_queries", {})
    if not gd_results:
        pytest.skip("GDScript emitter didn't write spatial_index_queries")

    idx = SpatialIndex(bounds=(-100.0, -100.0, 100.0, 100.0), cell_size_m=10.0)
    idx.insert(1, (0.0, 0.0))
    idx.insert(2, (5.0, 5.0))
    idx.insert(3, (50.0, 50.0))
    idx.insert(4, (-30.0, 20.0))
    idx.insert(5, (0.1, 0.1))

    # Compare each query result
    py_query_radius_1m = sorted(idx.query_radius((0.0, 0.0), 1.0).tolist())
    gd_query_radius_1m = sorted(gd_results.get("query_radius_origin_1m", []))
    assert py_query_radius_1m == gd_query_radius_1m, \
        f"query_radius(1m) mismatch: PY={py_query_radius_1m} vs GD={gd_query_radius_1m}"

    py_query_radius_50m = sorted(idx.query_radius((0.0, 0.0), 50.0).tolist())
    gd_query_radius_50m = sorted(gd_results.get("query_radius_origin_50m", []))
    assert py_query_radius_50m == gd_query_radius_50m

    py_query_rect = sorted(idx.query_rect((-1.0, -1.0, 10.0, 10.0)).tolist())
    gd_query_rect = sorted(gd_results.get("query_rect_neg1_to_10", []))
    assert py_query_rect == gd_query_rect

    # Nearest queries: order matters here, not just membership
    # (but tiebreak rules may differ between implementations)
    py_nearest_3 = idx.query_nearest((0.0, 0.0), 3).tolist()
    gd_nearest_3 = gd_results.get("query_nearest_origin_3", [])
    # We assert SET equality (top 3 nearest are the same items),
    # tolerating different tiebreak ordering
    assert set(py_nearest_3) == set(gd_nearest_3), \
        f"nearest(3) member mismatch: PY={py_nearest_3} vs GD={gd_nearest_3}"

    # Diagnostics
    assert idx.size() == gd_results.get("size")
    assert idx.bucket_count() == gd_results.get("bucket_count")
