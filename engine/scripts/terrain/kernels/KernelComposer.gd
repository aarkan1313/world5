## KernelComposer — chain orchestrator (GDScript mirror of
## pipeline/world5/kernels/composer.py).
##
## Per spec 19 §"KernelComposer" + spec 22 §"Catalog schema". A biome's
## `kernel` field is either a single-stage spec or a chain spec (type
## == "chain" + ordered `stages`). The composer reads this and
## produces a runnable pipeline.
##
## Two responsibilities:
## 1. Parse: dict-of-stages → typed Array[{kind, config}] where config
##    is the matching kernel class (NoiseStackKernel, ErosionKernel).
## 2. Hash: combine each stage's config_hash into a single chain hash
##    used as part of the cache key. Same chain → same hash → same
##    cached result (spec 12 content addressing).
##
## Execution is owned by GpuTerrainBackend, not the composer — the
## composer is config + parsing + hashing only (mirrors the rest of
## the kernel system: config classes don't execute, executors live in
## the backend / Python ref).

class_name KernelComposer extends RefCounted


const STAGE_NOISE_STACK := "noise_stack"
const STAGE_EROSION := "erosion"
const STAGE_DEM_FEATURE := "dem_feature"

const VALID_STAGE_TYPES := [STAGE_NOISE_STACK, STAGE_EROSION, STAGE_DEM_FEATURE]


## Parsed chain — array of Dictionary{kind: String, config: RefCounted}.
## First entry is the base generator; subsequent entries are post-
## processes. Empty if the source dict was unparseable.
var stages: Array = []


## Parse a chain spec into typed stages. Accepts either:
## - {"type": "chain", "stages": [{type, params}, ...]}
## - {"type": "noise_stack", "params": {...}}  (bare single stage)
## Returns the composer with `stages` populated (empty on parse error;
## see validate() for error strings).
static func from_dict(d: Dictionary) -> KernelComposer:
	var c := KernelComposer.new()
	if d.is_empty():
		return c
	var raw_stages: Array = []
	var t: String = String(d.get("type", ""))
	if t == "chain":
		var s_in: Array = d.get("stages", []) as Array
		for e in s_in:
			if e is Dictionary:
				raw_stages.append(e)
	elif t != "":
		# Bare single-stage spec; wrap as chain-of-one.
		raw_stages.append(d)
	for s in raw_stages:
		var stage_t: String = String(s.get("type", ""))
		var params: Dictionary = s.get("params", {}) as Dictionary
		var cfg: RefCounted = _build_config(stage_t, params)
		if cfg != null:
			c.stages.append({"kind": stage_t, "config": cfg})
	return c


static func _build_config(stage_type: String, params: Dictionary) -> RefCounted:
	match stage_type:
		STAGE_NOISE_STACK:
			return NoiseStackKernel.from_dict(params)
		STAGE_EROSION:
			return ErosionKernel.from_dict(params)
		STAGE_DEM_FEATURE:
			return DemFeatureKernel.from_dict(params)
		_:
			return null  # unknown stage type; caller surfaces via validate()


## Returns an Array of error strings; empty Array means a valid chain.
func validate() -> Array:
	var errors: Array = []
	if stages.is_empty():
		errors.append("chain has no parseable stages")
		return errors
	# First stage must be a base generator.
	var first_kind: String = String(stages[0].get("kind", ""))
	if first_kind != STAGE_NOISE_STACK:
		errors.append("first stage must be a base generator (got '%s')" % first_kind)
	# Subsequent stages should be post-processes (erosion). Multiple
	# generators in a chain is undefined; flag.
	for i in range(1, stages.size()):
		var k: String = String(stages[i].get("kind", ""))
		if k == STAGE_NOISE_STACK:
			errors.append("stage %d: chained generator '%s' undefined; expected post-process" % [i, k])
		if not VALID_STAGE_TYPES.has(k):
			errors.append("stage %d: unknown type '%s'" % [i, k])
	# Each stage's config validates itself.
	for i in range(stages.size()):
		var cfg = stages[i].get("config")
		if cfg == null or not cfg.has_method("validate"):
			errors.append("stage %d: config missing or non-validateable" % i)
			continue
		var per: Array = cfg.validate()
		for e in per:
			errors.append("stage %d (%s): %s" % [i, stages[i].get("kind", ""), e])
	return errors


## Content-addressed hash of the WHOLE chain. Same chain spec → same
## hash. Different stage params, ordering, or type → different hash.
## Used in TerrainPageRequest.cache_key so chain edits invalidate
## downstream bakes.
func chain_hash() -> String:
	var parts: Array = []
	for s in stages:
		parts.append({
			"kind": s.get("kind", ""),
			"hash": s.get("config").config_hash() if s.get("config") != null else "",
		})
	return ContentAddress.compute_stamp({"chain": parts})


## True if this chain has at least one erosion stage (used by the
## backend to decide whether to allocate the water/sediment/velocity
## work buffers).
func has_erosion() -> bool:
	for s in stages:
		if String(s.get("kind", "")) == STAGE_EROSION:
			return true
	return false


## True if this chain has at least one dem_feature stage (used by the
## backend to decide whether to require a DemSource for the bundle).
func has_dem_feature() -> bool:
	for s in stages:
		if String(s.get("kind", "")) == STAGE_DEM_FEATURE:
			return true
	return false


## Returns Array of DemFeatureKernel configs in chain order. Used by
## the backend to dispatch dem_feature stages with their per-stage
## strength/mode params, and by TerrainWorld to look up which DEM
## source IDs the bundle must provide.
func dem_feature_stages() -> Array:
	var out: Array = []
	for s in stages:
		if String(s.get("kind", "")) == STAGE_DEM_FEATURE:
			out.append(s.get("config") as DemFeatureKernel)
	return out


## Convenience accessors for the backend.
func base_noise_kernel() -> NoiseStackKernel:
	for s in stages:
		if String(s.get("kind", "")) == STAGE_NOISE_STACK:
			return s.get("config") as NoiseStackKernel
	return null


func erosion_stages() -> Array:
	var out: Array = []
	for s in stages:
		if String(s.get("kind", "")) == STAGE_EROSION:
			out.append(s.get("config") as ErosionKernel)
	return out
