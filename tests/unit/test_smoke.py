"""Smoke test — verifies pytest harness works.

Per Phase 2.1: minimal assertion that pytest collects + runs from
repo root. First real test alongside Phase 2.2 systems.
"""


def test_truthy():
    assert True


def test_arithmetic():
    assert 1 + 1 == 2


def test_world5_importable():
    """Verify the world5 package imports + version is set."""
    import world5

    assert hasattr(world5, "__version__")
    assert world5.__version__ == "0.0.1"


def test_verify_module_importable():
    """Verify the verify submodule imports."""
    from world5.verify import VerifyMode, run_verify

    assert VerifyMode.DEFAULT == VerifyMode("default")
    assert callable(run_verify)
