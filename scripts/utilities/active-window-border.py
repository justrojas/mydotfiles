#!/usr/bin/env python3
"""
active-window-border — draw a coloured outline around the focused window.

A jankyborders/borders equivalent for X11, written against GTK3 so it needs
only python3-gi and pycairo (both already present on a Plasma install). No
python-xlib, no compositor plugin, no third-party .deb.

WHY THIS EXISTS
---------------
Getting a visible focus indicator on this setup turned out to be surprisingly
hard:

  * The window decoration cannot do it while an Aurorae SVG theme is in use.
    Aurorae themes paint from their own SVGs and ignore the KDE colour scheme
    entirely, so setting WM/activeBackground has no effect.
  * kwin4_effect_shapecorners loads, reports enabled, and logs "shaders
    loaded" — but does not draw, even at 8px in bright red.
  * Breeze borders DO work, but only by giving up the Ant-Dark decoration.

So: draw the outline ourselves, in a separate always-on-top, click-through
window that tracks the focused window's frame.

HOW IT WORKS
------------
An override-redirect GTK window with an RGBA visual is kept just outside the
active window's frame and painted as a hollow rectangle. Two details make it
usable rather than infuriating:

  * INPUT SHAPE IS EMPTY. Without this the border swallows every click that
    lands on it, including window edges and resize handles. An empty input
    region makes it visually present but completely click-through.
  * IT NEVER TAKES FOCUS. accept_focus/focus_on_map are off, so the border
    itself can never become the active window — which would otherwise cause an
    infinite focus-follows-border loop.

Geometry is polled rather than event-driven: X11 has no single signal for
"the active window moved or resized", and with a tiling WM windows are
constantly re-laid-out. A cheap poll of one window's geometry is simpler and
more reliable than stitching together ConfigureNotify handling.

Usage:
    active-window-border.py [--color RRGGBB] [--width PX] [--radius PX]
                            [--gap PX] [--interval MS] [--inactive-alpha A]
"""

import argparse
import math
import subprocess
import sys

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402


# Window classes that should never get a border: our own bar, the desktop
# shell, and the border window itself.
SKIP_CLASSES = {
    "polybar",
    "plasmashell",
    "krunner",
    "latte-dock",
    "active-window-border",
}


def hex_to_rgb(value):
    value = value.lstrip("#")
    if len(value) != 6:
        raise argparse.ArgumentTypeError(f"expected RRGGBB, got {value!r}")
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))


class BorderWindow(Gtk.Window):
    def __init__(self, opts):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.opts = opts
        self.rgb = opts.color
        self._last = None

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is None:
            sys.exit(
                "error: no RGBA visual available.\n"
                "       A compositor must be running (KWin provides one)."
            )
        self.set_visual(visual)

        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        # Never become the active window — that would make the border chase
        # itself in a focus loop.
        self.set_accept_focus(False)
        self.set_focus_on_map(False)
        self.set_type_hint(Gdk.WindowTypeHint.DOCK)

        # Show on every virtual desktop. Without this the border window is
        # bound to whichever desktop it was first mapped on, so switching
        # desktops leaves it behind — the ring appears to break or vanish
        # while the focused window on the new desktop gets nothing.
        self.stick()

        self.connect("draw", self.on_draw)
        self.connect("realize", self.on_realize)

    def on_realize(self, _widget):
        # Empty input region => fully click-through. Without this the border
        # eats clicks on window edges and resize handles.
        self.input_shape_combine_region(cairo.Region())

    def on_draw(self, _widget, cr):
        w = self.get_allocated_width()
        h = self.get_allocated_height()
        bw = self.opts.width
        r = self.opts.radius

        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        cr.set_source_rgba(*self.rgb, self.opts.alpha)
        cr.set_line_width(bw)

        # Stroke centred on the path, so inset by half the line width.
        x = y = bw / 2.0
        ww = max(0.0, w - bw)
        hh = max(0.0, h - bw)
        rr = min(r, ww / 2.0, hh / 2.0)

        if rr <= 0:
            cr.rectangle(x, y, ww, hh)
        else:
            cr.new_sub_path()
            cr.arc(x + ww - rr, y + rr, rr, -math.pi / 2, 0)
            cr.arc(x + ww - rr, y + hh - rr, rr, 0, math.pi / 2)
            cr.arc(x + rr, y + hh - rr, rr, math.pi / 2, math.pi)
            cr.arc(x + rr, y + rr, rr, math.pi, 3 * math.pi / 2)
            cr.close_path()
        cr.stroke()
        return False


