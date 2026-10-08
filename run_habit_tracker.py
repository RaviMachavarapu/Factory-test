"""Convenience launcher for the Windows Habit Tracker application."""
import sys
from pathlib import Path

# Ensure src is on sys.path
here = Path(__file__).resolve().parent
if str(here) not in sys.path:
    sys.path.insert(0, str(here))

from src.habit_tracker.gui import launch_gui

if __name__ == "__main__":
    launch_gui()
