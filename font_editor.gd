@tool
extends PanelContainer

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "window"
const SETTINGS_FULLSCREEN_KEY := "fullscreen"
const SETTINGS_TTF_SECTION := "ttf_import"
const SETTINGS_FILEDIALOG_SECTION := "file_dialog"
const SETTINGS_FILEDIALOG_FAVORITES_KEY := "favorites"

var data: BMFontData
@onready var atlas: Control = $Main/Left/Atlas
@onready var glyph_list: ItemList = $Main/Tabs/Glyph/GlyphList
@onready var glyph_jump_edit: LineEdit = $Main/Tabs/Glyph/AddRow/GlyphJumpEdit
@onready var status_lbl: Label = $Main/Left/StatusLbl
@onready var preview_edit: TextEdit = $Main/Left/PreviewEdit
@onready var stats_lbl: RichTextLabel = $Main/Tabs/FontStats/StatsLbl
@onready var char_preview: Control = $Main/Left/CharPreview
@onready var kern_list: ItemList = $Main/Tabs/Kerning/KernList
var prop_spin: Dictionary = {}
@onready var font_line_h: SpinBox = $Main/Tabs/FontStats/FontGrid/FontLineH
@onready var font_base: SpinBox = $Main/Tabs/FontStats/FontGrid/FontBase
@onready var glyph_action_btn: Button = $Main/Tabs/Glyph/GlyphActionBtn
@onready var fullscreen_cb: CheckBox = $Main/Left/Toolbar/FullscreenCb
@onready var repack_pad_spin: SpinBox = $Main/Left/Toolbar/RepackPadSpin
var _ttf_font_path: String = ""
@onready var ttf_dialog: AcceptDialog = $TtfDialog
var preview_scale: float = 2.0
var sel_id: int = -1
var _updating_ui := false
var _ui_tinted := false
var _generating_font := false
var _gen_pixel_perfect := false
const STATUS_ERROR_COLOR := Color(1.0, 0.42, 0.42, 1.0)
const STATUS_WARN_COLOR := Color(1.0, 0.82, 0.45, 1.0)

func _ready() -> void:
	name = "Gofnt"
	data = BMFontData.new()
	_bind_ui()
	_apply_ui_tint()
	set_process_unhandled_input(true)
	_refresh_preview()
	_load_window_settings()
	_load_file_dialog_favorites()
	_set_status("Drop-ready: use Open .fnt to load a bitmap font (text BMFont) and its atlas PNG.  Toggle Fullscreen with F11 or the checkbox.")

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
		"pixel_perfect": true, # 1-bit rasterization (no grayscale AA) for pixel fonts
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
	defaults["pixel_perfect"] = bool(cfg.get_value(SETTINGS_TTF_SECTION, "pixel_perfect", defaults["pixel_perfect"]))
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
	defaults["line_height_mode"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "line_height_mode", defaults.get("line_height_mode", 0)))
	defaults["charset_preset"] = int(cfg.get_value(SETTINGS_TTF_SECTION, "charset_preset", defaults.get("charset_preset", 0)))
	defaults["charset"] = str(cfg.get_value(SETTINGS_TTF_SECTION, "charset", defaults.get("charset", " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")))
	# Backward compat: old configs had gradient_dir but no fill_mode.
	if defaults["fill_mode"] < 0:
		defaults["fill_mode"] = 1 if int(defaults["gradient_dir"]) != 0 else 0
	return defaults

