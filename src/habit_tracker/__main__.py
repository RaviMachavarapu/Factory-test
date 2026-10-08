"""Application entrypoint for Windows Habit Tracker."""
import sys
from src.habit_tracker.gui import launch_gui


def main():
    launch_gui()


if __name__ == "__main__":
    main()
