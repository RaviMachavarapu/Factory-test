"""Smoke test for __NAME__ (REQ-304): both branches of main()."""

from src.__PKG__.__main__ import main


def test_main_smoke_mode(monkeypatch):
    monkeypatch.setenv("SPECFLOW_SMOKE", "1")
    assert main() == 0


def test_main_greeting_mode(monkeypatch, capsys):
    monkeypatch.delenv("SPECFLOW_SMOKE", raising=False)
    assert main() == 0
    out = capsys.readouterr().out
    assert "__NAME__" in out
