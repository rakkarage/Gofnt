@tool
extends PanelContainer

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "window"
const SETTINGS_FULLSCREEN_KEY := "fullscreen"
const SETTINGS_TTF_SECTION := "ttf_import"
const SETTINGS_UI_SECTION := "ui"
const SETTINGS_APPLY_DEMO_KEY := "apply_demo"

var data: BMFontData
var atlas: Control
var glyph_list: ItemList
var status_lbl: Label
var preview_edit: TextEdit
var preview_canvas: Control
var stats_lbl: RichTextLabel
var load_demo_lbl: Label
var apply_demo_lbl: Label
var preview_lbl: Label
var kern_list: ItemList
var prop_spin: Dictionary = {}
var font_line_h: SpinBox
var font_base: SpinBox
var glyph_action_btn: Button
var fullscreen_cb: CheckBox
var apply_dd: OptionButton
var preview_scale: float = 2.0
var sel_id: int = -1
var _updating_ui := false

func _ready() -> void:
	name = "Gofnt"
	data = BMFontData.new()
	_build_ui()
	_apply_ui_tint()
	set_process_unhandled_input(true)
	_apply_project_default_theme()
	_load_window_settings()
	_load_apply_settings()
	_set_status("Drop-ready: use Open .fnt to load a bitmap font (text BMFont) and its atlas PNG.  Toggle Fullscreen with F11 or the checkbox.")

func _apply_project_default_theme() -> void:
	var def_path := str(ProjectSettings.get_setting("gui/theme/custom", "res://theme/venice16_x1.tres"))
	if def_path != "" and ResourceLoader.exists(def_path):
		theme = load(def_path)
	elif ResourceLoader.exists("res://theme/venice16_x1.tres"):
		theme = load("res://theme/venice16_x1.tres")
	preview_scale = 1.0
	if preview_canvas:
		preview_canvas.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		if fullscreen_cb:
			fullscreen_cb.button_pressed = not fullscreen_cb.button_pressed
		else:
			_set_fullscreen(not _is_fullscreen(), true)
		accept_event()

func _is_fullscreen() -> bool:
	var win := get_window()
	return win != null and win.mode == Window.MODE_FULLSCREEN

func _set_fullscreen(enabled: bool, persist: bool = true) -> void:
	var win := get_window()
	if win:
		win.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	if persist:
		_save_window_settings(enabled)

func _load_window_settings() -> void:
	var cfg := ConfigFile.new()
	var enabled := false
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_FULLSCREEN_KEY, false))
	if fullscreen_cb:
		fullscreen_cb.set_pressed_no_signal(enabled)
	_set_fullscreen(enabled, false)

func _save_window_settings(enabled: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_FULLSCREEN_KEY, enabled)
	cfg.save(SETTINGS_PATH)

func _load_ttf_import_settings() -> Dictionary:
	var defaults := {
		"size": 16,
		"filter": 0,
		"outline": 0,
		"outline_color": Color.BLACK,
		"gradient_dir": 0,
		"gradient_color1": Color.WHITE,
		"gradient_color2": Color(0.7, 0.85, 1.0, 1.0),
		"fill_mode": 0, # 0=solid, 1=gradient, 2=stamp(image), 3=procedural
		"stamp_path": "",
		"stamp_tile": true,
		"proc_effect": 0, # 0=scanlines,1=bayer,2=checker,3=noise,4=edge tint/bevel
		"proc_color": Color(1, 1, 1, 1),
	}
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return defaults
	defaults["size"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "size", defaults["size"]))
	defaults["filter"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "filter", defaults["filter"]))
	defaults["outline"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "outline", defaults["outline"]))
	defaults["outline_color"] = Color.from_string(str(cfg.get_value(SETTINGS_TTF_SECTION, "outline_color", defaults["outline_color"].to_html())), defaults["outline_color"])
	defaults["gradient_dir"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "gradient_dir", defaults["gradient_dir"]))
	defaults["gradient_color1"] = Color.from_string(str(cfg.get_value(SETTINGS_TTF_SECTION, "gradient_color1", defaults["gradient_color1"].to_html())), defaults["gradient_color1"])
	defaults["gradient_color2"] = Color.from_string(str(cfg.get_value(SETTINGS_TTF_SECTION, "gradient_color2", defaults["gradient_color2"].to_html())), defaults["gradient_color2"])
	defaults["fill_mode"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "fill_mode", -1))
	defaults["stamp_path"] = str(cfg.get_value(SETTINGS_TTF_SECTION, "stamp_path", defaults["stamp_path"]))
	defaults["stamp_tile"] = bool(cfg.get_value(SETTINGS_TTF_SECTION, "stamp_tile", defaults["stamp_tile"]))
	defaults["proc_effect"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "proc_effect", defaults["proc_effect"]))
	defaults["proc_color"] = Color.from_string(str(cfg.get_value(SETTINGS_TTF_SECTION, "proc_color", defaults["proc_color"].to_html())), defaults["proc_color"])
	# Backward compat: old configs had gradient_dir but no fill_mode.
	if defaults["fill_mode"] < 0:
		defaults["fill_mode"] = 1 if int(defaults["gradient_dir"]) != 0 else 0
	return defaults

