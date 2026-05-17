# Pitfalls: Meta + Tier 0

> Bugs in build / test / packaging / docs / lint / Tier 0 primitives.
> See `pitfalls_INDEX.md` for the symptom-lookup table.

## #1 — Static methods named `get`/`load`/`set`/`free`/etc. shadow Godot builtins

**Symptom**: GDScript parser fails with `Cannot call non-static
function "get()" from the static function ...` or `Too few arguments
for "load()" call. Expected at least 1 but received 0.` when calling
a class-level static method.

**Cause**: GDScript's base `Object` class has builtin methods named
`get(property)`, `set(property, value)`, `load(path)` (Resource
loader), `free()`, `call(method, args)`, and several others. A
`class_name` extending Node (or any Object) inherits these as
instance methods. A `static func get(...)` in your class shadows
the inherited instance `get()` and the parser flags the conflict.

The compiler doesn't error at definition — it errors at the CALL
site, on every test that uses the static method.

**Fix**: rename the static method to avoid collision:
- `get(x)` → `get_tier(x)` / `get_item(x)` / `get_entry(x)`
- `load(path)` → `load_config(path)` / `load_file(path)`
- `set(k, v)` → `set_entry(k, v)`
- `call(name, args)` → `invoke(name, args)`

The Python mirror of the same class is unaffected (Python has no
such builtin shadowing). Cross-impl tests should call the
language-appropriate name.

**What didn't work**: Trying to call `MyClass.get(x)` from gut test
code — parser fails. Trying to call it from within the class's own
methods — parser fails. Renaming the test's local variable — no
effect; the static method itself is what's broken.

**Diagnostic**: gut output shows tests as "Risky: Did not assert"
(zero asserts ran) because every `before_each` / test method crashes
on parse. Look at the raw godot stderr for "SCRIPT ERROR: Parse
Error: Too few arguments for ..." messages.

**Related**: spec 13 QUALITY_TIERS (first hit; renamed `load` →
`load_config`, `get` → `get_tier`). Every cross-impl static class
in Tier 0 + later should check for builtin collisions.

**First hit**: 2026-05-16 (Phase 2.3, QualityTiers).