func _save_ttf_import_settings(opts: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_TTF_SECTION, "size", int(opts.get("size", 16)))
	cfg.set_value(SETTINGS_TTF_SECTION, "filter", int(opts.get("filter", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "pixel_perfect", bool(opts.get("pixel_perfect", true)))
	cfg.set_value(SETTINGS_TTF_SECTION, "outline", int(opts.get("outline", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "outline_color", (opts.get("outline_color", Color.BLACK) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_dir", int(opts.get("gradient_dir", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_color1", (opts.get("gradient_color1", Color.WHITE) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "gradient_color2", (opts.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0)) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "fill_mode", int(opts.get("fill_mode", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "stamp_path", str(opts.get("stamp_path", "")))
	cfg.set_value(SETTINGS_TTF_SECTION, "stamp_tile", bool(opts.get("stamp_tile", true)))
	cfg.set_value(SETTINGS_TTF_SECTION, "proc_effect", int(opts.get("proc_effect", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "proc_color", (opts.get("proc_color", Color.WHITE) as Color).to_html())
	cfg.set_value(SETTINGS_TTF_SECTION, "padding", int(opts.get("padding", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "pack_tiebreaker", int(opts.get("pack_tiebreaker", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "line_height_mode", int(opts.get("line_height_mode", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "charset_preset", int(opts.get("charset_preset", 0)))
	cfg.set_value(SETTINGS_TTF_SECTION, "charset", str(opts.get("charset", "")))
	cfg.save(SETTINGS_PATH)

# Shared packing gap: the toolbar repack spin and the TTF import dialog edit the
# same setting, so changing one is reflected by the other.
func _save_padding_setting(pad: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_TTF_SECTION, "padding", clampi(pad, 0, 32))
	cfg.save(SETTINGS_PATH)

func _apply_ui_tint() -> void:
	var accent := Color(0.45, 0.72, 1.0, 0.18)
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
			sb.border_color = accent
			add_theme_stylebox_override("panel", sb)
	_ui_tinted = true
	if status_lbl:
		status_lbl.add_theme_color_override("font_color", _status_normal_color())
	if stats_lbl:
		stats_lbl.add_theme_color_override("default_color", Color(0.9, 0.93, 0.98, 0.95))

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

func _ttf(path: String) -> Node:
	# All TTF dialog controls live under this root; keep path changes in one place.
	return ttf_dialog.get_node_or_null("Scroll/VBox/" + path)

func _collect_ttf_options() -> Dictionary:
	var fill_g := "FillGrid/"
	var preset_node := _ttf("CharsGrid/CharsetPresetOption") as OptionButton
	var line_h_node := _ttf("RasterGrid/LineHeightOption") as OptionButton
	var pp_node := _ttf("RasterGrid/PixelPerfectCheck") as CheckBox
	var tall_node := _ttf("RasterGrid/TieBox/TieTallRadio") as CheckBox
	return {
		"size": int((_ttf("RasterGrid/SizeSpin") as SpinBox).value),
		"charset": (_ttf("CharsGrid/CharsetEdit") as TextEdit).text,
		"charset_preset": preset_node.get_selected_id() if preset_node else 0,
		"filter": 1 if (_ttf("RasterGrid/FilterCheck") as CheckBox).button_pressed else 0,
		"pixel_perfect": pp_node.button_pressed if pp_node else true,
		"padding": int((_ttf("RasterGrid/PaddingSpin") as SpinBox).value),
		"pack_tiebreaker": 1 if tall_node != null and tall_node.button_pressed else 0,
		"line_height_mode": line_h_node.get_selected_id() if line_h_node else 0,
		"outline": int((_ttf("OutlineGrid/OutlineSpin") as SpinBox).value),
		"outline_color": (_ttf("OutlineGrid/OutlineColorPicker") as ColorPickerButton).color,
		"fill_mode": (_ttf(fill_g + "FillOption") as OptionButton).get_selected_id(),
		"gradient_dir": (_ttf(fill_g + "GradientOption") as OptionButton).get_selected_id(),
		"gradient_color1": (_ttf(fill_g + "GradFromPicker") as ColorPickerButton).color,
		"gradient_color2": (_ttf(fill_g + "GradToPicker") as ColorPickerButton).color,
		"proc_effect": (_ttf(fill_g + "ProcEffectOption") as OptionButton).get_selected_id(),
		"proc_color": (_ttf(fill_g + "ProcColorPicker") as ColorPickerButton).color,
	}

func _wire_ttf_preview() -> void:
	# Every control feeds the swatch / hint so the dialog reacts instantly.
	var root := ttf_dialog.get_node_or_null("Scroll/VBox")
	if root != null:
		_wire_ttf_preview_node(root)

func _wire_ttf_preview_node(n: Node) -> void:
	var cb := Callable(self, "_refresh_ttf_preview")
	if n is SpinBox:
		var spin_sig := (n as SpinBox).value_changed
		if not spin_sig.is_connected(cb): spin_sig.connect(cb)
	elif n is OptionButton:
		var opt_sig := (n as OptionButton).item_selected
		if not opt_sig.is_connected(cb): opt_sig.connect(cb)
	elif n is CheckBox:
		var check_sig := (n as CheckBox).toggled
		if not check_sig.is_connected(cb): check_sig.connect(cb)
	elif n is ColorPickerButton:
		var color_sig := (n as ColorPickerButton).color_changed
		if not color_sig.is_connected(cb): color_sig.connect(cb)
	elif n is TextEdit:
		var text_sig := (n as TextEdit).text_changed
		if not text_sig.is_connected(cb): text_sig.connect(cb)
	for c in n.get_children():
		_wire_ttf_preview_node(c)

func _refresh_ttf_preview(_ignored: Variant = null) -> void:
	var p := _ttf("Header/HeaderMargin/HeaderRow/Preview")
	if p == null:
		return
	var fg := "FillGrid/"
	var fill := _ttf(fg + "FillOption") as OptionButton
	var grad := _ttf(fg + "GradientOption") as OptionButton
	var proc := _ttf(fg + "ProcEffectOption") as OptionButton
	var outline := _ttf("OutlineGrid/OutlineSpin") as SpinBox
	p.set("fill_mode", fill.get_selected_id() if fill else 0)
	p.set("gradient_dir", grad.get_selected_id() if grad else 1)
	p.set("color1", (_ttf(fg + "GradFromPicker") as ColorPickerButton).color)
	p.set("color2", (_ttf(fg + "GradToPicker") as ColorPickerButton).color)
	p.set("proc_effect", proc.get_selected_id() if proc else 0)
	p.set("proc_color", (_ttf(fg + "ProcColorPicker") as ColorPickerButton).color)
	p.set("outline_px", int(outline.value) if outline else 0)
	p.set("outline_color", (_ttf("OutlineGrid/OutlineColorPicker") as ColorPickerButton).color)
	p.queue_redraw()
	_update_ttf_hint()

func _update_ttf_hint() -> void:
	var lbl := _ttf("InfoLabel") as Label
	if lbl == null:
		return
	var fill := _ttf("FillGrid/FillOption") as OptionButton
	var mode := fill.get_selected_id() if fill else 0
	var msg := ""
	match mode:
		0: msg = "Solid: glyph pixels use a flat color — crisp and compact."
		1: msg = "Gradient: colors are baked across every glyph in the atlas."
		2: msg = "Procedural: scanlines, dither and noise are baked into glyph pixels."
	var pp := _ttf("RasterGrid/PixelPerfectCheck") as CheckBox
	if pp != null and pp.button_pressed:
		msg += "  Pixel-perfect rasterization keeps edges sharp."
	lbl.text = msg

func _style_ttf_dialog() -> void:
	if ttf_dialog.get_meta("ttf_styled", false):
		return
	ttf_dialog.set_meta("ttf_styled", true)
	var ok := ttf_dialog.get_ok_button()
	if ok != null:
		ok.text = "  Import font  "
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.32, 0.62, 0.96, 1.0)
		normal.set_corner_radius_all(5)
		normal.content_margin_left = 10.0
		normal.content_margin_right = 10.0
		ok.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.44, 0.74, 1.0, 1.0)
		ok.add_theme_stylebox_override("hover", hover)
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(0.20, 0.46, 0.80, 1.0)
		ok.add_theme_stylebox_override("pressed", pressed)
		ok.add_theme_color_override("font_color", Color(0.04, 0.09, 0.15, 1.0))
		ok.add_theme_color_override("font_hover_color", Color(0.02, 0.06, 0.12, 1.0))

func _animate_ttf_dialog() -> void:
	if Engine.is_editor_hint():
		return
	var root := ttf_dialog.get_node_or_null("Scroll/VBox") as Control
	if root == null or not is_inside_tree():
		return
	root.modulate.a = 0.0
	root.pivot_offset = Vector2(root.size.x * 0.5, 32.0)
	root.scale = Vector2(0.985, 0.985)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var i := 0
	for n in ["RasterTitle", "OutlineTitle", "FillTitle", "CharsTitle", "InfoLabel", "Footer"]:
		var c := _ttf(n) as Control
		if c == null:
			continue
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(0.04 * float(i))
		i += 1

func _bind_ui() -> void:
	# Scene provides nodes; wire signals here.
	var tabs := $Main/Tabs as TabContainer
	tabs.set_tab_title(0, "Glyph")
	tabs.set_tab_title(1, "Font/Stats")
	tabs.set_tab_title(2, "Kerning")

	# Toolbar buttons
	$Main/Left/Toolbar/OpenBtn.pressed.connect(_on_open)
	$Main/Left/Toolbar/SaveFntBtn.pressed.connect(_on_save)
	$Main/Left/Toolbar/TrimSelectedBtn.pressed.connect(_on_autoslice_selected)
	$Main/Left/Toolbar/TrimAllBtn.pressed.connect(_on_autoslice_all)
	$Main/Left/Toolbar/RepackBtn.pressed.connect(_on_repack)
	if repack_pad_spin:
		_updating_ui = true
		repack_pad_spin.value = maxi(0, int(_load_ttf_import_settings().get("padding", 0)))
		_updating_ui = false
		repack_pad_spin.value_changed.connect(func(v):
			if not _updating_ui:
				_save_padding_setting(int(v))
		)
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
	font_base.value_changed.connect(func(v): if not _updating_ui: data.common["base"] = int(v); _refresh_preview())

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

	# TTF import dialog — wired, skinned and live-previewed
	ttf_dialog.canceled.connect(func(): ttf_dialog.hide())
	var ttf_reset_btn := _ttf("Footer/ResetBtn") as Button
	ttf_reset_btn.pressed.connect(_reset_ttf_dialog)
	var ttf_fill := _ttf("FillGrid/FillOption") as OptionButton
	ttf_fill.item_selected.connect(func(_i):
		_update_ttf_fill_visibility()
		_update_ttf_hint()
	)
	_setup_ttf_tie_radios()
	_wire_ttf_preview()
	_style_ttf_dialog()
	ttf_dialog.confirmed.connect(func():
		var opts := _collect_ttf_options()
		_save_ttf_import_settings(opts)
		ttf_dialog.hide()
		if repack_pad_spin:
			_updating_ui = true
			repack_pad_spin.value = int(opts.get("padding", 0))
			_updating_ui = false
		_import_ttf(_ttf_font_path, opts)
	)

func _refresh_preview() -> void:
	if char_preview:
		char_preview.set_data(data)
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
	# Fill in (empty) glyphs for missing codepoints so the preview does not
	# render tofu/boxes for characters that have no defined glyph yet.
	var _space_adv := 0
	if preview_data.chars.has(32):
		_space_adv = int(preview_data.chars[32].get("xadvance", 0))
	if _space_adv <= 0:
		_space_adv = maxi(4, int(preview_data.common.get("lineHeight", 16) / 2) * s)
	var _needed := {}
	for _id in range(32, 127):
		_needed[_id] = true
	if preview_edit != null:
		for _i in preview_edit.text.length():
			_needed[preview_edit.text.unicode_at(_i)] = true
	for _id in _needed.keys():
		if not preview_data.chars.has(_id):
			preview_data.chars[_id] = {"id": _id, "x": 0, "y": 0, "width": 0, "height": 0, "xoffset": 0, "yoffset": 0, "xadvance": _space_adv, "page": 0, "chnl": 15}
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
	if char_preview:
		char_preview.texture_filter = tf
	# note: BMFont .fnt doesn't store Godot texture filter; this affects editor preview/atlas rendering.

func _on_open() -> void:
	if _generating_font:
		_set_status("Font generation in progress...", false, true)
		return
	# Unified "Open" dialog: accepts BMFont .fnt, TTF/OTF fonts, and images.
	# The selected file is routed to the appropriate loader based on its extension.
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray([
		"* ; All files",
		"*.fnt ; BMFont (.fnt)",
		"*.ttf,*.otf ; TrueType/OpenType Font (.ttf/.otf)",
		"*.png,*.webp,*.jpg,*.jpeg,*.bmp ; Image (.png/.webp/...)",
	])
	add_child(dlg)
	_register_file_dialog(dlg)
	dlg.file_selected.connect(func(p: String):
		var path := p
		# Godot may append the selected filter's extension if it thinks the
		# chosen file does not match; recover the real file when possible.
		if not FileAccess.file_exists(path):
			for ext in [".fnt", ".ttf", ".otf", ".png", ".webp", ".jpg", ".jpeg", ".bmp"]:
				if path.to_lower().ends_with(ext) and path.length() > ext.length():
					var stripped := path.substr(0, path.length() - ext.length())
					# If stripping the last extension yields an existing file, use it.
					if FileAccess.file_exists(stripped):
						path = stripped
						break
		var low := path.to_lower()
		if low.ends_with(".fnt"):
			_load_font(path)
		elif low.ends_with(".ttf") or low.ends_with(".otf"):
			_show_ttf_options(path)
		else:
			_import_image(path)
		dlg.queue_free()
	)
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

func _on_save() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	if data.fnt_path == "":
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.filters = PackedStringArray([
			"* ; All files",
			"*.fnt ; BMFont (.fnt)",
		])
		dlg.current_file = str(data.info.get("face", "font")) + ".fnt"
		add_child(dlg)
		_register_file_dialog(dlg)
		dlg.file_selected.connect(func(p: String):
			var path := p
			if not path.to_lower().ends_with(".fnt"):
				path += ".fnt"
			data.fnt_path = path
			if data.image_path == "":
				data.image_path = path.get_basename() + ".png"
			_save_both()
			dlg.queue_free()
		)
		dlg.canceled.connect(func(): dlg.queue_free())
		dlg.popup_centered_ratio(0.7)
		return
	if data.image_path == "":
		data.image_path = data.fnt_path.get_basename() + ".png"
	_save_both()

func _save_both() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	var e1 := data.save_fnt(data.fnt_path)
	if e1 == OK and not data.pages.is_empty():
		var page_file := data.fnt_path.get_file().get_basename() + ".png"
		if data.image_path != "":
			page_file = data.image_path.get_file()
		data.pages[0]["file"] = page_file
	var e2 := data.save_png(data.image_path)
	if e1 == OK and e2 == OK:
		_set_status("Saved .fnt (%s) and PNG (%s)" % [data.fnt_path, data.image_path])
	else:
		_set_status("Save failed: fnt=%d png=%d" % [e1, e2], true)

func _on_save_fnt() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	if data.fnt_path == "":
		_prompt_save_unified()
		return
	_do_save_fnt()

func _prompt_save_unified() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray([
		"*.fnt ; BMFont (.fnt)",
		"*.png ; PNG Image (.png)",
	])
	var base := data.fnt_path.get_basename() if data.fnt_path != "" else str(data.info.get("face", "font"))
	dlg.current_file = base.get_file()
	add_child(dlg)
	_register_file_dialog(dlg)
	dlg.file_selected.connect(func(p: String):
		var low := p.to_lower()
		if low.ends_with(".fnt"):
			data.fnt_path = p
			if data.image_path == "":
				data.image_path = p.get_basename() + ".png"
			_do_save_fnt()
		else:
			var out := p
			if not low.ends_with(".png"):
				out += ".png"
			data.image_path = out
			_do_save_png()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered_ratio(0.7)

func _do_save_fnt() -> void:
	var err := data.save_fnt(data.fnt_path)
	if err == OK and not data.pages.is_empty():
		var page_file := data.fnt_path.get_file().get_basename() + ".png"
		if data.image_path != "":
			page_file = data.image_path.get_file()
		data.pages[0]["file"] = page_file
	_set_status("Saved .fnt to %s" % data.fnt_path if err == OK else "Save failed: %d" % err, err != OK)

func _on_save_png() -> void:
	if data == null or data.image == null:
		_set_status("Nothing to save"); return
	if data.image_path == "":
		_prompt_save_unified()
		return
	_do_save_png()

func _do_save_png() -> void:
	var err := data.save_png(data.image_path)
	_set_status("Saved PNG to %s" % data.image_path if err == OK else "Save failed: %d" % err, err != OK)

func _on_repack() -> void:
	if data == null or data.image == null: return
	var pad := 0
	if repack_pad_spin:
		pad = maxi(0, int(repack_pad_spin.value))
	else:
		pad = maxi(0, int(_load_ttf_import_settings().get("padding", 0)))
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
	var msg := "Repacked atlas to %dx%d (%d glyphs)" % [nw, nh, glyphs.size()]
	if pad > 0:
		msg += " (pad %d)" % pad
	_set_status(msg)

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

func _import_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		# Fallback for formats load_from_file may not handle directly (e.g. webp in some builds).
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			img = Image.new()
			var ext := path.get_extension().to_lower()
			var ok := false
			match ext:
				"png": ok = img.load_png_from_buffer(bytes) == OK
				"webp": ok = img.load_webp_from_buffer(bytes) == OK
				"jpg", "jpeg": ok = img.load_jpg_from_buffer(bytes) == OK
				"bmp": ok = img.load_bmp_from_buffer(bytes) == OK
			if not ok:
				# Last-chance: try all common formats.
				for fmt in ["png", "webp", "jpg", "bmp"]:
					var e := ERR_FILE_UNRECOGNIZED
					match fmt:
						"png": e = img.load_png_from_buffer(bytes)
						"webp": e = img.load_webp_from_buffer(bytes)
						"jpg": e = img.load_jpg_from_buffer(bytes)
						"bmp": e = img.load_bmp_from_buffer(bytes)
					if e == OK:
						ok = true
						break
		if img == null or (img.get_width() <= 0 and img.get_height() <= 0):
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

func _show_ttf_options(font_path: String) -> void:
	_ttf_font_path = font_path
	var saved := _load_ttf_import_settings()
	_populate_ttf_dialog(saved)
	var name_lbl := _ttf("Header/HeaderMargin/HeaderRow/HeaderText/FontName") as Label
	if name_lbl != null:
		name_lbl.text = font_path.get_file()
	var preview := _ttf("Header/HeaderMargin/HeaderRow/Preview")
	if preview != null:
		var fnt := FontFile.new()
		preview.set("font", fnt if fnt.load_dynamic_font(font_path) == OK else null)
		preview.set("sample_text", "Ag")
	_refresh_ttf_preview()
	var vp_size := get_viewport_rect().size
	var target_w := mini(720, int(vp_size.x * 0.92))
	var target_h := mini(840, int(vp_size.y * 0.92))
	ttf_dialog.popup_centered(Vector2i(maxi(target_w, 520), maxi(target_h, 460)))
	_animate_ttf_dialog()

func _populate_ttf_dialog(saved: Dictionary) -> void:
	(_ttf("RasterGrid/SizeSpin") as SpinBox).value = int(saved.get("size", 16))
	(_ttf("RasterGrid/FilterCheck") as CheckBox).button_pressed = int(saved.get("filter", 0)) == 1
	var pp := _ttf("RasterGrid/PixelPerfectCheck") as CheckBox
	if pp != null: pp.button_pressed = bool(saved.get("pixel_perfect", true))
	(_ttf("RasterGrid/PaddingSpin") as SpinBox).value = int(saved.get("padding", 0))
	_set_ttf_tie_radio(int(saved.get("pack_tiebreaker", 0)))
	var line_h_node := _ttf("RasterGrid/LineHeightOption") as OptionButton
	if line_h_node != null:
		line_h_node.select(clampi(int(saved.get("line_height_mode", 0)), 0, maxi(0, line_h_node.item_count - 1)))
	(_ttf("OutlineGrid/OutlineSpin") as SpinBox).value = int(saved.get("outline", 0))
	(_ttf("OutlineGrid/OutlineColorPicker") as ColorPickerButton).color = saved.get("outline_color", Color.BLACK)
	var fill := _ttf("FillGrid/FillOption") as OptionButton
	fill.select(clampi(int(saved.get("fill_mode", 0)), 0, 2))
	var grad := _ttf("FillGrid/GradientOption") as OptionButton
	grad.select(clampi(int(saved.get("gradient_dir", 1)) - 1, 0, 3))
	(_ttf("FillGrid/GradFromPicker") as ColorPickerButton).color = saved.get("gradient_color1", Color.WHITE)
	(_ttf("FillGrid/GradToPicker") as ColorPickerButton).color = saved.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0))
	var proc := _ttf("FillGrid/ProcEffectOption") as OptionButton
	proc.select(clampi(int(saved.get("proc_effect", 0)), 0, 4))
	(_ttf("FillGrid/ProcColorPicker") as ColorPickerButton).color = saved.get("proc_color", Color.WHITE)
	var preset_node := _ttf("CharsGrid/CharsetPresetOption") as OptionButton
	if preset_node != null:
		preset_node.select(clampi(int(saved.get("charset_preset", 0)), 0, 2))
	(_ttf("CharsGrid/CharsetEdit") as TextEdit).text = str(saved.get("charset", " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"))
	_update_ttf_fill_visibility()

func _reset_ttf_dialog() -> void:
	var defaults := _default_ttf_import_settings()
	(_ttf("RasterGrid/SizeSpin") as SpinBox).value = int(defaults.get("size", 16))
	(_ttf("RasterGrid/FilterCheck") as CheckBox).button_pressed = int(defaults.get("filter", 0)) == 1
	var pp := _ttf("RasterGrid/PixelPerfectCheck") as CheckBox
	if pp != null: pp.button_pressed = bool(defaults.get("pixel_perfect", true))
	(_ttf("RasterGrid/PaddingSpin") as SpinBox).value = int(defaults.get("padding", 0))
	_set_ttf_tie_radio(int(defaults.get("pack_tiebreaker", 0)))
	var line_h_node := _ttf("RasterGrid/LineHeightOption") as OptionButton
	if line_h_node != null: line_h_node.select(0)
	(_ttf("OutlineGrid/OutlineSpin") as SpinBox).value = int(defaults.get("outline", 0))
	(_ttf("OutlineGrid/OutlineColorPicker") as ColorPickerButton).color = defaults.get("outline_color", Color.BLACK)
	(_ttf("FillGrid/FillOption") as OptionButton).select(clampi(int(defaults.get("fill_mode", 0)), 0, 2))
	(_ttf("FillGrid/GradientOption") as OptionButton).select(clampi(int(defaults.get("gradient_dir", 1)) - 1, 0, 3))
	(_ttf("FillGrid/GradFromPicker") as ColorPickerButton).color = defaults.get("gradient_color1", Color.WHITE)
	(_ttf("FillGrid/GradToPicker") as ColorPickerButton).color = defaults.get("gradient_color2", Color(0.7, 0.85, 1.0, 1.0))
	(_ttf("FillGrid/ProcEffectOption") as OptionButton).select(clampi(int(defaults.get("proc_effect", 0)), 0, 4))
	(_ttf("FillGrid/ProcColorPicker") as ColorPickerButton).color = defaults.get("proc_color", Color.WHITE)
	var preset_node := _ttf("CharsGrid/CharsetPresetOption") as OptionButton
	if preset_node != null: preset_node.select(0)
	(_ttf("CharsGrid/CharsetEdit") as TextEdit).text = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
	_update_ttf_fill_visibility()
	_refresh_ttf_preview()

func _setup_ttf_tie_radios() -> void:
	var g := "RasterGrid/TieBox/"
	var wide := _ttf(g + "TieWideRadio") as CheckBox
	var tall := _ttf(g + "TieTallRadio") as CheckBox
	if wide == null or tall == null:
		return
	if wide.button_group == null:
		var bg := ButtonGroup.new()
		wide.button_group = bg
		tall.button_group = bg

func _set_ttf_tie_radio(v: int) -> void:
	_setup_ttf_tie_radios()
	var g := "RasterGrid/TieBox/"
	var wide := _ttf(g + "TieWideRadio") as CheckBox
	var tall := _ttf(g + "TieTallRadio") as CheckBox
	if wide == null or tall == null:
		return
	tall.button_pressed = v == 1
	wide.button_pressed = v != 1

func _update_ttf_fill_visibility() -> void:
	var fill := _ttf("FillGrid/FillOption") as OptionButton
	if fill == null:
		return
	var mode := fill.get_selected_id()
	var is_grad := mode == 1
	var is_proc := mode == 2
	for n in ["GradientLabel", "GradientOption", "GradFromLabel", "GradFromPicker", "GradToLabel", "GradToPicker"]:
		var node := _ttf("FillGrid/" + n) as CanvasItem
		if node: node.visible = is_grad
	for n in ["ProcEffectLabel", "ProcEffectOption", "ProcColorLabel", "ProcColorPicker"]:
		var node := _ttf("FillGrid/" + n) as CanvasItem
		if node: node.visible = is_proc


func _import_ttf(font_path: String, opts: Dictionary) -> void:
	_generating_font = true
	_gen_pixel_perfect = bool(opts.get("pixel_perfect", true))
	var open_btn := get_node_or_null("Main/Left/Toolbar/OpenBtn") as Button
	if open_btn:
		open_btn.disabled = true
	var vp: SubViewport = null
	var font_face := font_path.get_file().get_basename()
	var font_size: int = int(opts.get("size", 16))
	_set_status("Generating font from %s..." % font_face)
	# Allow the status label to repaint before heavy work begins.
	await get_tree().process_frame
	if not is_inside_tree():
		_generating_font = false
		if open_btn:
			open_btn.disabled = false
		return
	var charset_preset: int = int(opts.get("charset_preset", 0))
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
			_generating_font = false
			if open_btn:
				open_btn.disabled = false
			_set_status("Failed to load TTF/OTF: %s" % font_path, true); return
		font.data = bytes
	if _gen_pixel_perfect:
		# 1-bit rasterization: this is what makes alagard-style pixel fonts come out crisp.
		# Grayscale FreeType AA is what turns smooth-outline TTFs into a gray, "sloppy" atlas.
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NORMAL
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font.force_autohinter = false
		font.clear_cache()
	var charset_str := charset
	if charset_preset == 0:
		charset_str = ""
		for cp in range(32, 127):
			charset_str += String.chr(cp)
	elif charset_preset == 1:
		if font.has_method("get_supported_chars"):
			charset_str = str(font.get_supported_chars())
		else:
			charset_str = ""
	var unique: Dictionary = {}
	var order: Array[int] = []
	for i in charset_str.length():
		var cp := charset_str.unicode_at(i)
		if cp == 10: continue
		if not unique.has(cp):
			unique[cp] = true; order.append(cp)
	if order.is_empty():
		for cp in range(32, 127): order.append(cp)
	var pad := maxi(0, int(opts.get("padding", 0)))
	var font_ascent := font_size
	if font.has_method("get_ascent"):
		font_ascent = int(ceil(font.get_ascent(font_size)))
	elif font.has_method("get_font_ascent"):
		font_ascent = int(ceil(font.get_font_ascent(font_size)))
	font_ascent = maxi(1, font_ascent)
	var font_descent := maxi(0, font_size - font_ascent)
	if font.has_method("get_descent"):
		font_descent = int(ceil(font.get_descent(font_size)))
	elif font.has_method("get_font_descent"):
		font_descent = int(ceil(font.get_font_descent(font_size)))
	var metrics_line_h := maxi(font_size, font_ascent + font_descent)
	var entries: Array = []
	# collect metrics using font
	for cp in order:
		var ch := String.chr(cp)
		var adv := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var xadv := int(ceil(adv.x)) + outline_px * 2
		if xadv <= 0: xadv = int(font_size / 2.0)
		entries.append({"cp": cp, "ch": ch, "xadv": xadv})
	# render in batches to get images: use one SubViewport and draw each char
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ci := Control.new()
	ci.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ci)
	ci.draw.connect(func(): _ttf_draw_glyph(ci))
	var rendered: Array = [] # {cp,xadv,img,ox,oy}
	var margin := int(font_size) + outline_px + 2
	var total := entries.size()
	var done := 0
	for e in entries:
		var cw := int(font_size * 2) + margin * 2 + outline_px * 4
		var chh := int(font_size * 2) + margin * 2 + outline_px * 4
		vp.size = Vector2i(cw, chh)
		var img: Image = null
		if outline_px > 0 and fill_mode in [1, 2]:
			# Render fill and outline separately so effects don't overwrite outline color.
			img = await _render_ttf_glyph_layered(vp, ci, font, int(e.cp), font_size, margin, font_ascent, outline_px, outline_color, fill_mode, gradient_dir, gradient_color1, gradient_color2, proc_effect, proc_color)
		else:
			ci.set_meta("ds", {"font": font, "cp": e.cp, "size": font_size, "margin": margin, "ascent": font_ascent, "outline": outline_px, "outline_color": outline_color})
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			ci.queue_redraw()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not is_inside_tree():
				if is_instance_valid(vp):
					vp.queue_free()
				_generating_font = false
				return
			var tex := vp.get_texture()
			if tex != null:
				img = tex.get_image()
			if img != null and _gen_pixel_perfect:
				_snap_alpha_1bit(img)
			if img != null:
				var b := _alpha_bounds(img)
				if b.size.x > 0 and b.size.y > 0:
					if fill_mode == 1:
						_apply_gradient_to_bounds(img, b, gradient_dir, gradient_color1, gradient_color2)
					elif fill_mode == 2:
						_apply_procedural_to_bounds(img, b, proc_effect, proc_color)
		if not is_inside_tree():
			if is_instance_valid(vp):
				vp.queue_free()
			_generating_font = false
			return
		if img == null:
			rendered.append({"cp": e.cp, "xadv": e.xadv, "w": 0, "h": 0, "img": null, "ox": 0, "oy": 0})
		else:
			var b := _alpha_bounds(img)
			if b.size.x <= 0 or b.size.y <= 0:
				rendered.append({"cp": e.cp, "xadv": e.xadv, "w": 0, "h": 0, "img": null, "ox": 0, "oy": 0})
			else:
				var sub := img.get_region(b)
				var ox := b.position.x - margin
				var oy := b.position.y - margin
				rendered.append({"cp": e.cp, "xadv": e.xadv, "w": b.size.x, "h": b.size.y, "img": sub, "ox": ox, "oy": oy})
		done += 1
		if done == 1 or done == total or done % 5 == 0:
			var pct := int(round(float(done) * 100.0 / float(maxi(total, 1))))
			var ch_label: String = str(e.get("ch", ""))
			var cpv := int(e.get("cp", 0))
			if cpv == 32:
				ch_label = "space"
			elif cpv < 32 or cpv > 126:
				ch_label = "U+%04X" % cpv
			_set_status("Generating font: %d/%d glyphs (%d%%) — %s" % [done, total, pct, ch_label])
	vp.queue_free()
	_set_status("Packing font atlas...")
	await get_tree().process_frame
	var prefer_wide := int(opts.get("pack_tiebreaker", 0)) == 0
	var final_line_h := metrics_line_h
	if int(opts.get("line_height_mode", 0)) == 1:
		var tight_h := 0
		for r in rendered:
			if int(r.get("h", 0)) > 0:
				tight_h = maxi(tight_h, int(r.get("oy", 0)) + int(r.get("h", 0)))
		if tight_h > 0:
			final_line_h = tight_h
	_pack_rendered_font(font_face, font_size, rendered, pad, filter_mode, prefer_wide, final_line_h, font_ascent)
	_generating_font = false
	if open_btn:
		open_btn.disabled = false

func _render_ttf_glyph_layered(vp: SubViewport, ci: Control, font: Font, cp: int, font_size: int, margin: int, ascent: int, outline_px: int, outline_color: Color, fill_mode: int, gradient_dir: int, gradient_color1: Color, gradient_color2: Color, proc_effect: int, proc_color: Color) -> Image:
	# Fill only: apply baked effect to the glyph fill, not the outline.
	ci.set_meta("ds", {"font": font, "cp": cp, "size": font_size, "margin": margin, "ascent": ascent, "outline": outline_px, "outline_color": outline_color, "draw_outline": false, "draw_fill": true})
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	ci.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return null
	var fill_tex := vp.get_texture()
	if fill_tex == null:
		return null
	var img_fill := fill_tex.get_image()
	if img_fill == null:
		return null
	if _gen_pixel_perfect:
		_snap_alpha_1bit(img_fill)
	var fb := _alpha_bounds(img_fill)
	if fb.size.x > 0 and fb.size.y > 0:
		if fill_mode == 1:
			_apply_gradient_to_bounds(img_fill, fb, gradient_dir, gradient_color1, gradient_color2)
		elif fill_mode == 2:
			_apply_procedural_to_bounds(img_fill, fb, proc_effect, proc_color)

	# Outline only: keep its own color.
	ci.set_meta("ds", {"font": font, "cp": cp, "size": font_size, "margin": margin, "ascent": ascent, "outline": outline_px, "outline_color": outline_color, "draw_outline": true, "draw_fill": false})
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	ci.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return null
	var out_tex := vp.get_texture()
	if out_tex == null:
		return img_fill
	var img_outline := out_tex.get_image()
	if img_outline == null:
		return img_fill
	if _gen_pixel_perfect:
		_snap_alpha_1bit(img_outline)

	# Composite: outline underneath/around, effected fill on top.
	var result := Image.create(img_fill.get_width(), img_fill.get_height(), false, img_fill.get_format())
	result.fill(Color(0, 0, 0, 0))
	var full := Rect2i(Vector2i.ZERO, img_fill.get_size())
	result.blit_rect(img_outline, full, Vector2i.ZERO)
	result.blend_rect(img_fill, full, Vector2i.ZERO)
	if _gen_pixel_perfect:
		_snap_alpha_1bit(result)
	return result

func _snap_alpha_1bit(img: Image) -> void:
	# Force a strict 0/255 alpha so the packed atlas has no gray fringe pixels.
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var p := img.get_pixel(x, y)
			if p.a < 0.5:
				if p.a > 0.0:
					img.set_pixel(x, y, Color(p.r, p.g, p.b, 0.0))
			else:
				img.set_pixel(x, y, Color(p.r, p.g, p.b, 1.0))

func _ttf_draw_glyph(ci: Control) -> void:
	if not ci.has_meta("ds"): return
	var ds: Dictionary = ci.get_meta("ds")
	var font: Font = ds.font
	var cp: int = ds.cp
	var fsize: int = ds.size
	var margin: int = ds.margin
	var ascent: int = int(ds.get("ascent", fsize))
	var outline: int = int(ds.get("outline", 0))
	var outline_color: Color = ds.get("outline_color", Color.BLACK)
	var draw_outline: bool = bool(ds.get("draw_outline", true))
	var draw_fill: bool = bool(ds.get("draw_fill", true))
	ci.draw_rect(Rect2(Vector2.ZERO, ci.size), Color(0, 0, 0, 0))
	# Draw with the font baseline at (margin, margin + ascent) so glyph yoffsets
	# are relative to the top of the line box (BMFont convention: yoffset from line top).
	var baseline := Vector2(margin, margin + ascent)
	var ch := String.chr(cp)
	if draw_outline and outline > 0:
		for oy in range(-outline, outline + 1):
			for ox in range(-outline, outline + 1):
				if ox == 0 and oy == 0: continue
				if ox * ox + oy * oy > outline * outline: continue
				ci.draw_char(font, baseline + Vector2(ox, oy), ch, fsize, outline_color)
	if draw_fill:
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

func _pack_rendered_font(font_face: String, font_size: int, rendered: Array, pad: int, filter_mode: int = 0, prefer_wide: bool = true, line_h: int = -1, base: int = -1) -> void:
	if line_h <= 0:
		line_h = font_size
	if base <= 0:
		base = int(font_size * 0.8)
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
	data.common = {"lineHeight": line_h, "base": base, "scaleW": nw, "scaleH": nh, "pages": 1}
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
	font_line_h.value = int(data.common.get("lineHeight", line_h))
	font_base.value = int(data.common.get("base", base))
	_updating_ui = false
	_refresh_glyph_list(); _refresh_kern(); _refresh_stats()
	_refresh_preview(); atlas.queue_redraw()
	var filt_name := "Nearest" if filter_mode == 0 else "Linear"
	var bits_name := "1-bit" if _gen_pixel_perfect else "grayscale"
	_set_status("Imported TTF/OTF '%s' at size %d: %d glyphs rasterized (%s, %s filter)" % [font_face, font_size, data.chars.size(), bits_name, filt_name])

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
