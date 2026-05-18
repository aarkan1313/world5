# Godot + Verify + GUT Command Reference

> Session reference captured 2026-05-17 for W5 on Godot 4.6.2 stable mono.
> Prefer the verify harness for normal testing. Use raw GUT commands only
> when targeting one Godot test file or debugging the harness itself.

## Walking Demo

Interactive launch command:

```powershell
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe `
  --path demo demo/scenes/walking_demo.tscn
```

Notes:

- Use the pinned 4.6.2 stable mono binary above. This avoids accidentally
  running an older Godot install.
- `--path demo` makes `demo/` the Godot project root.
- The final scene path opens the walking demo directly.
- Do not launch the editor as part of an agent verification loop. Print the
  interactive command for the user instead.

## Verify Harness

Canonical test entrypoint:

```powershell
python -m world5.verify --fastest
python -m world5.verify --fast
python -m world5.verify
python -m world5.verify --full
```

Mode meanings:

| Mode | Runs | Typical use |
|---|---|---|
| `--fastest` | pytest only | Fast Python/TDD loop |
| `--fast` | pytest + headless GUT | Normal local check |
| default | pytest + GUT + real-GPU GUT + preflight | Pre-commit style check |
| `--full` | all layers including capture/perf | Release or calibration check |

Harness implementation:

```text
pipeline/world5/verify/__init__.py
```

Verify layers:

1. `pytest`: Python pipeline tests under `tests/`.
2. `gut`: Godot tests in headless mode. No GPU rendering.
3. `gut_real_gpu`: Godot tests with Vulkan rendering.
4. `preflight`: world contract checks against on-disk bundles.
5. `capture`: visual regression captures.

## Raw GUT

Use raw GUT only when targeting one Godot test file or narrowing a failure.
GUT filtering is file-pattern based, not individual test-function based.

### Headless GUT

No rendering. Do not use this for tests that touch `RenderingDevice`,
SubViewport GPU readback, shaders, or `*_real_device.gd` files.

```powershell
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe `
  --headless `
  --path demo `
  --script res://addons/gut/gut_cmdln.gd `
  -gdir=res://addons/world5/tests/unit/ `
  -gprefix=test_material_pipeline `
  -gexit
```

### Real-GPU GUT

Required for real shaders, textures, compute, Vulkan, and files ending
`_real_device.gd`.

```powershell
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe `
  --display-driver windows --rendering-driver vulkan `
  --path demo `
  --script res://addons/gut/gut_cmdln.gd `
  -gdir=res://addons/world5/tests/ -ginclude_subdirs `
  -gprefix=test_ -gsuffix=_real_device.gd `
  -gexit
```

Flag notes:

- `--headless`: faster and windowless, but no real GPU rendering path.
- `--display-driver windows --rendering-driver vulkan`: real GPU path.
- `--path demo`: project root is the consumer demo project.
- `--script res://addons/gut/gut_cmdln.gd`: GUT CLI entrypoint.
- `-gdir=res://...`: directory to scan for test files.
- `-ginclude_subdirs`: recurse through test subdirectories.
- `-gprefix=...`: file prefix filter.
- `-gsuffix=...`: file suffix filter, commonly `_real_device.gd`.
- `-gexit`: quit Godot after tests finish.

Known quirks:

- `-gselect` alone is not enough; GUT still needs `-gdir`.
- GUT 9.4 uses `assert_lte`, not `assert_le`.
- The non-console Godot binary may not print useful stdout in PowerShell.
  The verify harness handles output parsing, so prefer it unless debugging.
- Headless mode can make GPU APIs return null. Use the real-GPU command for
  `*_real_device.gd` tests.
- In Codex sandboxed command runs, Godot may fail writing `user://logs` under
  `%APPDATA%/Godot/app_userdata/W5 Demo/logs` and then show a native Windows
  access-violation popup. That is a sandbox/userdata permission problem, not
  automatically a renderer crash. Run verify/Godot outside the sandbox when
  Godot needs normal user-data access.
- For agent diagnostics, prefer the `_console.exe` binary plus
  `WORLD5_GODOT_BIN` so crashes and GUT output stay in the terminal:

  ```powershell
  $env:WORLD5_GODOT_BIN='C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64_console.exe'
  python -m world5.verify --fast
  ```

## Project Mount Layout

Disk layout:

```text
D:/assets/world 5/engine/
D:/assets/world 5/demo/
D:/assets/world 5/demo/addons/world5/ -> ../../engine/
```

Runtime `res://` paths are resolved from the demo project:

| Runtime path | Disk target |
|---|---|
| `res://addons/world5/tests/...` | `engine/tests/...` |
| `res://addons/world5/shaders/terrain_clipmap.gdshader` | `engine/shaders/terrain_clipmap.gdshader` |
| `res://addons/world5/worlds/walking_demo/` | `engine/worlds/walking_demo/` |

This is why world-bundle paths should generally use
`res://addons/world5/...` at runtime.

## Background Runs

For long calibration or full verification runs, use a background process and
poll its output file rather than launching the editor or blocking the
conversation. Long cinematic-tier tests can appear idle while still running.

## Texture / Pipeline Commands Seen In This Session

Promote texture candidates into the walking-demo bundle:

```powershell
python -m world5.textures.promote --world engine/worlds/walking_demo `
  --candidates-root D:/tmp/w5_candidates/candidates `
  --biome forest --slot ground --base dirt_mossy_base --siblings ...
```

Author and promote macro terrain albedo:

```powershell
python -m world5.textures.tx_macro_terrain --purpose-candidates --promote-purpose
```

Run texture diversity generation:

```powershell
python -m world5.textures.diversity --biome alpine
```

Run one pytest file:

```powershell
python -m pytest tests/unit/test_kernel_composer.py -v
```
