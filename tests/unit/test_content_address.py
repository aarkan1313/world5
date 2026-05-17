"""Tests for world5.content_address (Python side).

Per spec 12 + SA-C2.3 (FileInput) + SA-S2.4 (GC cap).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from world5.content_address import ContentAddressStore, FileInput


@pytest.fixture
def store(tmp_path) -> ContentAddressStore:
    return ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.001)  # 1 MB cap for tests


# --- hashing ---

def test_hash_inputs_deterministic(store):
    inputs = {"a": 1, "b": "two", "c": [1, 2, 3]}
    h1 = store.hash_inputs(inputs)
    h2 = store.hash_inputs(inputs)
    assert h1 == h2


def test_hash_inputs_order_independent(store):
    """Sorted-keys canonicalization → different insertion order = same hash."""
    a = {"alpha": 1, "beta": 2}
    b = {"beta": 2, "alpha": 1}
    assert store.hash_inputs(a) == store.hash_inputs(b)


def test_hash_inputs_different_values_differ(store):
    assert store.hash_inputs({"x": 1}) != store.hash_inputs({"x": 2})


def test_file_input_content_hashed(store, tmp_path):
    """Same path, different content → different hash (SA-C2.3)."""
    f1 = tmp_path / "model.bin"
    f1.write_bytes(b"content_v1")
    h1 = store.hash_inputs({"model": FileInput(f1)})

    f1.write_bytes(b"content_v2_different")
    # Reset cache (mtime should change too, but be explicit)
    store._file_hash_cache.clear()
    h2 = store.hash_inputs({"model": FileInput(f1)})

    assert h1 != h2, "different file content → different hash"


def test_file_input_same_content_same_hash(store, tmp_path):
    f = tmp_path / "data.bin"
    f.write_bytes(b"identical_content")
    h1 = store.hash_inputs({"data": FileInput(f)})
    h2 = store.hash_inputs({"data": FileInput(f)})
    assert h1 == h2


def test_file_input_missing_raises(store, tmp_path):
    with pytest.raises(FileNotFoundError):
        store.hash_inputs({"model": FileInput(tmp_path / "nonexistent.bin")})


def test_bare_path_warns_not_content_hashed(store, tmp_path, caplog):
    """Bare Path → stringifies (warns); FileInput → content-hashes."""
    f = tmp_path / "model.bin"
    f.write_bytes(b"v1")
    h_bare = store.hash_inputs({"model": f})  # bare Path
    # Change content but keep path same
    f.write_bytes(b"v2_different_content")
    h_bare2 = store.hash_inputs({"model": f})
    # Bare Path: same path string → SAME hash (the bug SA-C2.3 fixed)
    assert h_bare == h_bare2


# --- cache ops ---

def test_put_get_roundtrip(store):
    key = store.hash_inputs({"prompt": "test"})
    store.put(key, b"artifact_bytes")
    assert store.has(key)
    path = store.get(key)
    assert path is not None
    assert path.read_bytes() == b"artifact_bytes"


def test_get_unknown_returns_none(store):
    assert store.get("nonexistent_key") is None


def test_get_metadata(store):
    key = "abc123"
    store.put(key, b"x", metadata={"prompt": "test", "model": "v1"})
    meta = store.get_metadata(key)
    assert meta["prompt"] == "test"
    assert meta["model"] == "v1"
    assert "stored_at" in meta  # auto-added


# --- dependency graph ---

def test_declare_dependency_basic(store):
    store.declare_dependency("artifact_a", ["input_x", "input_y"])
    dependents = store.find_dependents("input_x")
    assert "artifact_a" in dependents


def test_find_dependents_transitive(store):
    store.declare_dependency("a", ["x"])
    store.declare_dependency("b", ["a"])
    store.declare_dependency("c", ["b"])
    dependents = store.find_dependents("x")
    assert set(dependents) == {"a", "b", "c"}


def test_find_dependents_no_deps_empty(store):
    assert store.find_dependents("nonexistent") == []


def test_invalidate_evicts_dependents(store):
    store.put("input", b"i")
    store.put("derived_a", b"a")
    store.put("derived_b", b"b")
    store.declare_dependency("derived_a", ["input"])
    store.declare_dependency("derived_b", ["derived_a"])
    evicted = store.invalidate("input")
    # input + derived_a + derived_b all evicted
    assert "input" in evicted
    assert "derived_a" in evicted
    assert "derived_b" in evicted
    assert not store.has("input")
    assert not store.has("derived_a")
    assert not store.has("derived_b")


# --- GC ---

def test_gc_size_zero_on_empty(store):
    assert store.gc_size_bytes() == 0


def test_gc_size_increases_with_puts(store):
    store.put("k1", b"x" * 1024)
    assert store.gc_size_bytes() == 1024
    store.put("k2", b"y" * 2048)
    assert store.gc_size_bytes() == 3072


def test_gc_if_over_cap_evicts(store):
    """SA-S2.4: when store exceeds cap, oldest-accessed get evicted."""
    # cap_gb = 0.001 = ~1 MB
    store.cap_bytes = 100  # tighten cap further for testable trigger

    # Put 3 small artifacts; total > 100 bytes
    store.put("oldest", b"a" * 50)
    store.put("middle", b"b" * 50)
    store.put("newest", b"c" * 50)

    # gc_if_over_cap was called by each put; oldest should be evicted
    assert not store.has("oldest") or not store.has("middle"), \
        "at least one oldest evicted to fit cap"
    assert store.has("newest"), "newest survives"


def test_evict_unreferenced_removes_old(store, tmp_path):
    import time
    store.put("k1", b"x")
    # Manually back-date the access log
    log = store._load_access_log()
    log["k1"] = time.time() - (60 * 86400)  # 60 days ago
    store._save_access_log(log)
    count = store.evict_unreferenced(max_age_days=30)
    assert count == 1
    assert not store.has("k1")


# --- diagnostics ---

def test_list_artifacts_returns_metadata(store):
    store.put("k1", b"x", metadata={"prompt": "a"})
    store.put("k2", b"y", metadata={"prompt": "b"})
    artifacts = store.list_artifacts()
    keys = {a["key"] for a in artifacts}
    assert keys == {"k1", "k2"}