_class_cache = {}
_gtk_extents_cache = {}


def gtk_frame_extents(xid, rect):
    """Invisible shadow margins (left, right, top, bottom) for CSD windows.

    GTK client-side-decorated apps draw their own drop shadow *inside* the
    window, so the frame X reports is substantially larger than the window you
    can see. Firefox and Zen report 45px on every side: a Zen window whose
    visible bounds are 964,54 948x1138 reports 919,9 1038x1228. Tracing that
    verbatim puts the ring 45px out on all sides, overlapping the neighbouring
    tile — which is the "off-angle" border.

    Apps without CSD (kitty, and anything using server-side decorations) do not
    set the property at all, in which case there is nothing to subtract.

    Cached on (xid, width, height) rather than xid alone: GTK zeroes these
    margins when a window is maximised, so the value has to be re-read whenever
    the geometry changes — but not on every poll tick.
    """
    key = (xid, rect.width, rect.height)
    if key in _gtk_extents_cache:
        return _gtk_extents_cache[key]

    margins = (0, 0, 0, 0)
    try:
        out = subprocess.run(
            ["xprop", "-id", str(xid), "_GTK_FRAME_EXTENTS"],
            capture_output=True,
            text=True,
            timeout=1,
        ).stdout
        if "=" in out and "not found" not in out:
            parts = [int(p.strip()) for p in out.split("=", 1)[1].split(",")]
            if len(parts) == 4:
                margins = tuple(parts)
    except Exception:
        pass

    if len(_gtk_extents_cache) > 512:
        _gtk_extents_cache.clear()
    _gtk_extents_cache[key] = margins
    return margins


