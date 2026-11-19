# AGENTS.md

## What this is

- A Godot 4.7 / GDScript editor for BMFont `.fnt` fonts + PNG atlases. Despite the repo name `Gofnt` and CI file `gobot-go.yml`, there is **no Go code and no Go toolchain**.
- No build system, tests, linter, or formatter/typecheck config. Verify manually: open in Godot 4.7 and run the main scene `res://font_editor.tscn`. Parse/import-only check from repo root: `godot --headless --path . --editor --quit`.

## Code map

- `font_editor.gd` — main controller (`@tool`, extends `PanelContainer`). UI behavior lives in signal connections made in `_bind_ui()` and the `_on_*` handlers, not in `font_editor.tscn`; start there when tracing an action.
- `bmfont.gd` — `class_name BMFontData` (`RefCounted`): parses/loads/saves `.fnt` text **and** XML, owns the atlas `Image`, glyphs and kerning. Global class, usable from any script.
- `atlas_view.gd` (`FontAtlasView`), `char_preview.gd` (`CharPreview`), `ttf_preview.gd` — `@tool` UI components; `ttf_preview.gd` is the live fill/outline preview for the TTF import dialog.
- All four scripts are `@tool`: they execute inside the editor, so a syntax or runtime error can break the editor itself.
- `Font/` holds TTF/OTF sources only; there are no bundled `.fnt`/`.png` demos. Generate a test font via **Import TTF/OTF** or open an external `.fnt`.

## Godot/tooling gotchas

- `*.gd.uid` sidecars exist and `font_editor.tscn` references some scripts via `uid://...`. Let Godot generate them; don't hand-edit UIDs or invent them for new scripts.
- `.godot/` is gitignored generated editor/import cache (holds `global_script_class_cache.cfg`, which registers the `class_name` types). Don't commit it; if globals or resources look stale, reimport from the editor.
- Preferences persist at runtime to `user://settings.cfg` (fullscreen, TTF import options, file-dialog favorites). They are not in the repo; don't look for them in git.

## TTF import

- TTF/OTF import *generates* a bitmap font: font bytes are loaded into a `Font`, glyphs rendered through a `SubViewport` with fill/outline/gradient/procedural effects, then packed into an atlas. Not a simple file copy; changes there affect the whole generated font.

## Ship / CI

- Only export preset is `Web`. `.github/workflows/gobot-go.yml` is `workflow_dispatch`-only and delegates to `rakkarage/auto/.github/workflows/gobot.yml@main` to publish GitHub Pages. No automated tests or lint in CI.
