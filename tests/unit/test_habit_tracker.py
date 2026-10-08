# Covers: REQ-401, REQ-402, REQ-403, REQ-404, REQ-405
import json
import os
from datetime import date, timedelta
import pytest

from src.habit_tracker.models import Habit, calculate_streak
from src.habit_tracker.storage import HabitStorage
from src.habit_tracker.service import HabitService


class TestHabitModel:
    def test_habit_initialization_and_streak_zero(self):
        # Covers: REQ-401, REQ-403
        habit = Habit(name="Read 20 pages")
        today = date(2026, 10, 5)
        assert habit.name == "Read 20 pages"
        assert calculate_streak(habit, today) == 0

    def test_streak_checked_today(self):
        # Covers: REQ-402, REQ-403
        today = date(2026, 10, 5)
        habit = Habit(name="Walk 30 minutes")
        habit.completed_dates.add(today.isoformat())
        assert calculate_streak(habit, today) == 1

    def test_streak_consecutive_days_ending_today(self):
        # Covers: REQ-403
        today = date(2026, 10, 5)
        habit = Habit(name="Walk 30 minutes")
        # Completed for 7 consecutive days (today down to 6 days ago)
        for i in range(7):
            d = today - timedelta(days=i)
            habit.completed_dates.add(d.isoformat())
        assert calculate_streak(habit, today) == 7

    def test_streak_preserved_when_checked_yesterday_but_not_yet_today(self):
        # Covers: REQ-403
        today = date(2026, 10, 5)
        yesterday = today - timedelta(days=1)
        habit = Habit(name="Walk 30 minutes")
        # 6-day streak ending yesterday
        for i in range(1, 7):
            d = today - timedelta(days=i)
            habit.completed_dates.add(d.isoformat())
        assert calculate_streak(habit, today) == 6

    def test_streak_broken_when_yesterday_and_today_missed(self):
        # Covers: REQ-403
        today = date(2026, 10, 5)
        habit = Habit(name="Meditate")
        # Completed 2 days ago, but missed yesterday and today
        habit.completed_dates.add((today - timedelta(days=2)).isoformat())
        assert calculate_streak(habit, today) == 0

    def test_streak_decrements_on_uncheck(self):
        # Covers: REQ-402, REQ-403
        today = date(2026, 10, 5)
        habit = Habit(name="Drink water")
        # 3-day streak ending yesterday
        for i in range(1, 4):
            habit.completed_dates.add((today - timedelta(days=i)).isoformat())
        assert calculate_streak(habit, today) == 3

        # Check today: goes to 4
        habit.completed_dates.add(today.isoformat())
        assert calculate_streak(habit, today) == 4

        # Uncheck today: reverts to 3
        habit.completed_dates.remove(today.isoformat())
        assert calculate_streak(habit, today) == 3


class TestHabitStorage:
    def test_save_and_load_plain_json(self, tmp_path):
        # Covers: REQ-404
        file_path = tmp_path / "habits.json"
        storage = HabitStorage(file_path=file_path)

        habits = [
            Habit(name="Exercise", completed_dates={"2026-10-04", "2026-10-05"}),
            Habit(name="Read books", completed_dates={"2026-10-05"}),
        ]
        storage.save(habits)

        # Verify the file is human-readable valid JSON
        assert file_path.exists()
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        assert len(data) == 2
        assert data[0]["name"] == "Exercise"

        # Load back and verify equality
        loaded = storage.load()
        assert len(loaded) == 2
        assert loaded[0].name == "Exercise"
        assert loaded[0].completed_dates == {"2026-10-04", "2026-10-05"}
        assert loaded[1].name == "Read books"

    def test_load_nonexistent_file_returns_empty_list(self, tmp_path):
        # Covers: REQ-404
        file_path = tmp_path / "nonexistent.json"
        storage = HabitStorage(file_path=file_path)
        assert storage.load() == []


class TestHabitService:
    def test_add_and_delete_habit(self, tmp_path):
        # Covers: REQ-401
        file_path = tmp_path / "habits.json"
        service = HabitService(storage=HabitStorage(file_path))

        h1 = service.add_habit("Morning Stretch")
        assert h1.name == "Morning Stretch"
        assert len(service.get_habits()) == 1

        service.delete_habit(h1.id)
        assert len(service.get_habits()) == 0

    def test_duplicate_or_empty_habit_rejected(self, tmp_path):
        # Covers: REQ-401
        file_path = tmp_path / "habits.json"
        service = HabitService(storage=HabitStorage(file_path))

        service.add_habit("Journaling")
        with pytest.raises(ValueError, match="already exists"):
            service.add_habit("Journaling")

        with pytest.raises(ValueError, match="cannot be empty"):
            service.add_habit("   ")

    def test_toggle_habit_completion(self, tmp_path):
        # Covers: REQ-402, REQ-403
        file_path = tmp_path / "habits.json"
        service = HabitService(storage=HabitStorage(file_path))
        today = date(2026, 10, 5)

        h = service.add_habit("Walk Dog")
        assert not service.is_completed_on(h.id, today)
        assert service.get_streak(h.id, today) == 0

        # Toggle on
        is_completed = service.toggle_completion(h.id, today)
        assert is_completed is True
        assert service.is_completed_on(h.id, today)
        assert service.get_streak(h.id, today) == 1

        # Toggle off
        is_completed = service.toggle_completion(h.id, today)
        assert is_completed is False
        assert not service.is_completed_on(h.id, today)
        assert service.get_streak(h.id, today) == 0
