#!/usr/bin/env python3
"""livediag stage window.

A live checklist of every check in the run: what has finished, what is
running now, and what is still to come.  The runner feeds it over a FIFO:

    set <id> <pending|running|pass|warn|fail|skip>
    progress <done> <total>
    note <text>
    close

It also offers one button, "Stop after this check", which creates the file
passed with --stop-file so the runner can stop cleanly between modules.
"""

import argparse
import os
import sys
import threading

try:
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, GLib
except Exception as exc:  # pragma: no cover - only hit without GTK
    sys.stderr.write(f"livediag-stages: no GTK3 available: {exc}\n")
    sys.exit(2)

GLYPHS = {
    "pending": ("\u25cb", "#9aa0a6", "normal"),
    "running": ("\u25b6", "#3465a4", "bold"),
    "pass": ("\u2714", "#2e7d32", "normal"),
    "warn": ("\u0021", "#e08a00", "bold"),
    "fail": ("\u2718", "#c62828", "bold"),
    "skip": ("\u2013", "#9aa0a6", "normal"),
}


class StageWindow:
    def __init__(self, stages_file, fifo, stop_file, title):
        self.stop_file = stop_file
        self.rows = {}

        self.window = Gtk.Window(title=title)
        self.window.set_default_size(580, 640)
        self.window.set_position(Gtk.WindowPosition.CENTER)
        self.window.connect("destroy", Gtk.main_quit)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        outer.set_border_width(12)
        self.window.add(outer)

        self.heading = Gtk.Label(xalign=0)
        self.heading.set_markup("<b>Starting\u2026</b>")
        outer.pack_start(self.heading, False, False, 0)

        self.bar = Gtk.ProgressBar()
        outer.pack_start(self.bar, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll.add(self.listbox)
        outer.pack_start(scroll, True, True, 0)

        self.note = Gtk.Label(xalign=0)
        self.note.set_line_wrap(True)
        outer.pack_start(self.note, False, False, 0)

        stop = Gtk.Button(label="Stop after this check (click)")
        # Never keyboard-activatable: an accidental or injected Enter must not
        # end the run.
        stop.set_can_focus(False)
        stop.set_can_default(False)
        stop.set_focus_on_click(False)
        stop.connect("clicked", self.on_stop)
        outer.pack_start(stop, False, False, 0)

        with open(stages_file, encoding="utf-8") as handle:
            for line in handle:
                line = line.rstrip("\n")
                if not line:
                    continue
                stage_id, name = line.split("\t", 1)
                self.add_row(stage_id, name)

        self.window.show_all()
        threading.Thread(target=self.read_fifo, args=(fifo,), daemon=True).start()

    # -- model ----------------------------------------------------------
    def add_row(self, stage_id, name):
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        icon = Gtk.Label()
        text = Gtk.Label(xalign=0)
        text.set_text(name)
        box.pack_start(icon, False, False, 0)
        box.pack_start(text, True, True, 0)
        row.add(box)
        self.listbox.add(row)
        self.rows[stage_id] = (icon, text)
        self.set_status(stage_id, "pending")

    def set_status(self, stage_id, status):
        if stage_id not in self.rows:
            return
        glyph, colour, weight = GLYPHS.get(status, GLYPHS["pending"])
        icon, text = self.rows[stage_id]
        icon.set_markup(
            f'<span foreground="{colour}" weight="{weight}">{glyph}</span>'
        )
        text.set_markup(
            f'<span foreground="{colour}" weight="{weight}">'
            f"{GLib.markup_escape_text(text.get_text())}</span>"
        )

    def set_progress(self, done, total):
        fraction = 0.0 if total <= 0 else min(1.0, done / total)
        self.bar.set_fraction(fraction)
        self.heading.set_markup(
            f"<b>{done} of {total} checks</b>"
        )

    def set_note(self, message):
        self.note.set_markup(GLib.markup_escape_text(message))

    def on_stop(self, _button):
        try:
            with open(self.stop_file, "w", encoding="utf-8") as handle:
                handle.write("stop\n")
        except OSError:
            pass
        self.note.set_markup("<i>Stopping after the current check\u2026</i>")

    # -- FIFO reader ----------------------------------------------------
    def read_fifo(self, fifo):
        try:
            with open(fifo, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    line = line.rstrip("\n")
                    if not line:
                        continue
                    parts = line.split(" ", 2)
                    command = parts[0]
                    if command == "set" and len(parts) >= 3:
                        GLib.idle_add(self.set_status, parts[1], parts[2])
                    elif command == "progress" and len(parts) >= 3:
                        try:
                            GLib.idle_add(
                                self.set_progress, int(parts[1]), int(parts[2])
                            )
                        except ValueError:
                            pass
                    elif command == "note" and len(parts) >= 2:
                        text = " ".join(parts[1:])
                        GLib.idle_add(self.set_note, text)
                    elif command == "close":
                        GLib.idle_add(Gtk.main_quit)
        except (OSError, ValueError):
            GLib.idle_add(Gtk.main_quit)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stages", required=True)
    parser.add_argument("--fifo", required=True)
    parser.add_argument("--stop-file", required=True)
    parser.add_argument("--title", default="livediag")
    args = parser.parse_args()

    if not os.path.exists(args.fifo):
        sys.stderr.write("livediag-stages: no FIFO\n")
        return 2

    StageWindow(args.stages, args.fifo, args.stop_file, args.title)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