func _save_ttf_import_settings(opts: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_TTF_SECTION, "size", int(opts.get("size", 16)))
	cfg.set_value(SETTINGS_TTF_SECTION, "filter", int(opts.get("filter", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "outline", int(opts.get("outline", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "outline_color", (opts.get("outline_color", Color.BLACK) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_dir", int(opts.get("gradient_dir", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_color1", (opts.get("gradient_color1", Color.WHITE) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_color2", (opts.get("gradient_color2", Color.WHITE) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "fill_mode", int(opts.get("fill_mode", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "stamp_path", str(opts.get("stamp_path", "")))
	cfg.set_value(SETTINGS_TTF_SECTION, "stamp_tile", bool(opts.get("stamp_tile", true)))
	cfg.set_value(SETTINGS_TTF_SECTION, "proc_effect", int(opts.get("proc_effect", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "proc_color", (opts.get("proc_color", Color.WHITE) as Color).to_html())
	cfg.save(SETTINGS_PATH)

func _apply_ui_tint() -> void:
	var accent := Color(0.45, 0.72, 1.0)
	var accent_dim := Color(0.45, 0.72, 1.0, 0.18)
	var panel := get_theme_stylebox("panel", "PanelContainer")
	if panel:
		panel = panel.duplicate()
		if panel is StyleBoxFlat:
			var sb := panel as StyleBoxFlat
			sb.bg_color = sb.bg_color.lerp(Color(0.13, 0.15, 0.19), 0.35)
			sb.border_width_top = 1
			sb.border_width_bottom = 1
			sb.border_width_left = 1
			sb.border_width_right = 1
			sb.border_color = accent_dim
			add_theme_stylebox_override("panel", sb)
	if status_lbl:
		status_lbl.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96, 0.92).lerp(accent, 0.12))
	if stats_lbl:
		stats_lbl.add_theme_color_override("default_color", Color(0.9, 0.93, 0.98, 0.95))

func _clear_ui_tint() -> void:
	remove_theme_stylebox_override("panel")
	if status_lbl:
		status_lbl.remove_theme_color_override("font_color")
	if stats_lbl:
		stats_lbl.remove_theme_color_override("default_color")
	if load_demo_lbl:
		load_demo_lbl.remove_theme_color_override("font_color")
	if apply_demo_lbl:
		apply_demo_lbl.remove_theme_color_override("font_color")
	if preview_lbl:
		preview_lbl.remove_theme_color_override("font_color")

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	# Left: toolbar + atlas + preview
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	root.add_child(left)

	var bar := HFlowContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(bar)
	var open_btn := Button.new(); open_btn.text = "Open .fnt"; open_btn.tooltip_text = "Load a BMFont .fnt (text/XML) and its atlas PNG"; open_btn.pressed.connect(_on_open); bar.add_child(open_btn)
	var open_img_btn := Button.new(); open_img_btn.text = "Import Image"; open_img_btn.tooltip_text = "Import a PNG and auto-detect glyph regions (creates a new font)"; open_img_btn.pressed.connect(_on_import_image); bar.add_child(open_img_btn)
	var open_ttf_btn := Button.new(); open_ttf_btn.text = "Import TTF/OTF"; open_ttf_btn.tooltip_text = "Generate a bitmap font atlas from a TTF/OTF at a chosen size (basic rasterization)"; open_ttf_btn.pressed.connect(_on_import_ttf); bar.add_child(open_ttf_btn)
	var save_fnt_btn := Button.new(); save_fnt_btn.text = "Save .fnt"; save_fnt_btn.tooltip_text = "Save BMFont data to the loaded .fnt path"; save_fnt_btn.pressed.connect(_on_save_fnt); bar.add_child(save_fnt_btn)
	var save_png_btn := Button.new(); save_png_btn.text = "Save PNG"; save_png_btn.tooltip_text = "Save atlas image to the loaded PNG path"; save_png_btn.pressed.connect(_on_save_png); bar.add_child(save_png_btn)
	bar.add_child(VSeparator.new())
	var autoslice_btn := Button.new(); autoslice_btn.text = "Trim selected"; autoslice_btn.tooltip_text = "Trim selected glyph rect to non-transparent bounds"; autoslice_btn.pressed.connect(_on_autoslice_selected); bar.add_child(autoslice_btn)
	var autoslice_all_btn := Button.new(); autoslice_all_btn.text = "Trim all"; autoslice_all_btn.tooltip_text = "Trim all glyph rects to non-transparent bounds (does not detect new glyphs)"; autoslice_all_btn.pressed.connect(_on_autoslice_all); bar.add_child(autoslice_all_btn)
	var repack_btn := Button.new(); repack_btn.text = "Repack"; repack_btn.tooltip_text = "Shelf-pack glyphs into a tighter power-of-two atlas"; repack_btn.pressed.connect(_on_repack); bar.add_child(repack_btn)
	bar.add_child(VSeparator.new())
	fullscreen_cb = CheckBox.new()
	fullscreen_cb.text = "Fullscreen (F11)"
	fullscreen_cb.tooltip_text = "Toggle fullscreen window mode (persisted across runs)"
	fullscreen_cb.toggled.connect(func(pressed: bool): _set_fullscreen(pressed, true))
	bar.add_child(fullscreen_cb)
	status_lbl = Label.new(); status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_lbl.text = ""; status_lbl.clip_text = true; left.add_child(status_lbl)

	var examples_row := HBoxContainer.new(); left.add_child(examples_row)
	load_demo_lbl = _lbl("Load Demo:")
	load_demo_lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0))
	examples_row.add_child(load_demo_lbl)
	var load_dd := OptionButton.new()
	load_dd.add_item("[load]", 0)
	load_dd.add_item("SuperBlack12", 2)
	load_dd.add_item("SuperWhite12", 3)
	load_dd.add_item("Venice16", 1)
	load_dd.tooltip_text = "Load an example bitmap font (.fnt + atlas) from bundled demos"
	load_dd.item_selected.connect(func(i): _on_load_example(load_dd.get_item_id(i)); load_dd.select(0))
	examples_row.add_child(load_dd)
	examples_row.add_child(VSeparator.new())
	apply_demo_lbl = _lbl("Apply Demo:")
	apply_demo_lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0))
	examples_row.add_child(apply_demo_lbl)
	apply_dd = OptionButton.new()
	for item in [
		["None", 0],
		["SuperBlack12 @1x (12)", 3],
		["SuperBlack12 @2x (24)", 4],
		["SuperWhite12 @1x (12)", 5],
		["SuperWhite12 @2x (24)", 6],
		["Venice16 @1x (16)", 1],
		["Venice16 @2x (32)", 2],
	]:
		apply_dd.add_item(item[0], item[1])
	apply_dd.tooltip_text = "Apply an example UI theme/font scale to the editor and preview"
	apply_dd.item_selected.connect(func(i): _on_apply_example(apply_dd.get_item_id(i)))
	apply_dd.select(apply_dd.get_item_index(1))
	examples_row.add_child(apply_dd)

	atlas = FontAtlasView.new()
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas.size_flags_stretch_ratio = 3.0
	atlas.custom_minimum_size = Vector2(400, 300)
	atlas.glyph_selected.connect(_on_glyph_selected)
	atlas.glyph_changed.connect(_on_glyph_changed)
	left.add_child(atlas)

	preview_lbl = Label.new(); preview_lbl.text = "Live preview"
	preview_lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0))
	left.add_child(preview_lbl)
	preview_edit = TextEdit.new()
	preview_edit.text = "The quick brown fox jumps over the lazy dog.\n0123456789 !?@#$%"
	preview_edit.custom_minimum_size = Vector2(0, 80)
	preview_edit.scroll_fit_content_height = false
	preview_edit.text_changed.connect(func(): preview_canvas.queue_redraw())
	left.add_child(preview_edit)
	preview_canvas = Control.new()
	preview_canvas.custom_minimum_size = Vector2(0, 120)
	preview_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_canvas.draw.connect(_draw_preview)
	left.add_child(preview_canvas)

	# Right: tabs
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.3
	tabs.custom_minimum_size = Vector2(320, 0)
	root.add_child(tabs)

	tabs.add_child(_build_glyph_tab())
	tabs.set_tab_title(0, "Glyph")
	tabs.add_child(_build_font_tab())
	tabs.set_tab_title(1, "Font/Stats")
	tabs.add_child(_build_kern_tab())
	tabs.set_tab_title(2, "Kerning")

func _build_glyph_tab() -> Control:
	var vb := VBoxContainer.new()
	var hl := Label.new(); hl.text = "Glyphs (ASCII 32-126 shown; missing can be created)"; vb.add_child(hl)
	glyph_list = ItemList.new(); glyph_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; glyph_list.custom_minimum_size = Vector2(0, 180)
	glyph_list.item_selected.connect(_on_list_selected)
	vb.add_child(glyph_list)
	var add_row := HBoxContainer.new(); vb.add_child(add_row)
	var add_edit := LineEdit.new(); add_edit.placeholder_text = "char or id (e.g. A or 65)"; add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_row.add_child(add_edit)
	var add_btn := Button.new(); add_btn.text = "Add / Go"; add_btn.tooltip_text = "Create (if missing) and select glyph for the given character or numeric id"; add_row.add_child(add_btn)
	add_btn.pressed.connect(func(): _add_or_select_glyph(add_edit.text))
	add_edit.text_submitted.connect(func(_t): _add_or_select_glyph(add_edit.text))
	glyph_action_btn = Button.new(); glyph_action_btn.text = "Create glyph"; glyph_action_btn.disabled = true
	glyph_action_btn.tooltip_text = "Create or delete the selected glyph entry"
	glyph_action_btn.pressed.connect(_on_glyph_action)
	vb.add_child(glyph_action_btn)
	var grid := GridContainer.new(); grid.columns = 2; vb.add_child(grid)
	for key in ["x", "y", "width", "height", "xoffset", "yoffset", "xadvance"]:
		var l := Label.new(); l.text = key; grid.add_child(l)
		var s := SpinBox.new(); s.min_value = -4096; s.max_value = 4096; s.step = 1; s.allow_greater = true; s.allow_lesser = true
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(v): _on_prop_changed(key, int(v)))
		grid.add_child(s)
		prop_spin[key] = s
	var hint := Label.new(); hint.text = "Tip: select a (missing) entry to create it (gets a default rect). Set x/y/width/height in properties or drag/resize it in the atlas. Mouse wheel zooms, middle-drag pans."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	return vb

func _build_font_tab() -> Control:
	var vb := VBoxContainer.new()
	var g := GridContainer.new(); g.columns = 2; vb.add_child(g)
	g.add_child(_lbl("lineHeight")); font_line_h = SpinBox.new(); font_line_h.max_value = 4096; font_line_h.value_changed.connect(func(v): if not _updating_ui: data.common["lineHeight"] = int(v); preview_canvas.queue_redraw()); font_line_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(font_line_h)
	g.add_child(_lbl("base")); font_base = SpinBox.new(); font_base.max_value = 4096; font_base.value_changed.connect(func(v): if not _updating_ui: data.common["base"] = int(v)); font_base.size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(font_base)
	var bulk := HBoxContainer.new(); vb.add_child(bulk)
	bulk.add_child(_lbl("All xadvance +")); var ba := SpinBox.new(); ba.min_value = -999; ba.max_value = 999; ba.value = 0; bulk.add_child(ba)
	var bbtn := Button.new(); bbtn.text = "Apply"; bbtn.pressed.connect(func(): _bulk_advance(int(ba.value))); bulk.add_child(bbtn)
	var st := Label.new(); st.text = "Stats & details"; vb.add_child(st)
	stats_lbl = RichTextLabel.new(); stats_lbl.fit_content = true; stats_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL; stats_lbl.bbcode_enabled = true
	vb.add_child(stats_lbl)
	return vb

