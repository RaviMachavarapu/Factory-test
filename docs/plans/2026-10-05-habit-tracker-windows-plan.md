---
type: plan
phase: PLAN
spec: 2026-10-05-habit-tracker-windows
decisions: [ADR-004]
created: "2026-10-05"
---

# Habit Tracker (Windows) — Implementation Plan

Implements REQ-401, REQ-402, REQ-403, REQ-404, REQ-405 per ADR-004.

## Files

**Created:**
- `src/habit_tracker/__init__.py` — Package initialization.
- `src/habit_tracker/models.py` — Pure domain model, streak calculation logic (`REQ-403`).
- `src/habit_tracker/storage.py` — Plain JSON atomic file persistence (`REQ-404`).
- `src/habit_tracker/service.py` — Habit business logic and coordinator (`REQ-401`, `REQ-402`).
- `src/habit_tracker/gui.py` — Windows desktop GUI (`REQ-405`).
- `src/habit_tracker/__main__.py` — Entrypoint to launch the Windows desktop application.
- `tests/unit/test_habit_tracker.py` — Complete unit tests covering REQ-401 through REQ-405.

## Task 1: Test-First Discipline (Write Failing Unit Tests)
Write `tests/unit/test_habit_tracker.py` covering:
- Habit creation, whitespace trimming, and duplicate rejection (`REQ-401`).
- Habit deletion (`REQ-401`).
- Toggle completion for today and arbitrary dates (`REQ-402`).
- Exact streak calculation invariants: checked today, unchecked today but checked yesterday, broken streak, multi-day consecutive streaks (`REQ-403`).
- Plain file JSON persistence, round-trip load, and atomic writes (`REQ-404`).

Confirm tests fail prior to writing implementation bodies (`art-test-first`).

## Task 2: Implement Domain Models & Streak Invariant
Implement `src/habit_tracker/models.py`:
- `Habit` dataclass with `name`, `completed_dates: set[str]`.
- `calculate_streak(habit, reference_date)` returning current streak count.

## Task 3: Implement Persistence Layer
Implement `src/habit_tracker/storage.py`:
- `HabitStorage` reading from and writing to a designated JSON file path.
- Atomic file write using temporary file replacement to avoid corrupt files on interruption.

## Task 4: Implement Service Layer
Implement `src/habit_tracker/service.py`:
- `HabitService` managing in-memory state and synchronizing with storage.

## Task 5: Run Tests and Confirm Passing
Run pytest and confirm all tests pass.

## Task 6: Implement Windows Desktop GUI
Implement `src/habit_tracker/gui.py` and `src/habit_tracker/__main__.py`:
- Tkinter/TTK window with modern styling, habit card list, daily checkboxes, dynamic streak updates, and quick habit adder.
