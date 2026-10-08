---
spec: 2026-09-28-greet
kernel_modules:
  - path: src/greet/__init__.py
    req_map: [REQ-991]
external_dependencies: []
components: [greet]
---

# Greet — Architecture Overview

A single pure function; the kernel boundary is the function itself.
