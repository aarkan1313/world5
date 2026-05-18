## Tests for KernelComposer.gd — chain orchestrator.
##
## Per spec 19 §"KernelComposer". GDScript mirror of
## pipeline/world5/kernels/composer.py.

extends GutTest


# --- parse ---

func test_empty_dict_yields_empty_chain() -> void:
	var c: KernelComposer = KernelComposer.from_dict({})
	assert_eq(c.stages.size(), 0)


func test_bare_single_stage_wraps_as_chain_of_one() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "noise_stack",
		"params": {"octaves": 4},
	})
	assert_eq(c.stages.size(), 1)
	assert_eq(c.stages[0]["kind"], "noise_stack")
	assert_eq((c.stages[0]["config"] as NoiseStackKernel).octaves, 4)


func test_chain_with_noise_plus_erosion() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {"octaves": 6}},
			{"type": "erosion", "params": {"iterations": 100}},
		],
	})
	assert_eq(c.stages.size(), 2)
	assert_eq(c.stages[0]["kind"], "noise_stack")
	assert_eq(c.stages[1]["kind"], "erosion")
	assert_eq((c.stages[1]["config"] as ErosionKernel).iterations, 100)


func test_unknown_stage_type_dropped() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "made_up_kernel", "params": {}},
		],
	})
	# unknown stage dropped silently from `stages` (validate flags missing
	# if needed)
	assert_eq(c.stages.size(), 1)


# --- validate ---

func test_validate_empty_chain_rejected() -> void:
	var c: KernelComposer = KernelComposer.new()
	assert_gt(c.validate().size(), 0)


func test_validate_chain_starting_with_erosion_rejected() -> void:
	# Synthetic: build a chain directly to bypass parse-time defaulting.
	var c: KernelComposer = KernelComposer.new()
	c.stages.append({"kind": "erosion", "config": ErosionKernel.new()})
	var errors: Array = c.validate()
	assert_gt(errors.size(), 0,
		"first stage must be a base generator, not erosion")


func test_validate_chained_noise_after_first_rejected() -> void:
	var c: KernelComposer = KernelComposer.new()
	c.stages.append({"kind": "noise_stack", "config": NoiseStackKernel.new()})
	c.stages.append({"kind": "noise_stack", "config": NoiseStackKernel.new()})
	assert_gt(c.validate().size(), 0)


func test_validate_passes_for_noise_plus_erosion() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {}},
		],
	})
	assert_eq(c.validate().size(), 0)


func test_validate_surfaces_per_stage_errors() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {"iterations": -5}},
		],
	})
	# Erosion config rejects negative iterations; composer should
	# surface that.
	assert_gt(c.validate().size(), 0)


# --- chain_hash ---

func test_chain_hash_deterministic() -> void:
	var a: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {"octaves": 4}},
			{"type": "erosion", "params": {"iterations": 50}},
		],
	})
	var b: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {"octaves": 4}},
			{"type": "erosion", "params": {"iterations": 50}},
		],
	})
	assert_eq(a.chain_hash(), b.chain_hash())


func test_chain_hash_differs_on_stage_order() -> void:
	# (Constructed manually since parse-side ordering is preserved.)
	var a: KernelComposer = KernelComposer.new()
	a.stages.append({"kind": "noise_stack", "config": NoiseStackKernel.new()})
	a.stages.append({"kind": "erosion", "config": ErosionKernel.new()})
	# b: erosion first (invalid, but hash should still differ from a)
	var b: KernelComposer = KernelComposer.new()
	b.stages.append({"kind": "erosion", "config": ErosionKernel.new()})
	b.stages.append({"kind": "noise_stack", "config": NoiseStackKernel.new()})
	assert_ne(a.chain_hash(), b.chain_hash())


func test_chain_hash_differs_on_erosion_param() -> void:
	var a: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {"iterations": 50}},
		],
	})
	var b: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {"iterations": 100}},
		],
	})
	assert_ne(a.chain_hash(), b.chain_hash())


# --- accessors ---

func test_has_erosion_true_for_eroded_chain() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {}},
		],
	})
	assert_true(c.has_erosion())


func test_has_erosion_false_for_pure_noise() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "noise_stack", "params": {},
	})
	assert_false(c.has_erosion())


func test_base_noise_kernel_returns_first_noise_stage() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {"amplitude": 75.0}},
			{"type": "erosion", "params": {}},
		],
	})
	var k: NoiseStackKernel = c.base_noise_kernel()
	assert_not_null(k)
	assert_almost_eq(k.amplitude, 75.0, 1e-9)


func test_erosion_stages_returns_each_erosion_stage() -> void:
	var c: KernelComposer = KernelComposer.from_dict({
		"type": "chain",
		"stages": [
			{"type": "noise_stack", "params": {}},
			{"type": "erosion", "params": {"iterations": 30}},
		],
	})
	var es: Array = c.erosion_stages()
	assert_eq(es.size(), 1)
	assert_eq((es[0] as ErosionKernel).iterations, 30)
