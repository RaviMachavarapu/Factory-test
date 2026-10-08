# ADR-004: Windows Habit Tracker Architecture & Plain-File Storage

- Status: accepted
- Date: 2026-10-05
- Deciders: maintainer
- Addresses: [REQ-401, REQ-402, REQ-403, REQ-404, REQ-405]

## Context

The habit tracker must operate on Windows as a zero-friction desktop application. The IDEA document constrains the application to a single machine, single user, no external accounts or network services, and specifies that data must reside in a plain, human-readable file that the user could inspect directly. Furthermore, the streak calculation must be exact with respect to midnight local time boundaries.

## Decision

1. **Architecture Separation:**
   - **Domain Kernel (`src/habit_tracker/models.py`):** Pure functional data structures (`Habit`) and the streak invariant calculator with no I/O or UI coupling.
   - **Storage Layer (`src/habit_tracker/storage.py`):** Plain-file JSON serialization with atomic tempfile replacement for crash-resilience.
   - **Service Layer (`src/habit_tracker/service.py`):** Orchestrates habit operations, validation, and storage persistence.
   - **Presentation Layer (`src/habit_tracker/gui.py`):** Native Windows desktop UI using standard Python Tkinter/TTK with clean typography and layout.

2. **Persistence Format:**
   - Formatted JSON stored in `~/.habit_tracker/habits.json` (or customizable path). Each habit contains:
     ```json
     {
       "id": "uuid-or-slug",
       "name": "Walk 30 minutes",
       "created_at": "YYYY-MM-DD",
       "completed_dates": ["2026-10-01", "2026-10-02"]
     }
     ```

3. **Streak Invariant Implementation:**
   - Evaluated against a reference date (defaults to `date.today()`).
   - Counts uninterrupted backwards calendar days (`date - timedelta(days=1)`).

## Consequences

- **Positive:** Works out of the box on Windows with zero binary compilation dependencies, zero external database setup, and instant testability.
- **Traceability:** Fulfills all constraints from `IDEA.md`.
