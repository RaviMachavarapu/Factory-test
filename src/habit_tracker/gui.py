from datetime import date
import tkinter as tk
from tkinter import ttk, messagebox
from typing import Optional

from src.habit_tracker.service import HabitService


class HabitTrackerApp:
    """Windows Desktop GUI for Habit Tracker."""

    def __init__(self, root: tk.Tk, service: Optional[HabitService] = None):
        self.root = root
        self.service = service if service is not None else HabitService()
        self.today = date.today()

        self.setup_window()
        self.setup_styles()
        self.create_widgets()
        self.refresh_habit_list()

    def setup_window(self):
        self.root.title("Habit Tracker — Windows Desktop")
        self.root.geometry("520x680")
        self.root.minsize(460, 520)
        self.root.configure(bg="#f4f6f8")

    def setup_styles(self):
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        # Card and frame styles
        style.configure("TFrame", background="#f4f6f8")
        style.configure("Card.TFrame", background="#ffffff", relief="flat")
        
        # Labels
        style.configure("Header.TLabel", font=("Segoe UI", 18, "bold"), background="#f4f6f8", foreground="#1a202c")
        style.configure("Subheader.TLabel", font=("Segoe UI", 10), background="#f4f6f8", foreground="#718096")
        style.configure("HabitName.TLabel", font=("Segoe UI", 12, "bold"), background="#ffffff", foreground="#2d3748")
        style.configure("HabitCompleted.TLabel", font=("Segoe UI", 12), background="#ffffff", foreground="#a0aec0")
        style.configure("StreakBadge.TLabel", font=("Segoe UI", 11, "bold"), background="#ffffff", foreground="#dd6b20")

        # Buttons
        style.configure("Add.TButton", font=("Segoe UI", 10, "bold"), background="#3182ce", foreground="#ffffff")
        style.map("Add.TButton", background=[("active", "#2b6cb0")])

        style.configure("Delete.TButton", font=("Segoe UI", 9), background="#ffffff", foreground="#e53e3e")

    def create_widgets(self):
        # Top Header Frame
        header_frame = ttk.Frame(self.root, padding="20 20 20 10")
        header_frame.pack(fill=tk.X)

        title_label = ttk.Label(header_frame, text="Daily Habits", style="Header.TLabel")
        title_label.pack(anchor="w")

        date_str = self.today.strftime("%A, %B %d, %Y")
        date_label = ttk.Label(header_frame, text=f"Today: {date_str}", style="Subheader.TLabel")
        date_label.pack(anchor="w", pady=(2, 10))

        # Input Frame for Adding Habit
        input_frame = ttk.Frame(header_frame)
        input_frame.pack(fill=tk.X, pady=(5, 5))

        self.entry_habit_name = ttk.Entry(input_frame, font=("Segoe UI", 11))
        self.entry_habit_name.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8), ipady=5)
        self.entry_habit_name.bind("<Return>", lambda e: self.on_add_habit())

        add_btn = ttk.Button(input_frame, text="Add Habit", style="Add.TButton", command=self.on_add_habit)
        add_btn.pack(side=tk.RIGHT, ipady=3)

        # Habit List Scrollable Area
        list_container = ttk.Frame(self.root, padding="20 10 20 10")
        list_container.pack(fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(list_container, bg="#f4f6f8", highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(list_container, orient=tk.VERTICAL, command=self.canvas.yview)
        self.scrollable_frame = ttk.Frame(self.canvas)

        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )

        self.canvas_window = self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)

        self.canvas.bind(
            "<Configure>",
            lambda e: self.canvas.itemconfig(self.canvas_window, width=e.width)
        )

        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Status Bar
        self.status_var = tk.StringVar(value="Ready")
        status_bar = ttk.Label(self.root, textvariable=self.status_var, font=("Segoe UI", 9), foreground="#718096", padding="10 5")
        status_bar.pack(side=tk.BOTTOM, fill=tk.X)

    def on_add_habit(self):
        name = self.entry_habit_name.get()
        try:
            self.service.add_habit(name)
            self.entry_habit_name.delete(0, tk.END)
            self.refresh_habit_list()
        except ValueError as err:
            messagebox.showwarning("Invalid Habit", str(err))

    def on_delete_habit(self, habit_id: str, habit_name: str):
        if messagebox.askyesno("Delete Habit", f"Are you sure you want to remove '{habit_name}'?"):
            self.service.delete_habit(habit_id)
            self.refresh_habit_list()

    def on_toggle_habit(self, habit_id: str):
        self.service.toggle_completion(habit_id, self.today)
        self.refresh_habit_list()

    def refresh_habit_list(self):
        # Clear existing items
        for widget in self.scrollable_frame.winfo_children():
            widget.destroy()

        habits = self.service.get_habits()
        if not habits:
            empty_lbl = ttk.Label(
                self.scrollable_frame,
                text="No habits added yet. Type a habit above and click 'Add Habit'!",
                font=("Segoe UI", 10, "italic"),
                foreground="#a0aec0",
                justify=tk.CENTER
            )
            empty_lbl.pack(pady=40)
            self.status_var.set("No habits tracked.")
            return

        completed_today_count = 0
        for habit in habits:
            is_done = self.service.is_completed_on(habit.id, self.today)
            if is_done:
                completed_today_count += 1
            streak = self.service.get_streak(habit.id, self.today)

            card = tk.Frame(self.scrollable_frame, bg="#ffffff", bd=1, relief=tk.SOLID)
            card.pack(fill=tk.X, pady=6, ipady=8, ipadx=10)

            # Left checkbox/button toggle
            check_var = tk.BooleanVar(value=is_done)
            cb = tk.Checkbutton(
                card,
                variable=check_var,
                command=lambda hid=habit.id: self.on_toggle_habit(hid),
                bg="#ffffff",
                activebackground="#ffffff",
                font=("Segoe UI", 14),
                cursor="hand2"
            )
            cb.pack(side=tk.LEFT, padx=(5, 10))

            # Habit Title
            title_font = ("Segoe UI", 11, "bold") if not is_done else ("Segoe UI", 11, "overstrike")
            title_color = "#2d3748" if not is_done else "#a0aec0"
            title_lbl = tk.Label(
                card,
                text=habit.name,
                font=title_font,
                fg=title_color,
                bg="#ffffff",
                anchor="w"
            )
            title_lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)

            # Streak badge
            streak_text = f"🔥 {streak} {'day' if streak == 1 else 'days'}"
            streak_lbl = tk.Label(
                card,
                text=streak_text,
                font=("Segoe UI", 10, "bold"),
                fg="#dd6b20" if streak > 0 else "#a0aec0",
                bg="#ffffff"
            )
            streak_lbl.pack(side=tk.LEFT, padx=12)

            # Delete button
            del_btn = tk.Button(
                card,
                text="✕",
                command=lambda hid=habit.id, hname=habit.name: self.on_delete_habit(hid, hname),
                font=("Segoe UI", 9, "bold"),
                fg="#e53e3e",
                bg="#ffffff",
                activeforeground="#c53030",
                activebackground="#fed7d7",
                bd=0,
                cursor="hand2",
                padx=6
            )
            del_btn.pack(side=tk.RIGHT)

        self.status_var.set(
            f"{completed_today_count}/{len(habits)} completed today | Plain file: {self.service.storage.file_path}"
        )


def launch_gui(service: Optional[HabitService] = None):
    root = tk.Tk()
    app = HabitTrackerApp(root, service=service)
    root.mainloop()
