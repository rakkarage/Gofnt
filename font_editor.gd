@tool
extends PanelContainer

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "window"
const SETTINGS_FULLSCREEN_KEY := "fullscreen"
const SETTINGS_TTF_SECTION := "ttf_import"
const SETTINGS_UI_SECTION := "ui"
const SETTINGS_APPLY_DEMO_KEY := "apply_demo"
const SETTINGS_FILEDIALOG_SECTION := "file_dialog"
const SETTINGS_FILEDIALOG_FAVORITES_KEY := "favorites"

var data: BMFontData
@onready var atlas: Control = $Main/Left/Atlas
@onready var glyph_list: ItemList = $Main/Tabs/Glyph/GlyphList
@onready var glyph_jump_edit: LineEdit = $Main/Tabs/Glyph/AddRow/GlyphJumpEdit
@onready var status_lbl: Label = $Main/Left/StatusLbl
@onready var preview_edit: TextEdit = $Main/Left/PreviewEdit
@onready var stats_lbl: RichTextLabel = $Main/Tabs/FontStats/StatsLbl
@onready var preview_lbl: Label = $Main/Left/PreviewLbl
var load_demo_lbl: Label
var apply_demo_lbl: Label
var import_demo_lbl: Label
@onready var kern_list: ItemList = $Main/Tabs/Kerning/KernList
var prop_spin: Dictionary = {}
@onready var font_line_h: SpinBox = $Main/Tabs/FontStats/FontGrid/FontLineH
@onready var font_base: SpinBox = $Main/Tabs/FontStats/FontGrid/FontBase
@onready var glyph_action_btn: Button = $Main/Tabs/Glyph/GlyphActionBtn
@onready var fullscreen_cb: CheckBox = $Main/Left/Toolbar/FullscreenCb
var apply_dd: OptionButton
var _ttf_font_path: String = ""
@onready var ttf_dialog: AcceptDialog = $TtfDialog
var preview_scale: float = 2.0
var sel_id: int = -1
var _updating_ui := false
var _ui_tinted := false
const STATUS_ERROR_COLOR := Color(1.0, 0.42, 0.42, 1.0)
const STATUS_WARN_COLOR := Color(1.0, 0.82, 0.45, 1.0)

func _ready() -> void:
	name = "Gofnt"
	data = BMFontData.new()
	_bind_ui()
	_apply_ui_tint()
	set_process_unhandled_input(true)
	_apply_project_default_theme()
	_load_window_settings()
	_load_apply_settings()
	_load_file_dialog_favorites()
	_set_status("Drop-ready: use Open .fnt to load a bitmap font (text BMFont) and its atlas PNG.  Toggle Fullscreen with F11 or the checkbox.")

func _apply_project_default_theme() -> void:
	var def_path := str(ProjectSettings.get_setting("gui/theme/custom", "res://theme/venice16_x1.tres"))
	if def_path != "" and ResourceLoader.exists(def_path):
		theme = load(def_path)
	elif ResourceLoader.exists("res://theme/venice16_x1.tres"):
		theme = load("res://theme/venice16_x1.tres")
	_refresh_preview()

func _exit_tree() -> void:
	_save_file_dialog_favorites()

func _unhandled_input(event: InputEvent) -> void:
	# Never toggle window mode from within the Godot editor (tool mode): it would
	# hide the editor's title bar / close buttons and persist into the editor.
	if Engine.is_editor_hint():
		return
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
	if Engine.is_editor_hint():
		# In the editor, never change the editor window's mode; just keep it windowed.
		if win:
			win.mode = Window.MODE_WINDOWED
		return
	if win:
		win.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	if persist:
		_save_window_settings(enabled)