def window_class(gdk_window):
    """Best-effort WM_CLASS for a foreign GdkWindow.

    Cached per-XID: this is called on every poll tick, and spawning xprop 25
    times a second is a pointless amount of process churn for a value that
    never changes over a window's lifetime.
    """
    try:
        xid = gdk_window.get_xid()
    except Exception:
        return ""

    if xid in _class_cache:
        return _class_cache[xid]

    try:
        out = subprocess.run(
            ["xprop", "-id", str(xid), "WM_CLASS"],
            capture_output=True,
            text=True,
            timeout=1,
        ).stdout
        cls = out.split("=", 1)[1].strip().lower() if "=" in out else ""
    except Exception:
        cls = ""

    # Keep the cache from growing without bound over a long session.
    if len(_class_cache) > 512:
        _class_cache.clear()
    _class_cache[xid] = cls
    return cls


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--color", type=hex_to_rgb, default=hex_to_rgb("9d7cd8"),
                    help="border colour as RRGGBB (default 9d7cd8)")
    ap.add_argument("--width", type=int, default=3, help="border thickness in px")
    ap.add_argument("--radius", type=int, default=10, help="corner radius in px")
    ap.add_argument("--gap", type=int, default=0,
                    help="gap between window frame and border in px")
    ap.add_argument("--mode", choices=("inset", "outset"), default="inset",
                    help="draw the ring inside the window edge (inset, the "
                         "default and correct choice for zero-gap tiling) or "
                         "outside it (outset, needs tiling gaps to be visible)")
    ap.add_argument("--alpha", type=float, default=1.0, help="border opacity 0-1")
    ap.add_argument("--interval", type=int, default=40,
                    help="geometry poll interval in ms")
    opts = ap.parse_args()

    border = BorderWindow(opts)
    screen = Gdk.Screen.get_default()
    display = Gdk.Display.get_default()

    state = {"visible": False}

    def conceal():
        if state["visible"]:
            border.hide()
            # Park it off-screen as well as unmapping it. KWin composites a
            # drop shadow for the border window, and that shadow can briefly
            # outlive the unmap — which shows up as a faint ghost of the ring
            # when switching to an empty desktop. Moving it out of the viewport
            # means there is nothing left in place to leave a smear.
            border.move(-32000, -32000)
            border._last = None
            state["visible"] = False

    def tick():
        active = screen.get_active_window()
        if active is None:
            conceal()
            return True

        # NOTE: is_viewable() is deliberately NOT used to detect "window is on
        # another desktop". Measured on KWin 5.27/X11, a window on a different
        # virtual desktop still reports viewable=True, so that test is a no-op.
        # What actually handles the empty-desktop case is the plasmashell entry
        # in SKIP_CLASSES: switching to a desktop with no windows makes the
        # desktop shell itself the active window.
        cls = window_class(active)
        if any(skip in cls for skip in SKIP_CLASSES):
            conceal()
            return True

        # Frame extents include the decoration, so the border hugs the window
        # as the user sees it rather than the client area.
        rect = active.get_frame_extents()

        # A destroyed or not-yet-mapped window reports a degenerate frame.
        # Drawing that leaves a stray sliver on screen.
        if rect.width <= 1 or rect.height <= 1:
            conceal()
            return True

        # Strip the invisible CSD shadow, so the ring hugs the window the user
        # can actually see rather than its shadow bounding box.
        ml, mr, mt, mb = gtk_frame_extents(active.get_xid(), rect)
        rx = rect.x + ml
        ry = rect.y + mt
        rw = max(1, rect.width - ml - mr)
        rh = max(1, rect.height - mt - mb)

        bw = opts.width
        g = opts.gap

        if opts.mode == "outset":
            # Ring sits outside the frame. Looks best with tiling gaps; with
            # zero-gap tiling it spills off-screen and under neighbours.
            x = rx - bw - g
            y = ry - bw - g
            w = rw + 2 * (bw + g)
            h = rh + 2 * (bw + g)
        else:
            # Ring is drawn just inside the frame, overlapping the window's own
            # edge. Always fully visible regardless of gaps, which makes it the
            # safe default for edge-to-edge tiling.
            x = rx + g
            y = ry + g
            w = max(1, rw - 2 * g)
            h = max(1, rh - 2 * g)

        # Clamp to the monitor's work area.
        #
        # Some clients report frame extents far larger than the window you can
        # actually see, because the "frame" includes an invisible shadow and
        # resize margin. Firefox is the worst offender here: measured at
        # x=-37 w=1994 on a 1920-wide screen. Tracing that verbatim runs the
        # ring off both edges and reads as a misaligned border.
        #
        # Work area rather than raw monitor geometry, so the ring also stays
        # clear of the bar's reserved strut.
        try:
            monitor = display.get_monitor_at_window(active)
            if monitor is not None:
                wa = monitor.get_workarea()
                x2 = min(x + w, wa.x + wa.width)
                y2 = min(y + h, wa.y + wa.height)
                x = max(x, wa.x)
                y = max(y, wa.y)
                w = max(1, x2 - x)
                h = max(1, y2 - y)
        except Exception:
            pass

        geom = (x, y, w, h)
        if geom != border._last:
            border._last = geom
            # set_size_request, not just resize(): this window has no child
            # widget, so GTK computes a 1x1 natural size and clamps resize()
            # to it — which parks the border in the top-left corner. Forcing
            # the minimum size is what actually makes it track the window.
            border.set_size_request(w, h)
            border.resize(w, h)
            border.move(x, y)
            border.queue_draw()

        if not state["visible"]:
            border.show_all()
            border.set_keep_above(True)
            # Re-assert stickiness after every map: some window managers reset
            # the desktop assignment when a window is unmapped and remapped.
            border.stick()
            state["visible"] = True
        return True

    GLib.timeout_add(opts.interval, tick)
    Gtk.main()


if __name__ == "__main__":
    main()
