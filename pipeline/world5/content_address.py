"""W5 content-addressed asset store.

Per spec 12 + SA-C2.3 (FileInput for file-typed inputs) + SA-S2.4
(GC size cap default 20 GB).

Every baked artifact (texture, mesh, LOD chain, decoration blob,
audio tag manifest, etc.) has a sha256 hash of its inputs as its
cache key. The dependency graph captures "this artifact depends on
these inputs"; an input change invalidates only downstream artifacts.

Storage layout (per spec 12):
    pipeline/.content_addressed_store/
    ├── objects/<sha2>/<sha_rest>  ← artifact bytes/file
    ├── metadata/<sha>.json        ← provenance: inputs, deps, etc.
    ├── deps.json                  ← dependency graph
    └── access_log.json            ← LRU eviction order
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from world5.log import log

SYSTEM_NAME = "content_address"

# Default store size cap (SA-S2.4). 20 GB matches the user memory
# d_drive_space_constraint headroom.
DEFAULT_CAP_GB = 20.0

# Hash chunk size for file-content hashing
_HASH_CHUNK_SIZE = 65536


@dataclass(frozen=True)
class FileInput:
    """Sentinel wrapping a file path so hash_inputs content-hashes the
    file instead of stringifying the path. Per SA-C2.3.

    Usage:
        inputs = {
            "prompt": "fresh snow",
            "model": FileInput(Path("models/flux2.safetensors")),
        }
        key = store.hash_inputs(inputs)
    """
    path: Path


class ContentAddressStore:
    """Filesystem-backed content-addressed artifact store."""

    def __init__(self, store_root: Path, cap_gb: float = DEFAULT_CAP_GB):
        self.store_root = Path(store_root)
        self.objects_dir = self.store_root / "objects"
        self.metadata_dir = self.store_root / "metadata"
        self.deps_path = self.store_root / "deps.json"
        self.access_log_path = self.store_root / "access_log.json"
        self.cap_bytes = int(cap_gb * 1024 * 1024 * 1024)
        # Cache of (path, mtime, size) → content hash to avoid re-reading
        # large model files on every hash_inputs call
        self._file_hash_cache: dict[tuple[str, float, int], str] = {}
        self._ensure_layout()

    # --- layout ---

    def _ensure_layout(self) -> None:
        self.store_root.mkdir(parents=True, exist_ok=True)
        self.objects_dir.mkdir(parents=True, exist_ok=True)
        self.metadata_dir.mkdir(parents=True, exist_ok=True)
        if not self.deps_path.exists():
            self.deps_path.write_text("{}", encoding="utf-8")
        if not self.access_log_path.exists():
            self.access_log_path.write_text("{}", encoding="utf-8")

    # --- hashing ---

    def hash_inputs(self, inputs: dict[str, Any]) -> str:
        """Compute a stable sha256 from input dict. FileInput entries are
        content-hashed via hash_file_input (SA-C2.3)."""
        # Resolve FileInput sentinels to their content hashes
        resolved: dict[str, Any] = {}
        for k, v in inputs.items():
            if isinstance(v, FileInput):
                resolved[k] = f"file:sha256:{self.hash_file_input(v.path)}"
            elif isinstance(v, Path):
                # Bare Path → warn (caller probably meant FileInput)
                log.warn(SYSTEM_NAME, "bare Path in hash_inputs; use FileInput for content-hashing",
                         key=k, path=str(v))
                resolved[k] = str(v)
            else:
                resolved[k] = v
        # Stable canonical JSON: sorted keys, no whitespace
        canonical = json.dumps(resolved, sort_keys=True, separators=(",", ":"),
                               default=str)
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def hash_file_input(self, path: Path) -> str:
        """Content-hash a file. Cached by (path, mtime, size) so repeated
        calls in one session are O(1)."""
        path = Path(path)
        if not path.exists():
            log.error(SYSTEM_NAME, "FileInput points at nonexistent file",
                      path=str(path))
            raise FileNotFoundError(f"FileInput: {path}")
        stat = path.stat()
        cache_key = (str(path.resolve()), stat.st_mtime, stat.st_size)
        if cache_key in self._file_hash_cache:
            return self._file_hash_cache[cache_key]
        h = hashlib.sha256()
        with path.open("rb") as f:
            while chunk := f.read(_HASH_CHUNK_SIZE):
                h.update(chunk)
        digest = h.hexdigest()
        self._file_hash_cache[cache_key] = digest
        return digest

    # --- cache ---

    def has(self, key: str) -> bool:
        return self._object_path(key).exists()

    def get(self, key: str) -> Path | None:
        path = self._object_path(key)
        if not path.exists():
            return None
        self._touch_access(key)
        return path

    def get_metadata(self, key: str) -> dict:
        mpath = self.metadata_dir / f"{key}.json"
        if not mpath.exists():
            return {}
        return json.loads(mpath.read_text(encoding="utf-8"))

    def put(self, key: str, artifact: Path | bytes, metadata: dict | None = None) -> None:
        """Store an artifact under `key`. Triggers GC if store > cap (SA-S2.4)."""
        opath = self._object_path(key)
        opath.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(artifact, Path):
            shutil.copy2(str(artifact), str(opath))
        elif isinstance(artifact, (bytes, bytearray)):
            opath.write_bytes(bytes(artifact))
        else:
            raise TypeError(f"artifact must be Path or bytes; got {type(artifact)}")
        # Write metadata
        meta = dict(metadata or {})
        meta.setdefault("stored_at", time.time())
        (self.metadata_dir / f"{key}.json").write_text(
            json.dumps(meta, sort_keys=True, indent=2), encoding="utf-8")
        self._touch_access(key)
        # SA-S2.4: auto-GC on every put
        self.gc_if_over_cap()

    # --- dependency graph ---

    def declare_dependency(self, key: str, depends_on: list[str]) -> None:
        deps = self._load_deps()
        deps.setdefault(key, [])
        for dep in depends_on:
            if dep not in deps[key]:
                deps[key].append(dep)
        self._save_deps(deps)

    def find_dependents(self, input_key: str) -> list[str]:
        """Returns all artifacts that transitively depend on input_key."""
        deps = self._load_deps()
        # Reverse map: dep → [keys that depend on it]
        reverse: dict[str, list[str]] = {}
        for key, dep_list in deps.items():
            for dep in dep_list:
                reverse.setdefault(dep, []).append(key)
        # BFS from input_key
        result: list[str] = []
        seen: set[str] = set()
        queue = [input_key]
        while queue:
            current = queue.pop(0)
            for dependent in reverse.get(current, []):
                if dependent not in seen:
                    seen.add(dependent)
                    result.append(dependent)
                    queue.append(dependent)
        return result

    # --- invalidation ---

    def invalidate(self, key: str) -> list[str]:
        """Remove `key` + all transitive dependents. Returns evicted keys."""
        to_evict = [key] + self.find_dependents(key)
        evicted: list[str] = []
        for k in to_evict:
            opath = self._object_path(k)
            mpath = self.metadata_dir / f"{k}.json"
            if opath.exists():
                opath.unlink()
                evicted.append(k)
            if mpath.exists():
                mpath.unlink()
        # Clean up empty bucket dirs
        for opath in self.objects_dir.iterdir():
            if opath.is_dir() and not any(opath.iterdir()):
                opath.rmdir()
        # Remove from dep graph
        deps = self._load_deps()
        for k in to_evict:
            deps.pop(k, None)
        self._save_deps(deps)
        return evicted

    # --- GC ---

    def evict_unreferenced(self, max_age_days: float = 30.0) -> int:
        """LRU eviction of artifacts not accessed in N days. Returns count."""
        access_log = self._load_access_log()
        cutoff = time.time() - (max_age_days * 86400)
        to_evict: list[str] = []
        for key, last_access in access_log.items():
            if last_access < cutoff:
                to_evict.append(key)
        count = 0
        for key in to_evict:
            opath = self._object_path(key)
            mpath = self.metadata_dir / f"{key}.json"
            if opath.exists():
                opath.unlink()
                count += 1
            if mpath.exists():
                mpath.unlink()
            access_log.pop(key, None)
        self._save_access_log(access_log)
        return count

    def gc_if_over_cap(self) -> int:
        """SA-S2.4: if store size exceeds cap, evict oldest-accessed
        artifacts until under cap. Returns count evicted."""
        size = self.gc_size_bytes()
        if size <= self.cap_bytes:
            return 0
        access_log = self._load_access_log()
        # Sort by access time ascending (oldest first)
        sorted_keys = sorted(access_log.keys(), key=lambda k: access_log[k])
        count = 0
        for key in sorted_keys:
            if size <= self.cap_bytes:
                break
            opath = self._object_path(key)
            mpath = self.metadata_dir / f"{key}.json"
            if opath.exists():
                size -= opath.stat().st_size
                opath.unlink()
                count += 1
            if mpath.exists():
                mpath.unlink()
            access_log.pop(key, None)
        self._save_access_log(access_log)
        if count > 0:
            log.info(SYSTEM_NAME, "GC evicted artifacts to fit cap",
                     evicted=count, cap_bytes=self.cap_bytes,
                     remaining_bytes=size)
        return count

    def gc_size_bytes(self) -> int:
        """Total bytes used by objects/."""
        total = 0
        for p in self.objects_dir.rglob("*"):
            if p.is_file():
                total += p.stat().st_size
        return total

    def gc_size_mb(self) -> int:
        return int(self.gc_size_bytes() / (1024 * 1024))

    # --- diagnostics ---

    def list_artifacts(self) -> list[dict]:
        out: list[dict] = []
        for mpath in self.metadata_dir.iterdir():
            if mpath.suffix == ".json":
                key = mpath.stem
                meta = json.loads(mpath.read_text(encoding="utf-8"))
                opath = self._object_path(key)
                out.append({
                    "key": key,
                    "size_bytes": opath.stat().st_size if opath.exists() else 0,
                    "metadata": meta,
                })
        return out

    # --- internals ---

    def _object_path(self, key: str) -> Path:
        return self.objects_dir / key[:2] / key[2:]

    def _load_deps(self) -> dict[str, list[str]]:
        return json.loads(self.deps_path.read_text(encoding="utf-8"))

    def _save_deps(self, deps: dict) -> None:
        self.deps_path.write_text(
            json.dumps(deps, sort_keys=True, indent=2), encoding="utf-8")

    def _load_access_log(self) -> dict[str, float]:
        return json.loads(self.access_log_path.read_text(encoding="utf-8"))

    def _save_access_log(self, log_dict: dict) -> None:
        self.access_log_path.write_text(
            json.dumps(log_dict, sort_keys=True, indent=2), encoding="utf-8")

    def _touch_access(self, key: str) -> None:
        access_log = self._load_access_log()
        access_log[key] = time.time()
        self._save_access_log(access_log)
