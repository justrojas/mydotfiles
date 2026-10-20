#!/usr/bin/env python3
"""Now-playing card for the polybar media module.

Why GTK and not rofi: rofi menus are a static snapshot (no live progress) and
only accept an entry on double-click by default, so the transport buttons felt
dead. This is a small undecorated GTK3 window that polls playerctl twice a
second, has real single-click buttons, and a seekable progress bar.

Behaviour:
  * opens just under the bar at the mouse pointer
  * clicking the bar title again (or Esc, or clicking elsewhere) closes it
  * drag/click the progress bar to seek; scroll on the card for volume

Glyphs use \\u escapes on purpose: literal Nerd Font private-use characters get
stripped somewhere in the dotfiles toolchain.
"""

import hashlib
import os
import signal
import subprocess
import sys
import threading
import urllib.parse
import urllib.request

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

PREFERENCE = "spotify"
POLL_MS = 500
ART_SIZE = 120
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "polybar-media-art")
PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "polybar-media-card.pid")

G_PREV, G_PLAY, G_PAUSE, G_NEXT, G_OPEN = "\uf048", "\uf04b", "\uf04c", "\uf051", "\uf2d2"
SEP = "\x1f"

# Colours mirror config/polybar/config.ini [colors].
CSS = b"""
window { background-color: transparent; }
#card {
    background-color: rgba(30, 27, 46, 0.92);
    border: 2px solid #9d7cd8;
    border-radius: 14px;
    padding: 14px;
}
#card label { color: #c8c0dd; font-family: "JetBrainsMono Nerd Font"; }
#title  { font-size: 13pt; font-weight: bold; }
#artist { font-size: 11pt; }
#album, #time, #player { color: #6e6482; font-size: 9pt; }
#art { border-radius: 8px; }
button {
    background: transparent; border: none; box-shadow: none;
    border-radius: 10px; padding: 6px 14px; min-width: 0;
}
button label { font-size: 15pt; color: #c8c0dd; }
button:hover { background-color: rgba(157, 124, 216, 0.25); }
button:active { background-color: rgba(157, 124, 216, 0.45); }
#toggle label { color: #9d7cd8; font-size: 18pt; }
scale trough { background-color: #3a3450; min-height: 4px; border-radius: 2px; border: none; }
scale highlight { background-color: #9d7cd8; border-radius: 2px; border: none; }
scale slider {
    background-color: #c8c0dd; min-width: 10px; min-height: 10px;
    border-radius: 5px; border: none; box-shadow: none; margin: -4px;
}
"""