func _load_window_settings() -> void:
	if Engine.is_editor_hint():
		# In the editor, ignore any persisted fullscreen state and force a normal
		# window so the editor's title bar / close buttons stay available.
		var win := get_window()
		if win:
			win.mode = Window.MODE_WINDOWED
		if fullscreen_cb:
			fullscreen_cb.set_pressed_no_signal(false)
			fullscreen_cb.disabled = true
		return
	var cfg := ConfigFile.new()
	var enabled := false
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_FULLSCREEN_KEY, false))
	if fullscreen_cb:
		fullscreen_cb.set_pressed_no_signal(enabled)
	_set_fullscreen(enabled, false)

func _save_window_settings(enabled: bool) -> void:
	if Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_FULLSCREEN_KEY, enabled)
	cfg.save(SETTINGS_PATH)

func _load_file_dialog_favorites() -> void:
	if Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var raw = cfg.get_value(SETTINGS_FILEDIALOG_SECTION, SETTINGS_FILEDIALOG_FAVORITES_KEY, PackedStringArray())
	var favs := PackedStringArray()
	if raw is PackedStringArray:
		favs = raw
	elif raw is Array:
		for v in raw:
			favs.append(str(v))
	FileDialog.set_favorite_list(favs)

func _save_file_dialog_favorites() -> void:
	if Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_FILEDIALOG_SECTION, SETTINGS_FILEDIALOG_FAVORITES_KEY, FileDialog.get_favorite_list())
	cfg.save(SETTINGS_PATH)

func _register_file_dialog(dlg: FileDialog) -> void:
	# Persist favorites (which are only kept in memory by the engine) across runs.
	dlg.file_selected.connect(func(_p): _save_file_dialog_favorites())
	dlg.canceled.connect(func(): _save_file_dialog_favorites())
	var _was_open := [false]
	dlg.visibility_changed.connect(func():
		if dlg.visible:
			_was_open[0] = true
		elif _was_open[0]:
			_was_open[0] = false
			_save_file_dialog_favorites()
	)

func _default_ttf_import_settings() -> Dictionary:
	return {
		"size": 16,
		"filter": 0,
		"outline": 0,
		"outline_color": Color.BLACK,
		"gradient_dir": 1,
		"gradient_color1": Color.WHITE,
		"gradient_color2": Color(0.7, 0.85, 1.0, 1.0),
		"fill_mode": 0, # 0=solid, 1=gradient, 2=stamp(image), 3=procedural
		"stamp_path": "",
		"stamp_tile": true,
		"proc_effect": 0, # 0=scanlines,1=bayer,2=checker,3=noise,4=edge tint/bevel
		"proc_color": Color(1, 1, 1, 1),
		"padding": 0,
		"pack_tiebreaker": 0, # 0=prefer wide, 1=prefer tall
	}

