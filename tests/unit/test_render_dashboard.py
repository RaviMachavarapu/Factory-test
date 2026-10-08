# Covers: REQ-370
"""Tests for render_dashboard.py."""

import json

import pytest


@pytest.fixture
def dashboard_project(tmp_path):
    """Create a minimal project structure for dashboard testing."""
    specs = tmp_path / "docs" / "specs"
    specs.mkdir(parents=True)
    (specs / "design.md").write_text(
        "---\ntype: spec\nphase: SPEC\nstatus: approved\n---\n"
        "# Design Spec\n\n"
        "### REQ-001: User can log in\n"
        "Users must be able to authenticate.\n\n"
        "### REQ-002: User can view dashboard\n"
        "Authenticated users see their dashboard.\n"
    )

    plans = tmp_path / "docs" / "plans"
    plans.mkdir(parents=True)
    (plans / "plan-1.md").write_text(
        "---\ntype: plan\nphase: PLAN\nstatus: approved\n---\n"
        "# Plan 1: Auth\n\n"
        "### TASK-001: Implement login endpoint\n"
        "Implements: REQ-001\n\n"
        "### TASK-002: Build dashboard page\n"
        "Implements: REQ-002\n"
    )

    src = tmp_path / "src"
    src.mkdir()
    (src / "auth.py").write_text("# Task: TASK-001\ndef login(): pass\n")
    (src / "dashboard.py").write_text("# Task: TASK-002\ndef render(): pass\n")

    tests = tmp_path / "tests"
    tests.mkdir()
    (tests / "test_auth.py").write_text("# Covers: TASK-001\ndef test_login(): pass\n")

    (tmp_path / "docs" / "dashboard").mkdir(parents=True)
    return tmp_path


def test_parse_ids_from_spec(dashboard_project):
    """Should extract REQ-NNN IDs from spec files."""
    from scripts.render_dashboard import parse_requirement_ids

    ids = parse_requirement_ids(dashboard_project / "docs" / "specs" / "design.md")
    assert "REQ-001" in ids
    assert "REQ-002" in ids


def test_parse_task_implements(dashboard_project):
    """Should extract Implements: references from plan files."""
    from scripts.render_dashboard import parse_task_references

    refs = parse_task_references(dashboard_project / "docs" / "plans" / "plan-1.md")
    assert refs["TASK-001"] == ["REQ-001"]
    assert refs["TASK-002"] == ["REQ-002"]


def test_parse_source_task_refs(dashboard_project):
    """Should extract Task: references from source files."""
    from scripts.render_dashboard import parse_source_references

    refs = parse_source_references(dashboard_project / "src")
    assert any("auth.py" in k for k in refs)


def test_build_traceability_matrix(dashboard_project):
    """Should build a complete traceability matrix."""
    from scripts.render_dashboard import build_traceability

    matrix = build_traceability(dashboard_project)
    assert "REQ-001" in matrix
    assert "TASK-001" in matrix["REQ-001"]["tasks"]


def test_parse_dafny_proves(dashboard_project):
    """Should extract Proves: REQ-NNN from .dfy files."""
    verif = dashboard_project / "verification"
    verif.mkdir()
    (verif / "auth.dfy").write_text(
        "// verification/auth.dfy\n"
        "// Proves: REQ-001\n"
        "predicate ValidToken(token: string) { |token| >= 32 }\n"
    )
    from scripts.render_dashboard import parse_verification_status

    status = parse_verification_status(dashboard_project / "verification")
    assert "REQ-001" in status
    assert status["REQ-001"]["file"] == "auth.dfy"


def test_traceability_includes_verification(dashboard_project):
    """Traceability matrix should include verification status."""
    verif = dashboard_project / "verification"
    verif.mkdir()
    (verif / "auth.dfy").write_text(
        "// verification/auth.dfy\n"
        "// Proves: REQ-001\n"
        "predicate ValidToken(token: string) { |token| >= 32 }\n"
    )
    from scripts.render_dashboard import build_traceability

    matrix = build_traceability(dashboard_project)
    assert "REQ-001" in matrix
    assert matrix["REQ-001"]["verification"] is not None
    assert matrix["REQ-001"]["verification"]["file"] == "auth.dfy"
    assert matrix["REQ-002"]["verification"] is None


