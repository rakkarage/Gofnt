# Gofnt

A small Godot 4 bitmap font editor for BMFont-style `.fnt` fonts and PNG atlases.

## Features

- Open, inspect, and edit bitmap fonts (`.fnt` text/XML + atlas image)
- Edit glyph metrics/rects, add/remove glyphs, and adjust kerning
- Live text preview with zoom/pan atlas view
- Trim glyph bounds and repack atlas with Shelf, MaxRects, or Skyline packing and adjustable padding
- Import glyphs from an image or generate a bitmap font from TTF/OTF (same packing settings)
- Save edited `.fnt` and `.png` files

## Getting started

1. Open the project in Godot.
2. Run the main scene (`res://font_editor.tscn`).
3. Use **Open .fnt** to load a font, or **Import Image** / **Import TTF/OTF** to create one.
4. Edit glyphs/font settings, preview changes, then **Save .fnt** / **Save PNG**.

## Project files

- `font_editor.tscn`, `font_editor.gd` — editor UI and workflow
- `bmfont.gd` — BMFont parsing, loading, and saving
- `atlas_view.gd` — atlas/glyph view interactions
- `Font/` — source TTF/OTFs for the **Import TTF/OTF** workflow (no bundled `.fnt`/`.png` demos)

## Notes

- Focused on bitmap/BMFont workflows (not a general-purpose font editor).
- See `ATTRIBUTIONS.md` for bundled font credits.
- License: `UNLICENCE.txt`.