func _load_ttf_import_settings() -> Dictionary:
	var defaults := _default_ttf_import_settings()
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
	defaults["padding"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "padding", defaults["padding"]))
	defaults["pack_tiebreaker"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "pack_tiebreaker", defaults["pack_tiebreaker"]))
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
	cfg.set_value(SETTINGS_TTF_SECTION, "padding", int(opts.get("padding", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "pack_tiebreaker", int(opts.get("pack_tiebreaker", 0)))
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
	_ui_tinted = true
	if status_lbl:
		status_lbl.add_theme_color_override("font_color", _status_normal_color())
	if stats_lbl:
		stats_lbl.add_theme_color_override("default_color", Color(0.9, 0.93, 0.98, 0.95))

func _clear_ui_tint() -> void:
	remove_theme_stylebox_override("panel")
	_ui_tinted = false
	if status_lbl:
		status_lbl.remove_theme_color_override("font_color")
	if stats_lbl:
		stats_lbl.remove_theme_color_override("default_color")
	if load_demo_lbl:
		load_demo_lbl.remove_theme_color_override("font_color")
	if apply_demo_lbl:
		apply_demo_lbl.remove_theme_color_override("font_color")
	if import_demo_lbl:
		import_demo_lbl.remove_theme_color_override("font_color")
	if preview_lbl:
		preview_lbl.remove_theme_color_override("font_color")

func _status_normal_color() -> Color:
	if _ui_tinted:
		var accent := Color(0.45, 0.72, 1.0)
		return Color(0.78, 0.86, 0.96, 0.92).lerp(accent, 0.12)
	return get_theme_color("font_color", "Label") if has_theme_color("font_color", "Label") else Color(0.88, 0.88, 0.88, 1.0)

func _set_status(t: String, is_error: bool = false, is_warn: bool = false) -> void:
	if status_lbl == null:
		return
	status_lbl.text = t
	if is_error:
		status_lbl.add_theme_color_override("font_color", STATUS_ERROR_COLOR)
	elif is_warn:
		status_lbl.add_theme_color_override("font_color", STATUS_WARN_COLOR)
	elif _ui_tinted:
		status_lbl.add_theme_color_override("font_color", _status_normal_color())
	else:
		status_lbl.remove_theme_color_override("font_color")

func _bind_ui() -> void:
	# Scene provides nodes; wire signals here.
	var tabs := $Main/Tabs as TabContainer
	tabs.set_tab_title(0, "Glyph")
	tabs.set_tab_title(1, "Font/Stats")
	tabs.set_tab_title(2, "Kerning")

	# Toolbar buttons
	$Main/Left/Toolbar/OpenBtn.pressed.connect(_on_open)
	$Main/Left/Toolbar/ImportImageBtn.pressed.connect(_on_import_image)
	$Main/Left/Toolbar/ImportTtfBtn.pressed.connect(_on_import_ttf)
	$Main/Left/Toolbar/SaveFntBtn.pressed.connect(_on_save_fnt)
	$Main/Left/Toolbar/SavePngBtn.pressed.connect(_on_save_png)
	$Main/Left/Toolbar/TrimSelectedBtn.pressed.connect(_on_autoslice_selected)
	$Main/Left/Toolbar/TrimAllBtn.pressed.connect(_on_autoslice_all)
	$Main/Left/Toolbar/RepackBtn.pressed.connect(_on_repack)
	fullscreen_cb.toggled.connect(func(pressed: bool): _set_fullscreen(pressed, true))

	atlas.glyph_selected.connect(_on_glyph_selected)
	atlas.glyph_changed.connect(_on_glyph_changed)

	glyph_list.item_selected.connect(_on_list_selected)

	glyph_jump_edit.text_submitted.connect(func(_t): _add_or_select_glyph(glyph_jump_edit.text))

	var add_go_btn := $Main/Tabs/Glyph/AddRow/AddGoBtn as Button
	add_go_btn.pressed.connect(func(): _add_or_select_glyph(glyph_jump_edit.text))

	glyph_action_btn.pressed.connect(_on_glyph_action)

	# prop spin map + connections
	var keys := ["x", "y", "width", "height", "xoffset", "yoffset", "xadvance"]
	for key in keys:
		var spin := get_node("Main/Tabs/Glyph/PropsGrid/PropSpin" + key.capitalize()) as SpinBox
		prop_spin[key] = spin
		spin.value_changed.connect(func(v): _on_prop_changed(key, int(v)))

	font_line_h.value_changed.connect(func(v): if not _updating_ui: data.common["lineHeight"] = int(v); _refresh_preview())
	font_base.value_changed.connect(func(v): if not _updating_ui: data.common["base"] = int(v))

	var bulk_spin := $Main/Tabs/FontStats/BulkRow/BulkSpin as SpinBox
	var bulk_btn := $Main/Tabs/FontStats/BulkRow/BulkApplyBtn as Button
	bulk_btn.pressed.connect(func(): _bulk_advance(int(bulk_spin.value)))

	var kern_first := $Main/Tabs/Kerning/KernRow/KernFirstEdit as LineEdit
	var kern_second := $Main/Tabs/Kerning/KernRow/KernSecondEdit as LineEdit
	var kern_amt := $Main/Tabs/Kerning/KernRow/KernAmountSpin as SpinBox
	var kern_add := $Main/Tabs/Kerning/KernRow/KernAddBtn as Button
	kern_add.pressed.connect(func(): _add_kern(kern_first.text, kern_second.text, int(kern_amt.value)))
	var kern_remove := $Main/Tabs/Kerning/KernRemoveBtn as Button
	kern_remove.pressed.connect(_remove_kern)

	# TTF import dialog
	ttf_dialog.canceled.connect(func(): ttf_dialog.hide())
	var ttf_reset_btn := ttf_dialog.get_node("Scroll/VBox/ResetBtn") as Button
	ttf_reset_btn.pressed.connect(_reset_ttf_dialog)
	ttf_dialog.confirmed.connect(func():
		var g := "Scroll/VBox/Grid/"
		var opts := {
			"size": int((ttf_dialog.get_node(g + "SizeSpin") as SpinBox).value),
			"charset": (ttf_dialog.get_node(g + "CharsetEdit") as TextEdit).text,
			"filter": int((ttf_dialog.get_node(g + "FilterOption") as OptionButton).get_selected_id()),
			"padding": int((ttf_dialog.get_node(g + "PaddingSpin") as SpinBox).value),
			"pack_tiebreaker": int((ttf_dialog.get_node(g + "TieOption") as OptionButton).get_selected_id()),
			"outline": int((ttf_dialog.get_node(g + "OutlineSpin") as SpinBox).value),
			"outline_color": (ttf_dialog.get_node(g + "OutlineColorPicker") as ColorPickerButton).color,
			"fill_mode": int((ttf_dialog.get_node(g + "FillOption") as OptionButton).get_selected_id()),
			"gradient_dir": int((ttf_dialog.get_node(g + "GradientOption") as OptionButton).get_selected_id()),
			"gradient_color1": (ttf_dialog.get_node(g + "GradFromPicker") as ColorPickerButton).color,
			"gradient_color2": (ttf_dialog.get_node(g + "GradToPicker") as ColorPickerButton).color,
			"proc_effect": int((ttf_dialog.get_node(g + "ProcEffectOption") as OptionButton).get_selected_id()),
			"proc_color": (ttf_dialog.get_node(g + "ProcColorPicker") as ColorPickerButton).color,
		}
		_save_ttf_import_settings(opts)
		ttf_dialog.hide()
		_import_ttf(_ttf_font_path, opts)
	)

func _refresh_preview() -> void:
	if preview_edit == null:
		return
	if data == null or data.image == null:
		preview_edit.remove_theme_font_override("font")
		preview_edit.remove_theme_font_size_override("font_size")
		preview_edit.scale = Vector2(preview_scale, preview_scale)
		return
	# Build a scaled copy of the in-memory BMFont data so the editable preview
	# reflects glyph edits live and honors preview_scale (e.g. 2x/4x).
	var s := maxi(1, int(round(preview_scale)))
	var preview_data := BMFontData.new()
	preview_data.info = data.info.duplicate(true)
	if preview_data.info.has("size"):
		preview_data.info["size"] = int(preview_data.info.get("size", 16)) * s
	preview_data.common = data.common.duplicate(true)
	preview_data.pages = data.pages.duplicate(true)
	preview_data.chars = {}
	for id in data.chars.keys():
		var c: Dictionary = (data.chars[id] as Dictionary).duplicate()
		for key in ["x", "y", "width", "height", "xoffset", "yoffset", "xadvance"]:
			c[key] = int(c.get(key, 0)) * s
		preview_data.chars[id] = c
	preview_data.kernings = []
	for k in data.kernings:
		var kk: Dictionary = (k as Dictionary).duplicate()
		kk["amount"] = int(kk.get("amount", 0)) * s
		preview_data.kernings.append(kk)
	var img := data.image.duplicate()
	if s > 1:
		img.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
	preview_data.image = img
	preview_data.texture = ImageTexture.create_from_image(img)
	preview_data.fnt_path = data.fnt_path
	preview_data.image_path = data.image_path
	preview_data.common["lineHeight"] = int(data.common.get("lineHeight", 16)) * s
	preview_data.common["base"] = int(data.common.get("base", 12)) * s
	preview_data.common["scaleW"] = img.get_width()
	preview_data.common["scaleH"] = img.get_height()
	if not preview_data.pages.is_empty():
		preview_data.pages[0]["file"] = "gofnt_preview.png"

	var tmp_fnt := "user://gofnt_preview.fnt"
	var tmp_png := "user://gofnt_preview.png"
	var old_fnt := preview_data.fnt_path
	var old_img := preview_data.image_path
	preview_data.fnt_path = tmp_fnt
	preview_data.image_path = tmp_png
	preview_data.save_fnt(tmp_fnt)
	preview_data.save_png(tmp_png)
	preview_data.fnt_path = old_fnt
	preview_data.image_path = old_img

	var ff := FontFile.new()
	var p := ProjectSettings.globalize_path(tmp_fnt)
	if ff.load_bitmap_font(p) == OK:
		preview_edit.add_theme_font_override("font", ff)
	preview_edit.scale = Vector2.ONE

func _apply_texture_filter(filter_mode: int) -> void:
	var tf := CanvasItem.TEXTURE_FILTER_NEAREST if filter_mode == 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	if preview_edit:
		preview_edit.texture_filter = tf
	if atlas:
		atlas.texture_filter = tf
	# note: BMFont .fnt doesn't store Godot texture filter; this affects editor preview/atlas rendering.

func _on_open() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.fnt ; BMFont"])
	add_child(dlg)
	_register_file_dialog(dlg)
	dlg.file_selected.connect(func(p): _load_font(p); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _load_font(path: String) -> void:
	var err := data.load_fnt(path)
	if err != OK:
		_set_status("Failed to load: %s (err %d)" % [path, err], true); return
	atlas.set_data(data)
	_updating_ui = true
	font_line_h.value = int(data.common.get("lineHeight", 16))
	font_base.value = int(data.common.get("base", 12))
	_updating_ui = false
	_refresh_glyph_list(); _refresh_kern(); _refresh_stats()
	_apply_texture_filter(0)
	_set_status("Loaded %s  |  %d glyphs" % [data.info.get("face", path.get_file()), data.chars.size()])
	_refresh_preview(); atlas.queue_redraw()

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
	_populate_glyph_jump(id)
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
	# Pan the atlas view to the selected glyph so it can be found even after
	# the view was panned/zoomed off-screen.
	atlas.focus_glyph(sel_id)
	_sync_props()
	_populate_glyph_jump(id)

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

func _populate_glyph_jump(id: int) -> void:
	if glyph_jump_edit == null or id < 0:
		return
	if glyph_jump_edit.has_focus():
		return
	if id >= 32 and id <= 126 and id != 32:
		glyph_jump_edit.text = String.chr(id)
	elif id == 32:
		glyph_jump_edit.text = "32"
	else:
		glyph_jump_edit.text = str(id)

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
	_refresh_glyph_list(); _refresh_stats(); atlas.queue_redraw(); _refresh_preview()
	_sync_props()
	# reselect same id in list
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == sel_id:
			glyph_list.select(i); break

func _on_prop_changed(key: String, val: int) -> void:
	if _updating_ui or sel_id == -1 or not data.chars.has(sel_id): return
	data.chars[sel_id][key] = val
	atlas.queue_redraw(); _refresh_preview(); _refresh_stats()

func _on_glyph_changed(_id: int) -> void:
	_sync_props(); _refresh_preview(); _refresh_stats()

func _bulk_advance(delta: int) -> void:
	if data == null: return
	for id in data.chars.keys():
		data.chars[id]["xadvance"] = int(data.chars[id].get("xadvance", 0)) + delta
	_sync_props(); _refresh_glyph_list(); _refresh_preview(); _set_status("Applied xadvance %+d to all glyphs" % delta)

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
		_register_file_dialog(dlg)
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
	_set_status("Saved .fnt to %s" % data.fnt_path if err == OK else "Save failed: %d" % err, err != OK)

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
		_register_file_dialog(dlg)
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
	_set_status("Saved PNG to %s" % data.image_path if err == OK else "Save failed: %d" % err, err != OK)

func _on_repack() -> void:
	if data == null or data.image == null: return
	var pad := 0
	var glyphs: Array = []
	for id in data.sorted_char_ids():
		var c: Dictionary = data.chars[id]
		if int(c.get("width", 0)) > 0 and int(c.get("height", 0)) > 0:
			var d := c.duplicate(); d["id"] = id; glyphs.append(d)
	glyphs.sort_custom(func(a, b): return int(a.height) > int(b.height) or (int(a.height) == int(b.height) and int(a.width) > int(b.width)))
	var prefer_wide := int(_load_ttf_import_settings().get("pack_tiebreaker", 0)) == 0
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
		var score := float(a) * aspect
		var prefer := best.is_empty()
		if not prefer:
			var best_score := float(best_area) * float(maxi(int(best.w), int(best.h))) / float(maxi(1, mini(int(best.w), int(best.h))))
			if score < best_score - 0.0001:
				prefer = true
			elif abs(score - best_score) <= 0.0001:
				if a < best_area:
					prefer = true
				elif a == best_area:
					var best_land: bool = int(best.w) >= int(best.h)
					var cand_land: bool = w >= h
					if cand_land != best_land:
						prefer = cand_land if prefer_wide else not cand_land
		if prefer:
			best_area = a; best = {"w": w, "h": h, "pos": pos}
	if best.is_empty():
		_set_status("Repack failed: glyphs don't fit in 4096^2", true); return
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
	atlas.queue_redraw(); _refresh_preview(); _refresh_stats()
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
	if sel_id == -1 or not data.chars.has(sel_id): _set_status("Select a glyph first", false, true); return
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
	atlas.queue_redraw(); _refresh_preview(); _refresh_stats(); _sync_props()
	_set_status("Auto-sliced %d glyphs to alpha bounds" % n)

func _add_kern(a: String, b: String, amount: int) -> void:
	if a.is_empty() or b.is_empty(): return
	var fa := a.unicode_at(0); var fb := b.unicode_at(0)
	for k in data.kernings:
		if int(k.get("first", 0)) == fa and int(k.get("second", 0)) == fb:
			k["amount"] = amount; _refresh_kern(); _refresh_preview(); _set_status("Updated kerning %s,%s=%d" % [a.substr(0, 1), b.substr(0, 1), amount]); return
	data.kernings.append({"first": fa, "second": fb, "amount": amount})
	_refresh_kern(); _refresh_preview(); _refresh_stats(); _set_status("Added kerning %s,%s=%d" % [a.substr(0, 1), b.substr(0, 1), amount])

func _remove_kern() -> void:
	var sel := kern_list.get_selected_items()
	if sel.is_empty(): return
	var meta = kern_list.get_item_metadata(sel[0])
	data.kernings.erase(meta)
	_refresh_kern(); _refresh_preview(); _refresh_stats(); _set_status("Removed kerning pair")

func _on_import_image() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.png ; PNG Image"])
	add_child(dlg)
	_register_file_dialog(dlg)
	dlg.file_selected.connect(func(p): _import_image(p); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _import_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		_set_status("Failed to load image: %s" % path, true); return
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
	_refresh_preview(); atlas.queue_redraw()

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
		2: "res://fnt/Super12.fnt",
	}

func _on_load_example(id: int) -> void:
	if id <= 0: return
	var path: String = _example_paths().get(id, "")
	if path == "": return
	# Prefer the res:// path directly (works in editor and packed/web exports).
	_load_font(path)
	if data == null or data.image == null:
		# Export fallback: .fnt may be imported as a Font resource, so load raw text copy if bundled.
		_load_font(path + ".txt")
	if data == null or data.image == null:
		# Desktop fallback in case a globalized path is needed.
		var abs_path := ProjectSettings.globalize_path(path)
		if abs_path != path:
			_load_font(abs_path)
		if data == null or data.image == null:
			_load_font(abs_path + ".txt")

func _on_apply_example(idx: int) -> void:
	# 0 none, 1 V@1,2 V@2,3 B@1,4 B@2
	var theme_map := {
		1: "res://theme/venice16_x1.tres",
		2: "res://theme/venice16_x2.tres",
		3: "res://theme/super12_x1.tres",
		4: "res://theme/super12_x2.tres",
	}
	if idx == 0 or not theme_map.has(idx):
		# None: use an empty theme so the editor shows Godot's default UI (not the project custom theme)
		theme = Theme.new()
		_clear_ui_tint()
		_refresh_preview()
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
			3: fpath = "res://fnt/Super12.fnt"; sz = 12
			4: fpath = "res://fnt/Super12.fnt"; sz = 24
		if ResourceLoader.exists(fpath):
			t.default_font = load(fpath)
		t.default_font_size = sz
		theme = t
	_apply_ui_tint()
	_refresh_preview()
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
	_register_file_dialog(dlg)
	dlg.file_selected.connect(func(p): dlg.queue_free(); _show_ttf_options(p))
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _show_ttf_options(font_path: String) -> void:
	_ttf_font_path = font_path
	var saved := _load_ttf_import_settings()
	_populate_ttf_dialog(saved)
	var vp_size := get_viewport_rect().size
	var target_w := mini(700, int(vp_size.x * 0.92))
	var target_h := mini(700, int(vp_size.y * 0.92))
	ttf_dialog.popup_centered(Vector2i(maxi(target_w, 360), maxi(target_h, 320)))

func _populate_ttf_dialog(saved: Dictionary) -> void:
	var g := "Scroll/VBox/Grid/"
	(ttf_dialog.get_node(g + "SizeSpin") as SpinBox).value = int(saved.get("size", 16))
	var filt := ttf_dialog.get_node(g + "FilterOption") as OptionButton
	filt.select(clampi(int(saved.get("filter", 0)), 0, 1))
	(ttf_dialog.get_node(g + "PaddingSpin") as SpinBox).value = int(saved.get("padding", 0))
	var tie := ttf_dialog.get_node(g + "TieOption") as OptionButton
	tie.select(clampi(int(saved.get("pack_tiebreaker", 0)), 0, 1))
	(ttf_dialog.get_node(g + "OutlineSpin") as SpinBox).value = int(saved.get("outline", 0))
	(ttf_dialog.get_node(g + "OutlineColorPicker") as ColorPickerButton).color = saved.get("outline_color", Color.BLACK)
	var fill := ttf_dialog.get_node(g + "FillOption") as OptionButton
	fill.select(clampi(int(saved.get("fill_mode", 0)), 0, 2))
	var grad := ttf_dialog.get_node(g + "GradientOption") as OptionButton
	grad.select(clampi(int(saved.get("gradient_dir", 1)) - 1, 0, 3))
	(ttf_dialog.get_node(g + "GradFromPicker") as ColorPickerButton).color = saved.get("gradient_color1", Color.WHITE)
	(ttf_dialog.get_node(g + "GradToPicker") as ColorPickerButton).color = saved.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0))
	var proc := ttf_dialog.get_node(g + "ProcEffectOption") as OptionButton
	proc.select(clampi(int(saved.get("proc_effect", 0)), 0, 4))
	(ttf_dialog.get_node(g + "ProcColorPicker") as ColorPickerButton).color = saved.get("proc_color", Color.WHITE)
	(ttf_dialog.get_node(g + "CharsetEdit") as TextEdit).text = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

func _reset_ttf_dialog() -> void:
	var defaults := _default_ttf_import_settings()
	# apply defaults for colors etc already in defaults
	var g := "Scroll/VBox/Grid/"
	(ttf_dialog.get_node(g + "SizeSpin") as SpinBox).value = int(defaults.get("size", 16))
	(ttf_dialog.get_node(g + "FilterOption") as OptionButton).select(clampi(int(defaults.get("filter", 0)), 0, 1))
	(ttf_dialog.get_node(g + "PaddingSpin") as SpinBox).value = int(defaults.get("padding", 0))
	(ttf_dialog.get_node(g + "TieOption") as OptionButton).select(clampi(int(defaults.get("pack_tiebreaker", 0)), 0, 1))
	(ttf_dialog.get_node(g + "OutlineSpin") as SpinBox).value = int(defaults.get("outline", 0))
	(ttf_dialog.get_node(g + "OutlineColorPicker") as ColorPickerButton).color = defaults.get("outline_color", Color.BLACK)
	(ttf_dialog.get_node(g + "FillOption") as OptionButton).select(clampi(int(defaults.get("fill_mode", 0)), 0, 2))
	(ttf_dialog.get_node(g + "GradientOption") as OptionButton).select(clampi(int(defaults.get("gradient_dir", 1)) - 1, 0, 3))
	(ttf_dialog.get_node(g + "GradFromPicker") as ColorPickerButton).color = defaults.get("gradient_color1", Color.WHITE)
	(ttf_dialog.get_node(g + "GradToPicker") as ColorPickerButton).color = defaults.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0))
	(ttf_dialog.get_node(g + "ProcEffectOption") as OptionButton).select(clampi(int(defaults.get("proc_effect", 0)), 0, 4))
	(ttf_dialog.get_node(g + "ProcColorPicker") as ColorPickerButton).color = defaults.get("proc_color", Color.WHITE)

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
	var proc_effect: int = int(opts.get("proc_effect", 0))
	var proc_color: Color = opts.get("proc_color", Color.WHITE)
	var font := FontFile.new()
	var err := font.load_dynamic_font(font_path)
	if err != OK:
		# try loading as resource/data
		var bytes := FileAccess.get_file_as_bytes(font_path)
		if bytes.size() == 0:
			_set_status("Failed to load TTF/OTF: %s" % font_path, true); return
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
	var pad := maxi(0, int(opts.get("padding", 0)))
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
			elif fill_mode == 2:
				_apply_procedural_to_bounds(img, b, proc_effect, proc_color)
			var sub := img.get_region(b)
			var ox := b.position.x - margin
			var oy := b.position.y - margin
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": b.size.x, "h": b.size.y, "img": sub, "ox": ox, "oy": oy})
	vp.queue_free()
	var prefer_wide := int(opts.get("pack_tiebreaker", 0)) == 0
	_pack_rendered_font(font_path.get_file().get_basename(), font_size, rendered, pad, filter_mode, prefer_wide)

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
		0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
		12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
		3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
		15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0,
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
				var m: float = float(bayer[posmod(ly, 4) * 4 + posmod(lx, 4)])
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

func _pack_rendered_font(font_face: String, font_size: int, rendered: Array, pad: int, filter_mode: int = 0, prefer_wide: bool = true) -> void:
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
		var score := float(a) * aspect
		var prefer := best.is_empty()
		if not prefer:
			var best_score := float(best_area) * float(maxi(int(best.w), int(best.h))) / float(maxi(1, mini(int(best.w), int(best.h))))
			if score < best_score - 0.0001:
				prefer = true
			elif abs(score - best_score) <= 0.0001:
				if a < best_area:
					prefer = true
				elif a == best_area:
					var best_land: bool = int(best.w) >= int(best.h)
					var cand_land: bool = w >= h
					if cand_land != best_land:
						prefer = cand_land if prefer_wide else not cand_land
		if prefer:
			best_area = a; best = {"w": w, "h": h, "pos": pos}
	if best.is_empty():
		_set_status("TTF import failed: could not pack atlas", true); return
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
	_refresh_preview(); atlas.queue_redraw()
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