func _build_kern_tab() -> Control:
	var vb := VBoxContainer.new()
	vb.add_child(_lbl("Kerning pairs"))
	kern_list = ItemList.new(); kern_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(kern_list)
	var row := HBoxContainer.new(); vb.add_child(row)
	var f1 := LineEdit.new(); f1.placeholder_text = "first char"; f1.custom_minimum_size = Vector2(60, 0); row.add_child(f1)
	var f2 := LineEdit.new(); f2.placeholder_text = "second"; f2.custom_minimum_size = Vector2(60, 0); row.add_child(f2)
	var amt := SpinBox.new(); amt.min_value = -200; amt.max_value = 200; row.add_child(amt)
	var addb := Button.new(); addb.text = "Add/Set"; addb.pressed.connect(func(): _add_kern(f1.text, f2.text, int(amt.value))); row.add_child(addb)
	var delb := Button.new(); delb.text = "Remove sel"; delb.pressed.connect(_remove_kern); vb.add_child(delb)
	return vb

func _lbl(t: String) -> Label:
	var l := Label.new(); l.text = t; return l

func _set_status(t: String) -> void:
	if status_lbl: status_lbl.text = t

func _apply_texture_filter(filter_mode: int) -> void:
	var tf := CanvasItem.TEXTURE_FILTER_NEAREST if filter_mode == 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	if preview_canvas:
		preview_canvas.texture_filter = tf
	if atlas:
		atlas.texture_filter = tf
	# note: BMFont .fnt doesn't store Godot texture filter; this affects editor preview/atlas rendering.

func _on_open() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.fnt ; BMFont"])
	add_child(dlg)
	dlg.file_selected.connect(func(p): _load_font(p); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _load_font(path: String) -> void:
	var err := data.load_fnt(path)
	if err != OK:
		_set_status("Failed to load: %s (err %d)" % [path, err]); return
	atlas.set_data(data)
	_updating_ui = true
	font_line_h.value = int(data.common.get("lineHeight", 16))
	font_base.value = int(data.common.get("base", 12))
	_updating_ui = false
	_refresh_glyph_list(); _refresh_kern(); _refresh_stats()
	_apply_texture_filter(0)
	_set_status("Loaded %s  |  %d glyphs" % [data.info.get("face", path.get_file()), data.chars.size()])
	preview_canvas.queue_redraw(); atlas.queue_redraw()

func _refresh_glyph_list() -> void:
	glyph_list.clear()
	if data == null or data.image == null: return
	var ids := {}
	for id in data.chars.keys():
		ids[int(id)] = true
	var shown: Array[int] = []
	for id in range(32, 127):
		shown.append(id)
	for id in data.sorted_char_ids():
		var iid := int(id)
		if iid < 32 or iid > 126:
			shown.append(iid)
	shown.sort()
	for id in shown:
		var has := ids.has(id)
		var ch := "space" if id == 32 else String.chr(id)
		if has:
			var c: Dictionary = data.chars[id]
			var w := int(c.get("width", 0)); var h := int(c.get("height", 0))
			var label := "%s  (%d)  adv:%s" % [ch, id, str(c.get("xadvance", 0))]
			if w <= 0 or h <= 0:
				label += "  (empty)"
			var idx := glyph_list.add_item(label)
			glyph_list.set_item_metadata(idx, id)
			if w > 0 and h > 0:
				glyph_list.set_item_custom_fg_color(idx, Color(0.8, 1.0, 0.85, 0.95)) # used/defined
			else:
				glyph_list.set_item_custom_fg_color(idx, Color(1.0, 0.9, 0.6, 0.9)) # created but no rect
		else:
			var idx := glyph_list.add_item("%s  (%d)  (missing)" % [ch, id])
			glyph_list.set_item_metadata(idx, id)
			glyph_list.set_item_custom_fg_color(idx, Color(1, 1, 1, 0.4))
	_update_glyph_action()

func _refresh_kern() -> void:
	kern_list.clear()
	for k in data.kernings:
		var a := int(k.get("first", 0)); var b := int(k.get("second", 0)); var v := int(k.get("amount", 0))
		var idx := kern_list.add_item("%s,%s (%d,%d) = %d" % [String.chr(a), String.chr(b), a, b, v])
		kern_list.set_item_metadata(idx, k)

func _refresh_stats() -> void:
	if data == null or data.image == null: stats_lbl.text = "No font loaded."; return
	var s := data.get_stats()
	var fillp := snappedf(s.fill_ratio * 100.0, 0.01)
	stats_lbl.text = "[b]Atlas[/b]\n%dx%d  area:%d  glyph area:%d  fill:%s%%\nused bounds:%s\n\n[b]Font[/b]\nface:%s  glyphs:%d  kern pairs:%d\nlineHeight:%d  base:%d  median xadvance:%d\n\n[b]Texture[/b]\n%s" % [
		s.atlas_w, s.atlas_h, s.atlas_area, s.glyph_area, str(fillp), str(s.used_bounds),
		str(data.info.get("face", "?")), s.glyphs, s.kern_pairs, s.line_height, s.base, s.median_xadvance, str(data.image_path)
	]

func _on_glyph_selected(id: int) -> void:
	if id != -1:
		_ensure_glyph(id)
	sel_id = id
	_sync_props()
	# select in list
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == id:
			glyph_list.select(i); glyph_list.ensure_current_is_visible(); break

func _on_list_selected(idx: int) -> void:
	var id := int(glyph_list.get_item_metadata(idx))
	if data != null and data.image != null and not data.chars.has(id):
		_ensure_glyph(id)
		_refresh_glyph_list()
		for i in glyph_list.item_count:
			if int(glyph_list.get_item_metadata(i)) == id:
				glyph_list.select(i); glyph_list.ensure_current_is_visible(); break
		_set_status("Created glyph %d (%s) — set its rect in the atlas/properties" % [id, ("space" if id == 32 else String.chr(id))])
	sel_id = id
	atlas.selected_id = sel_id
	atlas.queue_redraw()
	_sync_props()

func _ensure_glyph(id: int) -> void:
	if data == null or data.chars.has(id): return
	var lh := maxi(1, int(data.common.get("lineHeight", 16)))
	# default to a visible, draggable rect so it can be placed/resized in the atlas immediately
	data.chars[id] = {"id": id, "x": 0, "y": 0, "width": lh, "height": lh, "xoffset": 0, "yoffset": 0, "xadvance": int(lh * 0.6), "page": 0, "chnl": 15}

func _add_or_select_glyph(text: String) -> void:
	if data == null or data.image == null:
		_set_status("Load or import a font/image first"); return
	var t := text.strip_edges()
	if t.is_empty(): return
	var id := -1
	if t.is_valid_int():
		id = int(t)
	elif t.length() >= 1:
		id = t.unicode_at(0)
	if id < 0: return
	var created := not data.chars.has(id)
	_ensure_glyph(id)
	if created:
		_refresh_glyph_list(); _refresh_stats()
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == id:
			glyph_list.select(i); _on_list_selected(i); glyph_list.ensure_current_is_visible(); return
	# id outside shown range, add to list view by refreshing
	_refresh_glyph_list()
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == id:
			glyph_list.select(i); _on_list_selected(i); return

func _sync_props() -> void:
	_updating_ui = true
	var has := data != null and sel_id != -1 and data.chars.has(sel_id)
	for k in prop_spin.keys():
		var s: SpinBox = prop_spin[k]
		s.editable = has
		s.value = int(data.chars[sel_id].get(k, 0)) if has else 0
	_updating_ui = false
	_update_glyph_action()

func _update_glyph_action() -> void:
	if glyph_action_btn == null: return
	if data == null or data.image == null or sel_id < 0:
		glyph_action_btn.disabled = true; glyph_action_btn.text = "Create glyph"; return
	glyph_action_btn.disabled = false
	if data.chars.has(sel_id):
		glyph_action_btn.text = "Delete glyph %d" % sel_id
	else:
		glyph_action_btn.text = "Create glyph %d" % sel_id

func _on_glyph_action() -> void:
	if data == null or data.image == null or sel_id < 0: return
	if data.chars.has(sel_id):
		data.chars.erase(sel_id)
		atlas.selected_id = -1
		_set_status("Deleted glyph %d" % sel_id)
	else:
		_ensure_glyph(sel_id)
		_set_status("Created glyph %d" % sel_id)
	_refresh_glyph_list(); _refresh_stats(); atlas.queue_redraw(); preview_canvas.queue_redraw()
	_sync_props()
	# reselect same id in list
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == sel_id:
			glyph_list.select(i); break

func _on_prop_changed(key: String, val: int) -> void:
	if _updating_ui or sel_id == -1 or not data.chars.has(sel_id): return
	data.chars[sel_id][key] = val
	atlas.queue_redraw(); preview_canvas.queue_redraw(); _refresh_stats()

func _on_glyph_changed(_id: int) -> void:
	_sync_props(); preview_canvas.queue_redraw(); _refresh_stats()

func _bulk_advance(delta: int) -> void:
	if data == null: return
	for id in data.chars.keys():
		data.chars[id]["xadvance"] = int(data.chars[id].get("xadvance", 0)) + delta
	_sync_props(); _refresh_glyph_list(); preview_canvas.queue_redraw(); _set_status("Applied xadvance %+d to all glyphs" % delta)

func _draw_preview() -> void:
	var c := preview_canvas
	var bg := Color(0.18, 0.18, 0.2)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), bg)
	if data == null or data.texture == null: return
	var txt := preview_edit.text
	var lh := int(data.common.get("lineHeight", 16))
	var s := preview_scale
	var margin := Vector2(8, 8)
	var kern := {}
	for k in data.kernings:
		kern[Vector2i(int(k.get("first", 0)), int(k.get("second", 0)))] = int(k.get("amount", 0))
	var pen := margin
	var prev := -1
	for i in txt.length():
		var code := txt.unicode_at(i)
		if code == 10:
			pen.x = margin.x; pen.y += lh * s; prev = -1; continue
		var g: Dictionary = data.chars.get(code, data.chars.get(63, {}))
		if g.is_empty(): prev = code; continue
		if prev != -1:
			pen.x += int(kern.get(Vector2i(prev, code), 0)) * s
		var gw := int(g.get("width", 0)); var gh := int(g.get("height", 0))
		if gw > 0 and gh > 0:
			var src := Rect2(int(g.get("x", 0)), int(g.get("y", 0)), gw, gh)
			var dst := Rect2(pen + Vector2(int(g.get("xoffset", 0)), int(g.get("yoffset", 0))) * s, Vector2(gw, gh) * s)
			c.draw_texture_rect_region(data.texture, dst, src)
		pen.x += int(g.get("xadvance", gw)) * s
		prev = code
	# caret-ish baseline hint
	c.draw_line(Vector2(margin.x, margin.y + int(data.common.get("base", lh)) * s), Vector2(c.size.x - 8, margin.y + int(data.common.get("base", lh)) * s), Color(1, 1, 1, 0.08), 1.0)

