"""__NAME__ entry point (REQ-390: SPECFLOW_SMOKE exits 0 with no side effects)."""

from __future__ import annotations

import os


def main() -> int:
    if os.environ.get("SPECFLOW_SMOKE") == "1":
        return 0
    name = "__NAME__"
    print(f"Hello from {name}!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
