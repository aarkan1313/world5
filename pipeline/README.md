# W5 Pipeline

Engine-agnostic Python content pipeline for W5. Generates the assets
the runtime engine consumes: terrain kernel outputs, PBR textures,
TRELLIS 3D meshes, LOD chains, decoration blobs, nav exports, etc.

## Status

**Phase 0 scaffold.** Empty `world5` package + `pyproject.toml` only.
Per-system code lands in Phase 2+ per [`../docs/ROADMAP.md`](../docs/ROADMAP.md).

## Install

```bash
pip install -e ./pipeline
```

After install, `python -c "import world5; print(world5.__version__)"`
should print `0.0.1`.

## Directory layout

```
pipeline/
├── world5/                 # Python package (importable as `world5`)
│   └── __init__.py
├── pyproject.toml          # editable-install package config
├── README.md
├── core/                   # cross-cutting Python primitives
├── kernels/                # terrain kernels (Python side; Phase 2+)
├── textures/               # texture pipeline (Phase 5)
├── trellis/                # 3D asset generation (Phase 7+)
├── decoration/             # offline decoration bake (Phase 7)
├── foliage/                # parametric tree generation (Phase 8)
├── nav/                    # nav export (Phase 4+)
├── world_contract/         # preflight + schema validators (Phase 2)
├── lighting/               # recipe builders (Phase 9)
├── atmosphere/             # profile builders (Phase 9)
├── water/                  # (Phase 10)
├── weather/                # (Phase 11)
├── caves/                  # (Phase 12)
├── deformation/            # (Phase 13)
├── persistence/            # (Phase 14)
├── impostors/              # (Phase 8 H)
├── lod/                    # LOD bake (Phase 7+)
├── roads/                  # (Phase 14+)
├── bake_recipes/           # 2.5D / topdown / world-map bake (Phase 15)
├── migrations/             # semver migration scripts (per spec 17)
├── release/                # release build (Phase 16)
├── forkability/            # fork validation (Phase 16)
└── docs/                   # build_sitemap.py + doc tools
```

## GPU mutex

Per spec 25, `pipeline/core/gpu_mutex.py` will provide TRELLIS +
ComfyUI serialization (cross-pipeline GPU lock). Builds in Phase 2.

## Doc cap status

This file: ~50 lines.