func _on_save_fnt() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	if data.fnt_path == "":
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.filters = PackedStringArray(["*.fnt ; BMFont"])
		dlg.current_file = (str(data.info.get("face", "font")) + ".fnt")
		add_child(dlg)
		dlg.file_selected.connect(func(p):
			data.fnt_path = p
			if data.image_path == "":
				data.image_path = p.get_basename() + ".png"
			_do_save_fnt()
			dlg.queue_free()
		)
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered_ratio(0.7)
		return
	_do_save_fnt()

func _do_save_fnt() -> void:
	var err := data.save_fnt(data.fnt_path)
	if err == OK and not data.pages.is_empty():
		data.pages[0]["file"] = data.fnt_path.get_file().get_basename() + ".png"
	_set_status("Saved .fnt to %s" % data.fnt_path if err == OK else "Save failed: %d" % err)

func _on_save_png() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	if data.image_path == "":
		var base := data.fnt_path.get_basename() if data.fnt_path != "" else str(data.info.get("face", "font"))
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.filters = PackedStringArray(["*.png ; PNG Image"])
		dlg.current_file = base.get_file() + ".png"
		add_child(dlg)
		dlg.file_selected.connect(func(p):
			data.image_path = p
			_do_save_png()
			dlg.queue_free()
		)
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered_ratio(0.7)
		return
	_do_save_png()

func _do_save_png() -> void:
	var err := data.save_png(data.image_path)
	_set_status("Saved PNG to %s" % data.image_path if err == OK else "Save failed: %d" % err)

func _on_repack() -> void:
	if data == null or data.image == null: return
	var pad := 1
	var glyphs: Array = []
	for id in data.sorted_char_ids():
		var c: Dictionary = data.chars[id]
		if int(c.get("width", 0)) > 0 and int(c.get("height", 0)) > 0:
			var d := c.duplicate(); d["id"] = id; glyphs.append(d)
	glyphs.sort_custom(func(a, b): return int(a.height) > int(b.height) or (int(a.height) == int(b.height) and int(a.width) > int(b.width)))
	var best: Dictionary = {}
	var best_area := 1 << 60
	var widths := [64, 128, 256, 512, 768, 1024, 1536, 2048, 4096]
	for w in widths:
		var pos := _try_pack(glyphs, w, 4096, pad)
		if pos.is_empty(): continue
		var used_h := 0
		for it in pos:
			used_h = maxi(used_h, int(it.y) + int(it.c.height) + pad)
		var h := 1
		while h < used_h and h < 4096: h *= 2
		h = clampi(h, 1, 4096)
		if used_h > h: continue
		var a: int = w * h
		var aspect := float(maxi(w, h)) / float(maxi(1, mini(w, h)))
		var best_aspect := 999.0
		if not best.is_empty():
			best_aspect = float(maxi(int(best.w), int(best.h))) / float(maxi(1, mini(int(best.w), int(best.h))))
		if best.is_empty() or a < best_area or (a == best_area and aspect < best_aspect):
			best_area = a; best = {"w": w, "h": h, "pos": pos}
	if best.is_empty():
		_set_status("Repack failed: glyphs don't fit in 4096^2"); return
	var nw: int = best.w; var nh: int = best.h
	var img := Image.create(nw, nh, false, data.image.get_format())
	img.fill(Color(0, 0, 0, 0))
	for it in best.pos:
		var id := int(it.c.id)
		var oc: Dictionary = data.chars[id]
		var ox: int = int(oc.get("x", 0)); var oy: int = int(oc.get("y", 0)); var gw: int = int(oc.get("width", 0)); var gh: int = int(oc.get("height", 0))
		if gw > 0 and gh > 0:
			img.blit_rect(data.image, Rect2i(ox, oy, gw, gh), Vector2i(int(it.x), int(it.y)))
		oc["x"] = int(it.x); oc["y"] = int(it.y)
		data.chars[id] = oc
	# zero-size chars parked
	for id in data.chars.keys():
		if int(data.chars[id].get("width", 0)) <= 0 or int(data.chars[id].get("height", 0)) <= 0:
			data.chars[id]["x"] = 0; data.chars[id]["y"] = 0
	data.image = img
	data.texture = ImageTexture.create_from_image(img)
	data.common["scaleW"] = nw; data.common["scaleH"] = nh
	atlas.queue_redraw(); preview_canvas.queue_redraw(); _refresh_stats()
	_set_status("Repacked atlas to %dx%d (%d glyphs)" % [nw, nh, glyphs.size()])

func _try_pack(glyphs: Array, W: int, H: int, pad: int) -> Array:
	var x := pad; var y := pad; var row_h := 0
	var out := []
	for g in glyphs:
		var gw := int(g.width); var gh := int(g.height)
		if x + gw + pad > W:
			x = pad; y += row_h + pad; row_h = 0
		if y + gh + pad > H:
			return []
		out.append({"c": g, "x": x, "y": y})
		x += gw + pad
		row_h = maxi(row_h, gh)
	return out