def test_pipeline_state_reads_next_json(dashboard_project, monkeypatch):
    """REQ-370 (P6 R13): the dashboard shows /next --json's derived state, never a hard-coded phase list."""
    from scripts import render_dashboard as rd

    payload = {
        "state": {"lane": "build", "phase": "awaiting-verifier"},
        "step": {"kind": "RunVerifier", "pr": 7},
        "next_step": "In a second terminal ...",
        "open_lane_prs": [{"number": 7, "head": "build/x-1"}],
    }
    calls = []

    class Done:
        returncode, stdout, stderr = 0, json.dumps(payload), ""

    def fake_run(argv, **kwargs):
        calls.append(argv)
        assert kwargs.get("timeout"), "next.sh runs under a timeout"
        return Done()

    monkeypatch.setattr(rd.subprocess, "run", fake_run)
    state = rd.pipeline_state(dashboard_project)
    assert calls and calls[0][:3] == ["bash", "scripts/next.sh", "--json"]
    assert (state["lane"], state["phase"], state["open_lanes"]) == (
        "build",
        "awaiting-verifier",
        [7],
    )
    html = rd.generate_html(
        rd.build_traceability(dashboard_project), state, dashboard_project / "out"
    ).read_text()
    assert "awaiting-verifier" in html and "phase/spec" not in html


def test_pipeline_state_when_next_fails(dashboard_project, monkeypatch):
    """REQ-370: when next.sh cannot run, the dashboard says so instead of inventing phases."""
    from scripts import render_dashboard as rd

    class Failed:
        returncode, stdout, stderr = 2, "", "ERROR next: not a git repository"

    monkeypatch.setattr(rd.subprocess, "run", lambda argv, **kwargs: Failed())
    state = rd.pipeline_state(dashboard_project)
    assert state["phase"] == "unknown" and "not a git repository" in state["note"]


def test_pipeline_state_has_a_timeout(dashboard_project, monkeypatch):
    """REQ-370 (Build 5 fix wave 1, E): next.sh runs under a timeout; a timeout renders 'state unavailable (timed out)'."""
    import subprocess as sp

    from scripts import render_dashboard as rd

    seen = {}

    def slow(argv, **kwargs):
        seen.update(kwargs)
        raise sp.TimeoutExpired(argv, kwargs.get("timeout"))

    monkeypatch.setattr(rd.subprocess, "run", slow)
    state = rd.pipeline_state(dashboard_project)
    assert seen.get("timeout") and seen["timeout"] > 0
    assert (
        state["phase"] == "unknown" and state["note"] == "state unavailable (timed out)"
    )
    html = rd.generate_html({}, state, dashboard_project / "out").read_text()
    assert "state unavailable (timed out)" in html


def test_pipeline_state_shows_notes_and_marks_a_pr_blind_derivation(
    dashboard_project, monkeypatch
):
    """REQ-370 (Build 5 fix wave 1, E): next.sh's notes are shown, and a derivation made without PR state is marked."""
    from scripts import render_dashboard as rd

    payload = {
        "state": {"lane": "design", "phase": "open-pr"},
        "next_step": "git push -u origin design/x",
        "open_lane_prs": [],
        "pr_state_known": False,
        "notes": [
            "template source (no .specflow.yml): profile guided",
            "detached <HEAD>",
        ],
    }

    class Done:
        returncode, stdout, stderr = 0, json.dumps(payload), ""

    monkeypatch.setattr(rd.subprocess, "run", lambda argv, **kwargs: Done())
    state = rd.pipeline_state(dashboard_project)
    assert state["notes"] == payload["notes"] and state["pr_state_known"] is False
    html = rd.generate_html({}, state, dashboard_project / "out").read_text()
    assert (
        "template source (no .specflow.yml): profile guided" in html
        and "detached &lt;HEAD&gt;" in html
    )
    assert "derived without PR state" in html


def test_dashboard_diff_keeps_to_the_feature():
    """REQ-370 (Build 5 fix wave 1, E): build_traceability and main keep their compact one-line forms."""
    from pathlib import Path

    src = (
        Path(__file__).resolve().parents[2] / "scripts" / "render_dashboard.py"
    ).read_text()
    assert (
        'matrix[req_id]["tasks"][task_id] = {"plan": str(plan.name), "source_files": [], "test_files": []}'
        in src
    )
    assert (
        'print(f"[dashboard] {covered}/{total_reqs} requirements have implementing tasks")'
        in src
    )
