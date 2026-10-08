---
type: spec
phase: SPEC
status: accepted
created: "2026-10-05"
approved_by: "solo-maintainer"
---

# Habit Tracker: Windows Desktop Application

## Overview

A native Windows desktop application for tracking daily habits and streaks. Data is stored in a clean, human-readable plain JSON file on the local machine with no accounts or telemetry required.

## Problem Statement

Users who want simple habit tracking are burdened by complex apps requiring cloud accounts, subscriptions, intrusive notifications, or heavy cross-platform overhead. A single user on a Windows PC needs a fast, lightweight, resilient desktop app to quickly add daily habits, check them off, and observe accurate streak progression.

## User Personas

### Persona: Focused Daily Tracker
- **Role:** Individual working on Windows who wants a frictionless habit check-off.
- **Goal:** Open app, toggle completed habits in under 5 seconds, see current streak, and close or minimize.
- **Success looks like:** Checking off a habit increments streak immediately. Launching tomorrow shows unchecked boxes while preserving earned streaks until missed.

## Objectives

1. Fast startup (< 1 second) and zero network dependencies.
2. Complete data ownership via human-readable local plain JSON file.
3. Formally precise streak calculation respecting local calendar days and midnight boundaries.
4. Seamless execution on Windows 10/11 with zero external runtime installations.

## Functional Requirements

### Must Have

- **REQ-401:** Habit creation and deletion.
  - Adding a habit requires a non-empty name (trimmed, 1–100 characters). Duplicate habit names are rejected.
  - An existing habit can be deleted, removing its definition and history.
- **REQ-402:** Daily check-off toggle.
  - Each habit can be marked as completed or incomplete for any target calendar date (`YYYY-MM-DD`, defaulting to today local time).
  - Toggling completion status immediately updates the underlying date set.
- **REQ-403:** Streak calculation invariant. [verifiable-model]
  - **Definition:** The streak is the number of consecutive calendar days ending either today (if checked today) or yesterday (if today is not yet checked, streak is preserved).
  - **Invariant 1:** If checked today, `streak(today) = 1 + consecutive_days_prior(today)`.
  - **Invariant 2:** If not checked today and checked yesterday, `streak(today) = consecutive_days_prior(today)`.
  - **Invariant 3:** If neither checked today nor checked yesterday, `streak(today) = 0`.
  - **Invariant 4:** Unchecking today decrements the streak to the yesterday streak value without losing historical records.
- **REQ-404:** Local plain-file persistence.
  - Habits and their completion date history are saved to a plain, human-readable JSON file.
  - File saving uses atomic write semantics to prevent data corruption.
  - If the file does not exist, an empty habit list is initialized without error.
- **REQ-405:** Windows Desktop GUI.
  - Provides a clean Windows desktop window displaying the current local date, an "Add Habit" input form, a scrollable list of habit cards with checkboxes, streak counters (e.g. `🔥 7 days`), and delete buttons.

### Won't Have

- Remote user accounts, telemetry, or server syncing.
- Push notifications, alarms, or background daemons.
- Charts or complex analytics beyond the streak counter.
- Task deadlines or one-off to-do items.

## Non-Functional Requirements

- Runs natively on Windows (Python 3.10+ / Tkinter / TTK).
- Self-contained, free to build and run.