func _alpha_bounds_in_rect(r: Rect2i) -> Rect2i:
	if data == null or data.image == null: return r
	var rx := clampi(r.position.x, 0, data.image.get_width() - 1)
	var ry := clampi(r.position.y, 0, data.image.get_height() - 1)
	var rw := clampi(r.size.x, 0, data.image.get_width() - rx)
	var rh := clampi(r.size.y, 0, data.image.get_height() - ry)
	if rw <= 0 or rh <= 0: return Rect2i(rx, ry, 0, 0)
	var minx := rx + rw; var miny := ry + rh; var maxx := rx - 1; var maxy := ry - 1
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			var a := data.image.get_pixel(x, y).a
			if a > 0.01:
				minx = mini(minx, x); miny = mini(miny, y); maxx = maxi(maxx, x); maxy = maxi(maxy, y)
	if maxx < minx:
		return Rect2i(rx, ry, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

func _on_autoslice_selected() -> void:
	if sel_id == -1 or not data.chars.has(sel_id): _set_status("Select a glyph first"); return
	var c: Dictionary = data.chars[sel_id]
	var r := Rect2i(int(c.get("x", 0)), int(c.get("y", 0)), int(c.get("width", 0)), int(c.get("height", 0)))
	var nb := _alpha_bounds_in_rect(r)
	c["x"] = nb.position.x; c["y"] = nb.position.y; c["width"] = nb.size.x; c["height"] = nb.size.y
	data.chars[sel_id] = c
	_on_glyph_changed(sel_id); atlas.queue_redraw(); _set_status("Auto-sliced glyph %d to alpha bounds" % sel_id)

func _on_autoslice_all() -> void:
	if data == null or data.image == null: return
	var n := 0
	for id in data.sorted_char_ids():
		var c: Dictionary = data.chars[id]
		var r := Rect2i(int(c.get("x", 0)), int(c.get("y", 0)), int(c.get("width", 0)), int(c.get("height", 0)))
		if r.size.x <= 0 or r.size.y <= 0: continue
		var nb := _alpha_bounds_in_rect(r)
		c["x"] = nb.position.x; c["y"] = nb.position.y; c["width"] = nb.size.x; c["height"] = nb.size.y
		data.chars[id] = c; n += 1
	atlas.queue_redraw(); preview_canvas.queue_redraw(); _refresh_stats(); _sync_props()
	_set_status("Auto-sliced %d glyphs to alpha bounds" % n)

func _add_kern(a: String, b: String, amount: int) -> void:
	if a.is_empty() or b.is_empty(): return
	var fa := a.unicode_at(0); var fb := b.unicode_at(0)
	for k in data.kernings:
		if int(k.get("first", 0)) == fa and int(k.get("second", 0)) == fb:
			k["amount"] = amount; _refresh_kern(); preview_canvas.queue_redraw(); _set_status("Updated kerning %s,%s=%d" % [a.substr(0, 1), b.substr(0, 1), amount]); return
	data.kernings.append({"first": fa, "second": fb, "amount": amount})
	_refresh_kern(); preview_canvas.queue_redraw(); _refresh_stats(); _set_status("Added kerning %s,%s=%d" % [a.substr(0, 1), b.substr(0, 1), amount])

func _remove_kern() -> void:
	var sel := kern_list.get_selected_items()
	if sel.is_empty(): return
	var meta = kern_list.get_item_metadata(sel[0])
	data.kernings.erase(meta)
	_refresh_kern(); preview_canvas.queue_redraw(); _refresh_stats(); _set_status("Removed kerning pair")

func _on_import_image() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.png ; PNG Image"])
	add_child(dlg)
	dlg.file_selected.connect(func(p): _import_image(p); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _import_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		_set_status("Failed to load image: %s" % path); return
	data.clear()
	data.image = img
	data.texture = ImageTexture.create_from_image(img)
	data.image_path = path
	data.fnt_path = path.get_basename() + ".fnt"
	data.info = {"face": path.get_file().get_basename(), "size": 16}
	data.common = {"lineHeight": 16, "base": 12, "scaleW": img.get_width(), "scaleH": img.get_height(), "pages": 1}
	data.pages = [ {"id": 0, "file": path.get_file()}]
	var rects := _detect_glyph_rects(img)
	# sort by top-left reading order
	rects.sort_custom(func(a, b): return (a.position.y / 16) < (b.position.y / 16) or ((a.position.y / 16) == (b.position.y / 16) and a.position.x < b.position.x))
	var id := 32
	for r in rects:
		data.chars[id] = {"id": id, "x": r.position.x, "y": r.position.y, "width": r.size.x, "height": r.size.y, "xoffset": 0, "yoffset": 0, "xadvance": r.size.x + 1, "page": 0, "chnl": 15}
		id += 1
	if data.chars.is_empty():
		# fallback single glyph covering image bounds? no, just report
		_set_status("Imported image but detected no glyph blobs (check alpha).");
	else:
		# heuristic lineHeight/base
		var max_h := 0
		for cid in data.chars.keys(): max_h = maxi(max_h, int(data.chars[cid].height))
		data.common["lineHeight"] = maxi(1, max_h)
		data.common["base"] = maxi(1, max_h - 2)
		_set_status("Imported %s: detected %d glyph regions (assigned ids from 32). Review/adjust as needed." % [path.get_file(), data.chars.size()])
	_apply_texture_filter(0)
	atlas.set_data(data)
	_updating_ui = true
	font_line_h.value = int(data.common.get("lineHeight", 16))
	font_base.value = int(data.common.get("base", 12))
	_updating_ui = false
	_refresh_glyph_list(); _refresh_kern(); _refresh_stats()
	preview_canvas.queue_redraw(); atlas.queue_redraw()

func _detect_glyph_rects(img: Image) -> Array[Rect2i]:
	var w := img.get_width(); var h := img.get_height()
	var visited := PackedByteArray(); visited.resize(w * h)
	var rects: Array[Rect2i] = []
	for y in h:
		for x in w:
			var idx := y * w + x
			if visited[idx]: continue
			if img.get_pixel(x, y).a <= 0.05:
				visited[idx] = 1; continue
			# BFS blob
			var q: Array[Vector2i] = [Vector2i(x, y)]
			visited[idx] = 1
			var head := 0
			var minx := x; var miny := y; var maxx := x; var maxy := y
			while head < q.size():
				var p: Vector2i = q[head]; head += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = p.x + d.x; var ny: int = p.y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var nidx := ny * w + nx
					if visited[nidx]: continue
					if img.get_pixel(nx, ny).a <= 0.05:
						visited[nidx] = 1; continue
					visited[nidx] = 1
					q.append(Vector2i(nx, ny))
					minx = mini(minx, nx); miny = mini(miny, ny); maxx = maxi(maxx, nx); maxy = maxi(maxy, ny)
			rects.append(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))
	return rects

func _example_paths() -> Dictionary:
	return {
		1: "res://fnt/Venice16.fnt",
		2: "res://fnt/SuperBlack12.fnt",
		3: "res://fnt/SuperWhite12.fnt",
	}

func _on_load_example(id: int) -> void:
	if id <= 0: return
	var path: String = _example_paths().get(id, "")
	if path == "": return
	var abs_path := ProjectSettings.globalize_path(path)
	var try_path := abs_path if FileAccess.file_exists(abs_path) else path
	_load_font(try_path)
	if data == null or data.image == null:
		# fallback: try the other form
		var alt := path if try_path == abs_path else abs_path
		_load_font(alt)

func _on_apply_example(idx: int) -> void:
	# 0 none, 1 V@1,2 V@2,3 B@1,4 B@2,5 W@1,6 W@2
	var theme_map := {
		1: "res://theme/venice16_x1.tres",
		2: "res://theme/venice16_x2.tres",
		3: "res://theme/superblack12_x1.tres",
		4: "res://theme/superblack12_x2.tres",
		5: "res://theme/superwhite12_x1.tres",
		6: "res://theme/superwhite12_x2.tres",
	}
	if idx == 0 or not theme_map.has(idx):
		# None: use an empty theme so the editor shows Godot's default UI (not the project custom theme)
		theme = Theme.new()
		if preview_edit:
			preview_edit.remove_theme_font_override("font")
			preview_edit.remove_theme_font_size_override("font_size")
		_clear_ui_tint()
		preview_scale = 1.0
		preview_canvas.queue_redraw()
		_save_apply_settings(0)
		_set_status("Applied no theme (Godot default)")
		return
	var tpath: String = theme_map[idx]
	var t: Theme = null
	if ResourceLoader.exists(tpath):
		t = load(tpath)
	if t:
		theme = t
	else:
		# fallback: build at runtime
		t = Theme.new()
		var fpath := "res://fnt/Venice16.fnt"
		var sz := 16
		match idx:
			2: fpath = "res://fnt/Venice16.fnt"; sz = 32
			3: fpath = "res://fnt/SuperBlack12.fnt"; sz = 12
			4: fpath = "res://fnt/SuperBlack12.fnt"; sz = 24
			5: fpath = "res://fnt/SuperWhite12.fnt"; sz = 12
			6: fpath = "res://fnt/SuperWhite12.fnt"; sz = 24
		if ResourceLoader.exists(fpath):
			t.default_font = load(fpath)
		t.default_font_size = sz
		theme = t
	if preview_edit:
		preview_edit.remove_theme_font_override("font")
		preview_edit.remove_theme_font_size_override("font_size")
	_apply_ui_tint()
	# keep canvas preview scale in sync with selection (1x for odd, 2x for even >0)
	preview_scale = 2.0 if idx % 2 == 0 else 1.0
	preview_canvas.queue_redraw()
	_save_apply_settings(idx)
	_set_status("Applied theme to root: %s" % tpath.get_file())

func _load_apply_settings() -> void:
	var cfg := ConfigFile.new()
	var idx := 1
	if cfg.load(SETTINGS_PATH) == OK:
		idx = int(cfg.get_value(SETTINGS_UI_SECTION, SETTINGS_APPLY_DEMO_KEY, 1))
	if apply_dd == null:
		return
	var sel := apply_dd.get_item_index(idx)
	if sel < 0:
		idx = 1
		sel = apply_dd.get_item_index(idx)
	if sel >= 0:
		apply_dd.select(sel)
	_on_apply_example(idx)

func _save_apply_settings(idx: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_UI_SECTION, SETTINGS_APPLY_DEMO_KEY, idx)
	cfg.save(SETTINGS_PATH)

func _on_import_ttf() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.ttf,*.otf ; Font"])
	add_child(dlg)
	dlg.file_selected.connect(func(p): dlg.queue_free(); _show_ttf_options(p))
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _show_ttf_options(font_path: String) -> void:
	var saved := _load_ttf_import_settings()
	var d := AcceptDialog.new()
	d.title = "Import TTF/OTF"
	d.dialog_hide_on_ok = false

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	d.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	var grid := GridContainer.new(); grid.columns = 2; vb.add_child(grid)
	grid.add_child(_lbl("Size")); var sz := SpinBox.new(); sz.min_value = 6; sz.max_value = 128; sz.value = int(saved.get("size", 16)); sz.step = 1; grid.add_child(sz)
	grid.add_child(_lbl("Filter")); var filt := OptionButton.new(); filt.add_item("Nearest (pixel)", 0); filt.add_item("Linear (smooth)", 1); filt.select(clampi(int(saved.get("filter", 0)), 0, 1)); grid.add_child(filt)
	grid.add_child(_lbl("Outline (px)")); var outline_sz := SpinBox.new(); outline_sz.min_value = 0; outline_sz.max_value = 8; outline_sz.value = int(saved.get("outline", 0)); outline_sz.step = 1; grid.add_child(outline_sz)
	grid.add_child(_lbl("Outline color")); var outline_col := ColorPickerButton.new(); outline_col.color = saved.get("outline_color", Color.BLACK); outline_col.custom_minimum_size = Vector2(120, 0); grid.add_child(outline_col)
	grid.add_child(_lbl("Fill")); var fill_mode := OptionButton.new(); fill_mode.add_item("Solid", 0); fill_mode.add_item("Gradient", 1); fill_mode.add_item("Stamp (image)", 2); fill_mode.add_item("Procedural", 3); fill_mode.select(clampi(int(saved.get("fill_mode", 0)), 0, 3)); grid.add_child(fill_mode)
	grid.add_child(_lbl("Gradient")); var grad_dir := OptionButton.new(); grad_dir.add_item("Vertical (top-bottom)", 1); grad_dir.add_item("Horizontal (left-right)", 2); grad_dir.add_item("Diagonal (TL-BR)", 3); grad_dir.add_item("Diagonal (TR-BL)", 4); grad_dir.select(clampi(int(saved.get("gradient_dir", 1)), 1, 4)); grid.add_child(grad_dir)
	grid.add_child(_lbl("Gradient from")); var grad_c1 := ColorPickerButton.new(); grad_c1.color = saved.get("gradient_color1", Color.WHITE); grad_c1.custom_minimum_size = Vector2(120, 0); grid.add_child(grad_c1)
	grid.add_child(_lbl("Gradient to")); var grad_c2 := ColorPickerButton.new(); grad_c2.color = saved.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0)); grad_c2.custom_minimum_size = Vector2(120, 0); grid.add_child(grad_c2)
	grid.add_child(_lbl("Stamp image")); var stamp_row := HBoxContainer.new(); stamp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var stamp_path := LineEdit.new(); stamp_path.text = str(saved.get("stamp_path", "")); stamp_path.placeholder_text = "Path to image (png, jpg, webp...)"; stamp_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stamp_row.add_child(stamp_path); var stamp_browse := Button.new(); stamp_browse.text = "Browse…"; stamp_row.add_child(stamp_browse); grid.add_child(stamp_row)
	grid.add_child(_lbl("Stamp mapping")); var stamp_tile := OptionButton.new(); stamp_tile.add_item("Tile", 0); stamp_tile.add_item("Fit to glyph", 1); stamp_tile.select(0 if bool(saved.get("stamp_tile", true)) else 1); grid.add_child(stamp_tile)
	grid.add_child(_lbl("Procedural effect")); var proc_effect := OptionButton.new(); proc_effect.add_item("Scanlines", 0); proc_effect.add_item("Bayer dither", 1); proc_effect.add_item("Checker", 2); proc_effect.add_item("Noise grain", 3); proc_effect.add_item("Edge tint / bevel", 4); proc_effect.select(clampi(int(saved.get("proc_effect", 0)), 0, 4)); grid.add_child(proc_effect)
	grid.add_child(_lbl("Procedural color")); var proc_color := ColorPickerButton.new(); proc_color.color = saved.get("proc_color", Color.WHITE); proc_color.custom_minimum_size = Vector2(120, 0); grid.add_child(proc_color)
	grid.add_child(_lbl("Charset")); var chars := TextEdit.new(); chars.text = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"; chars.custom_minimum_size = Vector2(420, 80); chars.size_flags_vertical = Control.SIZE_FILL; chars.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; grid.add_child(chars)

	var info := Label.new(); info.text = "Rasterizes glyphs into a new bitmap atlas. Filter affects preview/texture sampling; outline, gradient, image stamps, and procedural effects are baked into the atlas (tinting visible glyph pixels). Settings are remembered for next time."; info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; vb.add_child(info)

	var stamp_fd := FileDialog.new(); stamp_fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; stamp_fd.access = FileDialog.ACCESS_FILESYSTEM; stamp_fd.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp ; Image files"]); stamp_fd.title = "Choose Stamp Image"
	stamp_fd.file_selected.connect(func(path): stamp_path.text = path)
	d.add_child(stamp_fd)
	stamp_browse.pressed.connect(func(): stamp_fd.popup_centered(Vector2i(700, 500)))

	add_child(d)
	d.confirmed.connect(func():
		var opts := {
			"size": int(sz.value),
			"charset": chars.text,
			"filter": int(filt.get_selected_id()),
			"outline": int(outline_sz.value),
			"outline_color": outline_col.color,
			"fill_mode": int(fill_mode.get_selected_id()),
			"gradient_dir": int(grad_dir.get_selected_id()),
			"gradient_color1": grad_c1.color,
			"gradient_color2": grad_c2.color,
			"stamp_path": stamp_path.text.strip_edges(),
			"stamp_tile": stamp_tile.get_selected_id() == 0,
			"proc_effect": int(proc_effect.get_selected_id()),
			"proc_color": proc_color.color,
		}
		_save_ttf_import_settings(opts)
		d.queue_free()
		_import_ttf(font_path, opts)
	)
	d.canceled.connect(func(): d.queue_free())

	var vp_size := get_viewport_rect().size
	var target_w := mini(640, int(vp_size.x * 0.9))
	var target_h := mini(460, int(vp_size.y * 0.85))
	d.popup_centered(Vector2i(maxi(target_w, 320), maxi(target_h, 240)))

