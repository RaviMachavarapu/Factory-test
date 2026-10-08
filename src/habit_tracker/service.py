from datetime import date
from typing import List, Optional

from src.habit_tracker.models import Habit, calculate_streak
from src.habit_tracker.storage import HabitStorage


class HabitService:
    """Service layer managing habit operations and synchronizing storage."""

    def __init__(self, storage: Optional[HabitStorage] = None):
        self.storage = storage if storage is not None else HabitStorage()
        self._habits: List[Habit] = self.storage.load()

    def get_habits(self) -> List[Habit]:
        """Return copy of habit list."""
        return list(self._habits)

    def add_habit(self, name: str) -> Habit:
        """Add a new habit with trimmed name. Rejects duplicates and empty strings."""
        trimmed = name.strip()
        if not trimmed:
            raise ValueError("Habit name cannot be empty.")
        if len(trimmed) > 100:
            raise ValueError("Habit name cannot exceed 100 characters.")

        if any(h.name.lower() == trimmed.lower() for h in self._habits):
            raise ValueError(f"Habit '{trimmed}' already exists.")

        habit = Habit(name=trimmed)
        self._habits.append(habit)
        self.storage.save(self._habits)
        return habit

    def delete_habit(self, habit_id: str) -> bool:
        """Remove habit by ID."""
        orig_count = len(self._habits)
        self._habits = [h for h in self._habits if h.id != habit_id]
        if len(self._habits) != orig_count:
            self.storage.save(self._habits)
            return True
        return False

    def toggle_completion(self, habit_id: str, target_date: date | None = None) -> bool:
        """Toggle habit completion on target_date (defaults to today)."""
        if target_date is None:
            target_date = date.today()

        habit = next((h for h in self._habits if h.id == habit_id), None)
        if habit is None:
            raise ValueError(f"Habit with ID '{habit_id}' not found.")

        result = habit.toggle_completed(target_date)
        self.storage.save(self._habits)
        return result

    def is_completed_on(self, habit_id: str, target_date: date | None = None) -> bool:
        """Check if habit was completed on target_date."""
        if target_date is None:
            target_date = date.today()
        habit = next((h for h in self._habits if h.id == habit_id), None)
        if habit is None:
            return False
        return habit.is_completed(target_date)

    def get_streak(self, habit_id: str, reference_date: date | None = None) -> int:
        """Calculate current streak for habit."""
        habit = next((h for h in self._habits if h.id == habit_id), None)
        if habit is None:
            return 0
        return calculate_streak(habit, reference_date)