def run(*args):
    try:
        return subprocess.run(["playerctl", *args], capture_output=True, text=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def pick_player():
    players = [p for p in run("-l").splitlines() if p]
    if not players:
        return None
    for p in players:
        if p == PREFERENCE or p.startswith(PREFERENCE + "."):
            return p
    for p in players:
        if run("-p", p, "status") == "Playing":
            return p
    return players[0]


def fmt(sec):
    sec = max(0, int(sec))
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def art_path(url):
    """Local file for an mpris:artUrl, downloading http(s) art into a cache."""
    if not url:
        return None
    if url.startswith("file://"):
        path = urllib.parse.unquote(url[7:])
        return path if os.path.isfile(path) else None
    if url.startswith(("http://", "https://")):
        os.makedirs(CACHE, exist_ok=True)
        path = os.path.join(CACHE, hashlib.md5(url.encode()).hexdigest()[:16])
        if not os.path.isfile(path):
            try:
                with urllib.request.urlopen(url, timeout=4) as r, open(path + ".part", "wb") as f:
                    f.write(r.read())
                os.replace(path + ".part", path)
            except Exception:
                return None
        return path
    return None


class Card(Gtk.Window):
    def __init__(self):
        super().__init__(title="Now Playing")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual and screen.is_composited():
            self.set_visual(visual)
            self.set_app_paintable(True)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.player = None
        self.length = 0.0
        self.art_url = None
        self.seeking = False
        self._polling = False

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, name="card")
        self.add(card)

        top = Gtk.Box(spacing=14)
        card.pack_start(top, False, False, 0)

        self.art = Gtk.Image(name="art")
        self.art.set_size_request(ART_SIZE, ART_SIZE)
        top.pack_start(self.art, False, False, 0)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
        top.pack_start(info, True, True, 0)
        self.title = self._label("title", info)
        self.artist = self._label("artist", info)
        self.album = self._label("album", info)
        self.player_lbl = self._label("player", info)

        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.scale.set_draw_value(False)
        self.scale.connect("button-press-event", self._seek_start)
        self.scale.connect("button-release-event", self._seek_end)
        card.pack_start(self.scale, False, False, 0)

        times = Gtk.Box()
        self.pos_lbl = Gtk.Label(name="time", xalign=0)
        self.len_lbl = Gtk.Label(name="time", xalign=1)
        times.pack_start(self.pos_lbl, True, True, 0)
        times.pack_end(self.len_lbl, True, True, 0)
        card.pack_start(times, False, False, 0)

        controls = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        card.pack_start(controls, False, False, 0)
        self._button(controls, G_PREV, "previous")
        self.toggle = self._button(controls, G_PLAY, "play-pause", name="toggle")
        self._button(controls, G_NEXT, "next")
        self._button(controls, G_OPEN, None, self._raise)

        self.set_size_request(440, -1)
        self.connect("key-press-event", lambda w, e: e.keyval == Gdk.KEY_Escape and self.close())
        self.connect("focus-out-event", lambda *_: self.close())
        self.add_events(Gdk.EventMask.SCROLL_MASK)
        self.connect("scroll-event", self._scroll)
        self.connect("destroy", Gtk.main_quit)

        if not self.refresh():
            sys.exit(0)
        GLib.timeout_add(POLL_MS, self.tick)

    # -- widgets ---------------------------------------------------------
    def _label(self, name, box):
        lbl = Gtk.Label(name=name, xalign=0)
        lbl.set_ellipsize(3)  # Pango.EllipsizeMode.END
        lbl.set_max_width_chars(28)
        box.pack_start(lbl, False, False, 0)
        return lbl

    def _button(self, box, glyph, action, callback=None, name=None):
        btn = Gtk.Button(label=glyph, relief=Gtk.ReliefStyle.NONE)
        if name:
            btn.set_name(name)
        btn.connect("clicked", callback or (lambda *_: self._act(action)))
        box.pack_start(btn, False, False, 0)
        return btn

    # -- actions ---------------------------------------------------------
    def _act(self, action):
        if self.player:
            run("-p", self.player, action)
            GLib.timeout_add(120, self.refresh_once)

    def refresh_once(self):
        self.refresh()
        return False

    def _raise(self, *_):
        name = (self.player or "").split(".")[0]
        subprocess.Popen(["wmctrl", "-x", "-a", name], stderr=subprocess.DEVNULL)
        self.close()

    def _seek_start(self, *_):
        self.seeking = True

    def _seek_end(self, *_):
        self.seeking = False
        if self.player and self.length:
            run("-p", self.player, "position", f"{self.scale.get_value():.1f}")
        return False

    def _scroll(self, _w, event):
        if not self.player:
            return
        if event.direction == Gdk.ScrollDirection.UP:
            run("-p", self.player, "volume", "0.05+")
        elif event.direction == Gdk.ScrollDirection.DOWN:
            run("-p", self.player, "volume", "0.05-")

    # -- state -----------------------------------------------------------
    @staticmethod
    def fetch():
        """Blocking playerctl calls — run off the GTK thread (see tick)."""
        player = pick_player()
        if not player:
            return None, None
        fmt_str = SEP.join(["{{status}}", "{{xesam:title}}", "{{xesam:artist}}", "{{xesam:album}}",
                            "{{mpris:artUrl}}", "{{mpris:length}}", "{{position}}"])
        parts = (run("-p", player, "metadata", "--format", fmt_str).split(SEP) + [""] * 7)[:7]
        return player, parts

    def tick(self):
        """Poll in a worker thread so a slow player (2 s playerctl timeout)
        never freezes the card; at most one poll in flight."""
        if not self._polling:
            self._polling = True

            def work():
                result = self.fetch()
                GLib.idle_add(self._apply_async, *result)

            threading.Thread(target=work, daemon=True).start()
        return True

    def _apply_async(self, player, parts):
        self._polling = False
        self.apply(player, parts)
        return False

    def refresh(self):
        """Synchronous refresh: used once at startup and right after a click."""
        return self.apply(*self.fetch())

    def apply(self, player, parts):
        self.player = player
        if not self.player:
            self.close()
            return False
        status, title, artist, album, art, length, pos = parts

        self.title.set_text(title or "Unknown title")
        self.artist.set_text(artist)
        self.album.set_text(album)
        self.album.set_visible(bool(album))
        self.player_lbl.set_text(self.player.split(".")[0])
        self.toggle.set_label(G_PAUSE if status == "Playing" else G_PLAY)

        try:
            self.length = int(length) / 1e6
        except ValueError:
            self.length = 0.0
        try:
            position = int(pos) / 1e6
        except ValueError:
            position = 0.0

        self.scale.set_visible(self.length > 0)
        if self.length > 0:
            self.scale.set_range(0, self.length)
            if not self.seeking:
                self.scale.set_value(min(position, self.length))
            self.len_lbl.set_text(fmt(self.length))
        else:
            self.len_lbl.set_text("live")
        self.pos_lbl.set_text(fmt(self.scale.get_value() if self.seeking else position))

        if art != self.art_url:
            self.art_url = art
            threading.Thread(target=self._load_art, args=(art,), daemon=True).start()
        return True

    def _load_art(self, url):
        path = art_path(url)
        GLib.idle_add(self._set_art, url, path)

    def _set_art(self, url, path):
        if url != self.art_url:
            return False
        pix = None
        if path:
            try:
                src = GdkPixbuf.Pixbuf.new_from_file(path)
                # Centre-crop to a square so wide video thumbnails don't squash.
                side = min(src.get_width(), src.get_height())
                src = src.new_subpixbuf((src.get_width() - side) // 2, (src.get_height() - side) // 2, side, side)
                pix = src.scale_simple(ART_SIZE, ART_SIZE, GdkPixbuf.InterpType.BILINEAR)
            except Exception:
                pix = None
        self.art.set_visible(pix is not None)
        if pix:
            self.art.set_from_pixbuf(pix)
        return False

    # -- placement -------------------------------------------------------
    def place(self):
        """Just under the bar, horizontally at the pointer, kept on-monitor."""
        display = Gdk.Display.get_default()
        _, px, py = display.get_default_seat().get_pointer().get_position()
        geo = display.get_monitor_at_point(px, py).get_geometry()
        self.show_all()
        self.refresh()
        w, _h = self.get_size()
        x = min(max(px - 60, geo.x + 8), geo.x + geo.width - w - 8)
        y = geo.y + 72  # bar offset-y (8pt) + height (38pt) + a small gap
        self.move(x, y)
        self.present()


def toggle_existing():
    """Second click on the title closes an open card instead of stacking.

    The pidfile can be stale (the card was SIGKILLed, or the session ended)
    and its PID reused by something else, so only signal a process that is
    really this script.
    """
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            if b"media-card.py" not in f.read():
                return False
        os.kill(pid, signal.SIGTERM)
        return True
    except (OSError, ValueError):
        return False


def main():
    if toggle_existing():
        return
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    try:
        signal.signal(signal.SIGTERM, lambda *_: Gtk.main_quit())
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
        card = Card()
        card.place()
        Gtk.main()
    finally:
        try:
            os.remove(PIDFILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
