"""
Shared pytest fixtures for the Moodle Docker AWS Challenge test suite.

This ``conftest`` module centralises common paths and helpers so that test
modules under the ``tests/`` directory can obtain them through dependency
injection instead of recomputing them inline.

The ``repo_root`` fixture resolves the repository root (the parent of the
``tests/`` directory where this file lives). It is intended for future
tests that need a stable reference to the workspace root.

NOTE: Existing tests keep using ``pathlib.Path(__file__).parent.parent``
directly and continue to work unchanged — this fixture is purely additive.
"""

from pathlib import Path

import pytest


@pytest.fixture
def repo_root() -> Path:
    """Return the repository root directory as a :class:`pathlib.Path`.

    The repository root is the parent of the ``tests/`` directory that
    contains this ``conftest.py``. Tests can request this fixture to
    locate project artefacts (e.g. ``docker/``, ``terraform/``, ``docs/``)
    without hard-coding absolute paths.
    """
    return Path(__file__).parent.parent


# ---------------------------------------------------------------------------
# Perfil do Hypothesis sem limite de tempo por exemplo (deadline).
# No Windows, a primeira chamada a `git check-ignore` em
# test_gitignore_patterns.py pode levar mais de 200 ms (inicialização do Git e
# varredura do antivírus sobre o arquivo temporário), o que gera
# DeadlineExceeded/FlakyFailure mesmo quando o arquivo É ignorado.
# Desativar o deadline não altera o que os testes verificam, apenas remove o
# limite de tempo. Os demais parâmetros de cada teste (ex.: max_examples)
# continuam definidos nos próprios @settings.
# ---------------------------------------------------------------------------
from hypothesis import settings as _hypothesis_settings

_hypothesis_settings.register_profile("sem-deadline", deadline=None)
_hypothesis_settings.load_profile("sem-deadline")