func _import_ttf(font_path: String, opts: Dictionary) -> void:
	var font_size: int = int(opts.get("size", 16))
	var charset: String = str(opts.get("charset", ""))
	var filter_mode: int = int(opts.get("filter", 0))
	var outline_px: int = int(opts.get("outline", 0))
	var outline_color: Color = opts.get("outline_color", Color.BLACK)
	var fill_mode: int = int(opts.get("fill_mode", 0))
	var gradient_dir: int = int(opts.get("gradient_dir", 1))
	var gradient_color1: Color = opts.get("gradient_color1", Color.WHITE)
	var gradient_color2: Color = opts.get("gradient_color2", Color.WHITE)
	var stamp_path: String = str(opts.get("stamp_path", "")).strip_edges()
	var stamp_tile: bool = bool(opts.get("stamp_tile", true))
	var proc_effect: int = int(opts.get("proc_effect", 0))
	var proc_color: Color = opts.get("proc_color", Color.WHITE)
	var stamp_img: Image = null
	if fill_mode == 2 and stamp_path != "":
		stamp_img = Image.new()
		var serr := stamp_img.load(stamp_path)
		if serr != OK:
			_set_status("Failed to load stamp image: %s" % stamp_path)
			stamp_img = null
	if fill_mode == 2 and stamp_img == null:
		_set_status("Stamp fill selected but no valid stamp image; using solid fill.")
		fill_mode = 0
	var font := FontFile.new()
	var err := font.load_dynamic_font(font_path)
	if err != OK:
		# try loading as resource/data
		var bytes := FileAccess.get_file_as_bytes(font_path)
		if bytes.size() == 0:
			_set_status("Failed to load TTF/OTF: %s" % font_path); return
		font.data = bytes
	var unique: Dictionary = {}
	var order: Array[int] = []
	for i in charset.length():
		var cp := charset.unicode_at(i)
		if cp == 10: continue
		if not unique.has(cp):
			unique[cp] = true; order.append(cp)
	if order.is_empty():
		for cp in range(32, 127): order.append(cp)
	# measure glyphs and render via SubViewport
	await get_tree().process_frame
	var pad := 2
	var entries: Array = []
	# collect metrics using font
	for cp in order:
		var ch := String.chr(cp)
		var adv := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var xadv := int(ceil(adv.x)) + outline_px * 2
		if xadv <= 0: xadv = int(font_size / 2.0)
		entries.append({"cp": cp, "ch": ch, "xadv": xadv})
	# render in batches to get images: use one SubViewport and draw each char
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ci := Control.new()
	ci.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ci)
	ci.draw.connect(func(): _draw_ttf_probe(ci))
	var rendered: Array = [] # {cp,xadv,img,ox,oy}
	var margin := int(font_size) + outline_px + 2
	for e in entries:
		var cw := int(font_size * 2) + margin * 2 + outline_px * 4
		var chh := int(font_size * 2) + margin * 2 + outline_px * 4
		vp.size = Vector2i(cw, chh)
		ci.set_meta("ds", {"font": font, "cp": e.cp, "size": font_size, "margin": margin, "outline": outline_px, "outline_color": outline_color})
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		ci.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tex := vp.get_texture()
		if tex == null:
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": 0, "h": 0, "img": null, "ox": 0, "oy": 0})
			continue
		var img := tex.get_image()
		if img == null:
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": 0, "h": 0, "img": null, "ox": 0, "oy": 0})
			continue
		var b := _alpha_bounds(img)
		if b.size.x <= 0 or b.size.y <= 0:
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": 0, "h": 0, "img": null, "ox": 0, "oy": 0})
		else:
			if fill_mode == 1:
				_apply_gradient_to_bounds(img, b, gradient_dir, gradient_color1, gradient_color2)
			elif fill_mode == 2 and stamp_img != null:
				_apply_stamp_to_bounds(img, b, stamp_img, stamp_tile)
			elif fill_mode == 3:
				_apply_procedural_to_bounds(img, b, proc_effect, proc_color)
			var sub := img.get_region(b)
			var ox := b.position.x - margin
			var oy := b.position.y - margin
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": b.size.x, "h": b.size.y, "img": sub, "ox": ox, "oy": oy})
	vp.queue_free()
	_pack_rendered_font(font_path.get_file().get_basename(), font_size, rendered, pad, filter_mode)

