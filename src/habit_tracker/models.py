from dataclasses import dataclass, field
from datetime import date, timedelta
import uuid


@dataclass
class Habit:
    """Represents a daily habit with tracked completion dates."""
    name: str
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created_at: str = field(default_factory=lambda: date.today().isoformat())
    completed_dates: set[str] = field(default_factory=set)

    def is_completed(self, target_date: date) -> bool:
        """Check if habit was completed on target_date."""
        return target_date.isoformat() in self.completed_dates

    def toggle_completed(self, target_date: date) -> bool:
        """Toggle completion for target_date. Returns True if now completed, False otherwise."""
        iso = target_date.isoformat()
        if iso in self.completed_dates:
            self.completed_dates.remove(iso)
            return False
        else:
            self.completed_dates.add(iso)
            return True


def calculate_streak(habit: Habit, reference_date: date | None = None) -> int:
    """
    Calculate the streak for a habit relative to a reference date.
    
    Invariant (REQ-403):
    1. If checked on reference_date: streak = 1 + consecutive consecutive days prior.
    2. If not checked on reference_date, but checked on reference_date - 1:
       streak is preserved (pending today's checkoff before midnight).
    3. If not checked on reference_date and not checked on reference_date - 1:
       streak is 0.
    """
    if reference_date is None:
        reference_date = date.today()

    today_iso = reference_date.isoformat()
    yesterday = reference_date - timedelta(days=1)
    yesterday_iso = yesterday.isoformat()

    checked_today = today_iso in habit.completed_dates
    checked_yesterday = yesterday_iso in habit.completed_dates

    if not checked_today and not checked_yesterday:
        return 0

    streak = 0
    current_check_day = reference_date if checked_today else yesterday

    while current_check_day.isoformat() in habit.completed_dates:
        streak += 1
        current_check_day -= timedelta(days=1)

    return streak
