from pathlib import Path
import json
import os
import tempfile
from typing import List

from src.habit_tracker.models import Habit


class HabitStorage:
    """Manages plain JSON file persistence with atomic saves."""

    def __init__(self, file_path: Path | str | None = None):
        if file_path is None:
            home = Path.home()
            app_dir = home / ".habit_tracker"
            app_dir.mkdir(parents=True, exist_ok=True)
            self.file_path = app_dir / "habits.json"
        else:
            self.file_path = Path(file_path)

    def load(self) -> List[Habit]:
        """Load habits from plain JSON file."""
        if not self.file_path.exists():
            return []

        try:
            with open(self.file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            return []

        habits: List[Habit] = []
        for item in data:
            habit = Habit(
                id=item.get("id", ""),
                name=item.get("name", ""),
                created_at=item.get("created_at", ""),
                completed_dates=set(item.get("completed_dates", [])),
            )
            habits.append(habit)
        return habits

    def save(self, habits: List[Habit]) -> None:
        """Atomically save habits to plain JSON file."""
        self.file_path.parent.mkdir(parents=True, exist_ok=True)

        payload = [
            {
                "id": h.id,
                "name": h.name,
                "created_at": h.created_at,
                "completed_dates": sorted(list(h.completed_dates)),
            }
            for h in habits
        ]

        dir_path = self.file_path.parent
        # Write to temporary file in same directory first to ensure atomic replace on Windows
        with tempfile.NamedTemporaryFile("w", dir=dir_path, delete=False, encoding="utf-8") as tf:
            json.dump(payload, tf, indent=2, ensure_ascii=False)
            temp_name = tf.name

        os.replace(temp_name, self.file_path)