func _draw_ttf_probe(ci: Control) -> void:
	if not ci.has_meta("ds"): return
	var ds: Dictionary = ci.get_meta("ds")
	var font: Font = ds.font
	var cp: int = ds.cp
	var fsize: int = ds.size
	var margin: int = ds.margin
	var outline: int = int(ds.get("outline", 0))
	var outline_color: Color = ds.get("outline_color", Color.BLACK)
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0, 0, 0, 0))
	# draw baseline at margin+size
	var baseline := Vector2(margin, margin + fsize)
	var ch := String.chr(cp)
	if outline > 0:
		for oy in range(-outline, outline + 1):
			for ox in range(-outline, outline + 1):
				if ox == 0 and oy == 0: continue
				if ox * ox + oy * oy > outline * outline: continue
				ci.draw_char(font, baseline + Vector2(ox, oy), ch, fsize, outline_color)
	ci.draw_char(font, baseline, ch, fsize, Color.WHITE)

func _alpha_bounds(img: Image) -> Rect2i:
	var w := img.get_width(); var h := img.get_height()
	var minx := w; var miny := h; var maxx := -1; var maxy := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.01:
				if x < minx: minx = x
				if y < miny: miny = y
				if x > maxx: maxx = x
				if y > maxy: maxy = y
	if maxx < minx:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

func _apply_gradient_to_bounds(img: Image, b: Rect2i, dir: int, c1: Color, c2: Color) -> void:
	if b.size.x <= 0 or b.size.y <= 0: return
	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			var p := img.get_pixel(x, y)
			if p.a <= 0.01:
				continue
			var t := 0.0
			if dir == 1: # vertical
				t = 0.0 if b.size.y <= 1 else float(y - b.position.y) / float(b.size.y - 1)
			elif dir == 2: # horizontal
				t = 0.0 if b.size.x <= 1 else float(x - b.position.x) / float(b.size.x - 1)
			elif dir == 3: # diagonal TL -> BR
				var tx := 0.0 if b.size.x <= 1 else float(x - b.position.x) / float(b.size.x - 1)
				var ty := 0.0 if b.size.y <= 1 else float(y - b.position.y) / float(b.size.y - 1)
				t = (tx + ty) * 0.5
			elif dir == 4: # diagonal TR -> BL
				var tx := 0.0 if b.size.x <= 1 else float(x - b.position.x) / float(b.size.x - 1)
				var ty := 0.0 if b.size.y <= 1 else float(y - b.position.y) / float(b.size.y - 1)
				t = ((1.0 - tx) + ty) * 0.5
			var gc: Color = c1.lerp(c2, clampf(t, 0.0, 1.0))
			img.set_pixel(x, y, Color(gc.r, gc.g, gc.b, p.a))

