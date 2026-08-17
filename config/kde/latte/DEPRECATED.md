# DEPRECATED — Latte Dock layouts

Latte Dock was **archived by its maintainer in 2023** and never gained Plasma 6
support. Nothing in this repo installs it any more:

* `profiles/kde-setup.sh` no longer includes `latte-dock` in its package list.
* `setup_latte_dock_config()` is a no-op stub kept only so old call sites don't
  break.

These `.layout.latte` files are retained purely as a historical reference.

## What to use instead

| Want | Use |
|---|---|
| A conventional KDE panel | Native Plasma panels (right-click desktop > Enter Edit Mode > Add Panel) |
| A Waybar-style top bar | `bash profiles/bar-setup.sh` — polybar, see `config/polybar/` |

## Restoring an old layout by hand

```bash
cp -r config/kde/latte ~/.config/latte
latte-dock &   # only if you still have it installed
```

This directory is safe to delete if you have no intention of going back.
