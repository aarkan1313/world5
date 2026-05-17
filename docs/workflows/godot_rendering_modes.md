# Workflow: Godot Rendering Modes — Headless vs Real GPU

> When + how to launch Godot for different test / build needs.
> Investigated 2026-05-16 (Phase 2.5); the `--headless` /
> RenderingDevice incompatibility was the trigger.
>
> See pitfall meta-2 for the symptom-lookup version. This doc is the
> recipe (how to apply).

## TL;DR

| Need | Launch flags |
|---|---|
| Run gut tests with no GPU work | `--headless --path demo --script ...` |
| Run gut tests that need RenderingDevice | `--display-driver windows --rendering-driver vulkan --path demo --script ...` |
| Open the project in editor for manual work | (just open Godot, point at `demo/project.godot`) |
| Re-import after adding class_name files | `--headless --path demo --import` |
| Test on a CI runner without a GPU | `--headless` (real GPU tests skip via `pending()`) |

## Why `--headless` disables RenderingDevice

`--headless` is shorthand for:
```
--display-driver headless --audio-driver Dummy
```

The `headless` display driver only supports the `dummy` rendering
driver, which provides no Vulkan/D3D12/OpenGL pipeline. So
`RenderingServer.get_rendering_device()` returns `null`. Any
`RenderingDevice.*` call from a gut test crashes.

This is intentional Godot behavior — servers without GPUs need to
run scripts. It's not a bug.

Sources:
- [RenderingDevice docs](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html)
- [Compute shader docs](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)
- [Godot 4.5 internal rendering architecture](https://docs.godotengine.org/en/4.5/engine_details/architecture/internal_rendering_architecture.html)

## The fix: launch with a real display driver

For tests / scripts that need a real GPU:
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" \
  --display-driver windows \
  --rendering-driver vulkan \
  --path demo \
  --script "res://addons/gut/gut_cmdln.gd" \
  -gtest=res://addons/world5/tests/unit/test_gpu_real_device.gd \
  -gexit
```

A real (briefly visible) Vulkan window appears + closes when the
script exits. ~1-2s overhead vs headless launch.

`--display-driver windows` is the Windows-specific real driver.
On Mac use `--display-driver macos`; on Linux `--display-driver x11`
or `wayland`. Other valid `--rendering-driver` values: `d3d12`
(Windows-only), `opengl3` (legacy; per W4 memory
`godot_headless_null_viewport`, opengl3 mode also gives a usable
viewport but with the compatibility renderer's feature set).

## The test pattern that handles both modes

So one test file can run cleanly under both `--headless` (skips real
GPU tests) and the windowed launch (runs them):

```gdscript
func test_my_gpu_thing() -> void:
    var rd: RenderingDevice = RenderingServer.get_rendering_device()
    if rd == null:
        pending("RenderingDevice unavailable; run with --display-driver windows")
        return
    # ... real GPU work using rd ...
    var buf := rd.storage_buffer_create(256, data)
    # etc.
```

`pending()` is gut's "this test is intentionally skipped, not a
failure" signal. The full run summary shows `Pending` count
separately from passes / fails.

## Naming convention for real-GPU tests

Per spec 06 Layer 3a + `verify --full` integration:

```
engine/tests/<unit|integration>/test_<system>_real_device.gd
```

The `_real_device.gd` suffix is the filter the verify CLI uses to
collect real-GPU tests for the `--full` mode's `gut_real_gpu` layer.

Tests without the suffix run in `--headless` mode (gut layer); tests
WITH the suffix run in `--display-driver windows` mode (gut_real_gpu
layer). Same test file CAN have a `pending()` fallback so it works
in both — but for clarity + verify-layer separation, put real-GPU
tests in their own file.

## Working example: compute shader test

`engine/tests/unit/test_gpu_real_device.gd::test_compute_shader_dispatch`
ships a minimal compute shader that doubles 64 floats:

```gdscript
var shader_source := RDShaderSource.new()
shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
shader_source.source_compute = """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict buffer Data {
    float data[];
} buf;
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i < buf.data.length()) {
        buf.data[i] = buf.data[i] * 2.0;
    }
}
"""
var spirv := rd.shader_compile_spirv_from_source(shader_source)
var shader_rid := rd.shader_create_from_spirv(spirv)
# ... bind buffer, dispatch 1 workgroup of 64, sync, read back ...
```

This is the template for spec 19 kernel system + spec 20 terrain
backend GPU compute paths when those land in Phases 4-5.

## What happens in `verify --full`

The CLI launches Godot TWICE:

1. **Layer 2 (`gut`)**: `--headless` — collects all `test_*.gd` files
   in `engine/tests/` recursively (~70 tests for Phase 2.6). Real-GPU
   tests `pending()` themselves silently.
2. **Layer 3 (`gut_real_gpu`)**: `--display-driver windows
   --rendering-driver vulkan` — collects only `test_*_real_device.gd`
   files via gut's suffix filter (`-gsuffix=_real_device.gd`).
   ~3 tests for Phase 2.6.

Combined: ~127 tests pass in ~3s on dev hardware.

## Gotchas

### Gotcha 1: Re-import after adding class_name files

Adding a new `class_name MyClass extends ...` GDScript file requires
Godot to register it in the global class registry. Until that
happens, gut tests that reference `MyClass` fail with
"GUT class_names have not been imported."

Fix: run a one-time import:
```bash
"/c/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe" --headless --path demo --import
```

The verify CLI doesn't auto-import (would slow every run). If gut
suddenly fails with class-name errors, run `--import` once.

### Gotcha 2: Vulkan window may flash visible

Under `--display-driver windows --rendering-driver vulkan`, a real
window briefly appears + closes when the script exits. On dev
hardware this is ~200ms. On CI / remote display, may not render at
all if there's no display server — in which case the test would
fail differently (need to test on real CI; not investigated yet).

### Gotcha 3: Junctions vs symlinks

`demo/addons/world5/` is a Windows Junction → `engine/`, not a
symlink. Created via `New-Item -ItemType Junction` (no admin needed
vs `mklink /D` which does need admin OR Developer Mode).

Junctions work the same as symlinks for filesystem reads, BUT:
- `git status` shows them as regular dirs
- Some tools (notably some Python `Path.resolve()` calls) may treat
  them differently than symlinks

The junction itself is `.gitignored` — each contributor creates their
own via setup.py (lands in Phase 2.12).

## See also

- [spec 06 TEST_INFRASTRUCTURE](../specs/06_TEST_INFRASTRUCTURE.md) — Layer 3a definition
- [spec 08a GPU_CPU_CONTRACT](../specs/08a_GPU_CPU_CONTRACT.md) — what RenderingDevice work is sanctioned
- [pitfall meta-2](../reference/pitfalls/pitfalls_meta.md#2) — symptom-lookup
  version
- [running_tests.md](running_tests.md) — full test invocation guide

## Doc cap status

This file: ~180 lines.