func _apply_stamp_to_bounds(img: Image, b: Rect2i, stamp: Image, tile: bool) -> void:
	if b.size.x <= 0 or b.size.y <= 0: return
	var sw := stamp.get_width()
	var sh := stamp.get_height()
	if sw <= 0 or sh <= 0:
		return
	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			var p := img.get_pixel(x, y)
			if p.a <= 0.01:
				continue
			var sx: int
			var sy: int
			if tile:
				sx = posmod(x, sw)
				sy = posmod(y, sh)
			else:
				sx = 0 if b.size.x <= 1 else int(round(float(x - b.position.x) / float(b.size.x - 1) * float(sw - 1)))
				sy = 0 if b.size.y <= 1 else int(round(float(y - b.position.y) / float(b.size.y - 1) * float(sh - 1)))
			var sc := stamp.get_pixel(clampi(sx, 0, sw - 1), clampi(sy, 0, sh - 1))
			# "Stamp" onto glyph: use stamp color, preserve glyph alpha (baked like gradients).
			img.set_pixel(x, y, Color(sc.r, sc.g, sc.b, p.a))

func _apply_procedural_to_bounds(img: Image, b: Rect2i, effect: int, tint: Color) -> void:
	if b.size.x <= 0 or b.size.y <= 0:
		return
	# 4x4 Bayer matrix normalized to [0,1)
	var bayer := [
		0.0/16.0, 8.0/16.0, 2.0/16.0, 10.0/16.0,
		12.0/16.0, 4.0/16.0, 14.0/16.0, 6.0/16.0,
		3.0/16.0, 11.0/16.0, 1.0/16.0, 9.0/16.0,
		15.0/16.0, 7.0/16.0, 13.0/16.0, 5.0/16.0,
	]
	var w := img.get_width()
	var h := img.get_height()
	# Precompute a simple edge-distance approximation for bevel/edge tint.
	var edge_dist: Dictionary = {}
	if effect == 4:
		for y in range(b.position.y, b.position.y + b.size.y):
			for x in range(b.position.x, b.position.x + b.size.x):
				if img.get_pixel(x, y).a <= 0.01:
					continue
				var d := 99
				# Manhattan-ish search radius 3 for a cheap inner distance estimate.
				for r in range(1, 4):
					var on_edge := false
					var nx: Array[int] = [x - r, x + r, x, x]
					var ny: Array[int] = [y, y, y - r, y + r]
					for i in 4:
						var px: int = nx[i]
						var py: int = ny[i]
						if px < 0 or py < 0 or px >= w or py >= h or img.get_pixel(px, py).a <= 0.01:
							on_edge = true
							break
					if on_edge:
						d = r
						break
				edge_dist[Vector2i(x, y)] = d

	for y in range(b.position.y, b.position.y + b.size.y):
		for x in range(b.position.x, b.position.x + b.size.x):
			var p := img.get_pixel(x, y)
			if p.a <= 0.01:
				continue
			var lx := x - b.position.x
			var ly := y - b.position.y
			var out := Color(tint.r, tint.g, tint.b, p.a)
			if effect == 0:
				# Scanlines: darken every other row.
				var s := 0.55 if (posmod(y, 2) == 0) else 1.0
				out = Color(tint.r * s, tint.g * s, tint.b * s, p.a)
			elif effect == 1:
				# Ordered (Bayer) dither: modulate brightness by threshold pattern.
				var m :int= bayer[posmod(ly, 4) * 4 + posmod(lx, 4)]
				var s := 0.45 + 0.55 * m
				out = Color(tint.r * s, tint.g * s, tint.b * s, p.a)
			elif effect == 2:
				# Checker pattern.
				var s := 1.0 if ((posmod(lx, 2) + posmod(ly, 2)) % 2 == 0) else 0.45
				out = Color(tint.r * s, tint.g * s, tint.b * s, p.a)
			elif effect == 3:
				# Noise grain: deterministic pseudo-random per pixel.
				var n := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
				var s := 0.7 + 0.3 * n
				out = Color(clampf(tint.r * s, 0.0, 1.0), clampf(tint.g * s, 0.0, 1.0), clampf(tint.b * s, 0.0, 1.0), p.a)
			elif effect == 4:
				# Edge tint / bevel approximation: lighten near edges, darken interior.
				var d: int = int(edge_dist.get(Vector2i(x, y), 99))
				var s := 1.0
				if d <= 1:
					s = 1.35
				elif d == 2:
					s = 1.1
				else:
					s = 0.85
				# Blend toward tint so "Procedural color" influences the result.
				var base := Color(tint.r, tint.g, tint.b, p.a)
				out = Color(clampf(base.r * s, 0.0, 1.0), clampf(base.g * s, 0.0, 1.0), clampf(base.b * s, 0.0, 1.0), p.a)
			img.set_pixel(x, y, out)

func _pack_rendered_font(font_face: String, font_size: int, rendered: Array, pad: int, filter_mode: int = 0) -> void:
	var glyphs: Array = []
	for r in rendered:
		if int(r.w) > 0 and int(r.h) > 0:
			glyphs.append(r)
	glyphs.sort_custom(func(a, b): return int(a.h) > int(b.h) or (int(a.h) == int(b.h) and int(a.w) > int(b.w)))
	var best := {}
	var best_area := 1 << 60
	for w in [64, 128, 256, 512, 768, 1024, 2048]:
		var pos := _try_pack_ttf(glyphs, w, 4096, pad)
		if pos.is_empty(): continue
		var used_h := 0
		for it in pos:
			used_h = maxi(used_h, int(it.y) + int(it.c.h) + pad)
		var h := 1
		while h < used_h and h < 4096: h *= 2
		h = clampi(h, 1, 4096)
		if used_h > h: continue
		var a: int = w * h
		var aspect := float(maxi(w, h)) / float(maxi(1, mini(w, h)))
		var best_aspect := 999.0
		if not best.is_empty():
			best_aspect = float(maxi(int(best.w), int(best.h))) / float(maxi(1, mini(int(best.w), int(best.h))))
		if best.is_empty() or a < best_area or (a == best_area and aspect < best_aspect):
			best_area = a; best = {"w": w, "h": h, "pos": pos}
	if best.is_empty():
		_set_status("TTF import failed: could not pack atlas"); return
	var nw: int = best.w; var nh: int = best.h
	var img := Image.create(nw, nh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	data.clear()
	data.image = img
	data.image_path = ""
	data.fnt_path = ""
	data.info = {"face": font_face, "size": font_size}
	data.common = {"lineHeight": font_size, "base": int(font_size * 0.8), "scaleW": nw, "scaleH": nh, "pages": 1}
	data.pages = [ {"id": 0, "file": font_face + ".png"}]
	for it in best.pos:
		var r: Dictionary = it.c
		if r.img != null:
			img.blit_rect(r.img, Rect2i(Vector2i.ZERO, r.img.get_size()), Vector2i(int(it.x), int(it.y)))
		var cp := int(r.cp)
		data.chars[cp] = {"id": cp, "x": int(it.x), "y": int(it.y), "width": int(r.w), "height": int(r.h), "xoffset": int(r.ox), "yoffset": int(r.oy), "xadvance": int(r.xadv), "page": 0, "chnl": 15}
	# include empty glyphs (space etc.)
	for r in rendered:
		var cp := int(r.cp)
		if data.chars.has(cp): continue
		data.chars[cp] = {"id": cp, "x": 0, "y": 0, "width": 0, "height": 0, "xoffset": 0, "yoffset": 0, "xadvance": int(r.xadv), "page": 0, "chnl": 15}
	data.texture = ImageTexture.create_from_image(img)
	_apply_texture_filter(filter_mode)
	atlas.set_data(data)
	_updating_ui = true
	font_line_h.value = int(data.common.get("lineHeight", font_size))
	font_base.value = int(data.common.get("base", int(font_size * 0.8)))
	_updating_ui = false
	_refresh_glyph_list(); _refresh_kern(); _refresh_stats()
	preview_canvas.queue_redraw(); atlas.queue_redraw()
	var filt_name := "Nearest" if filter_mode == 0 else "Linear"
	_set_status("Imported TTF/OTF '%s' at size %d: %d glyphs rasterized (%s filter)" % [font_face, font_size, data.chars.size(), filt_name])

func _try_pack_ttf(glyphs: Array, W: int, H: int, pad: int) -> Array:
	var x := pad; var y := pad; var row_h := 0
	var out := []
	for g in glyphs:
		var gw := int(g.w); var gh := int(g.h)
		if x + gw + pad > W:
			x = pad; y += row_h + pad; row_h = 0
		if y + gh + pad > H:
			return []
		out.append({"c": g, "x": x, "y": y})
		x += gw + pad
		row_h = maxi(row_h, gh)
	return out
