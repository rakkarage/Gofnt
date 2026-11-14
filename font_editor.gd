@tool
extends PanelContainer

var data: BMFontData
var atlas: Control
var glyph_list: ItemList
var status_lbl: Label
var preview_edit: TextEdit
var preview_canvas: Control
var stats_lbl: RichTextLabel
var kern_list: ItemList
var prop_spin: Dictionary = {}
var font_line_h: SpinBox
var font_base: SpinBox
var glyph_action_btn: Button
var preview_scale: float = 2.0
var sel_id: int = -1
var _updating_ui := false

func _ready() -> void:
	name = "JuicyFontEditor"
	data = BMFontData.new()
	_build_ui()
	set_process_unhandled_input(true)
	_set_status("Drop-ready: use Open .fnt to load a bitmap font (text BMFont) and its atlas PNG.  F11: fullscreen")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var win := get_window()
		if win:
			if win.mode == Window.MODE_FULLSCREEN:
				win.mode = Window.MODE_WINDOWED
			else:
				win.mode = Window.MODE_FULLSCREEN
		accept_event()

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
	var save_fnt_btn := Button.new(); save_fnt_btn.text = "Save .fnt"; save_fnt_btn.tooltip_text = "Save BMFont data to the loaded .fnt path"; save_fnt_btn.pressed.connect(_on_save_fnt); bar.add_child(save_fnt_btn)
	var save_png_btn := Button.new(); save_png_btn.text = "Save PNG"; save_png_btn.tooltip_text = "Save atlas image to the loaded PNG path"; save_png_btn.pressed.connect(_on_save_png); bar.add_child(save_png_btn)
	bar.add_child(VSeparator.new())
	var autoslice_btn := Button.new(); autoslice_btn.text = "Trim selected"; autoslice_btn.tooltip_text = "Trim selected glyph rect to non-transparent bounds"; autoslice_btn.pressed.connect(_on_autoslice_selected); bar.add_child(autoslice_btn)
	var autoslice_all_btn := Button.new(); autoslice_all_btn.text = "Trim all"; autoslice_all_btn.tooltip_text = "Trim all glyph rects to non-transparent bounds (does not detect new glyphs)"; autoslice_all_btn.pressed.connect(_on_autoslice_all); bar.add_child(autoslice_all_btn)
	var repack_btn := Button.new(); repack_btn.text = "Repack"; repack_btn.tooltip_text = "Shelf-pack glyphs into a tighter power-of-two atlas"; repack_btn.pressed.connect(_on_repack); bar.add_child(repack_btn)
	status_lbl = Label.new(); status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_lbl.text = ""; status_lbl.clip_text = true; left.add_child(status_lbl)

	var examples_row := HBoxContainer.new(); left.add_child(examples_row)
	examples_row.add_child(_lbl("Load Demo:"))
	var load_dd := OptionButton.new()
	load_dd.add_item("[load]", 0)
	load_dd.add_item("Venice16", 1)
	load_dd.add_item("SuperBlack12", 2)
	load_dd.add_item("SuperWhite12", 3)
	load_dd.tooltip_text = "Load an included example .fnt into the editor"
	load_dd.item_selected.connect(func(i): _on_load_example(load_dd.get_item_id(i)); load_dd.select(0))
	examples_row.add_child(load_dd)
	examples_row.add_child(VSeparator.new())
	examples_row.add_child(_lbl("Apply Demo:"))
	var apply_dd := OptionButton.new()
	for item in ["[apply]", "Venice16 @1x (16)", "Venice16 @2x (32)", "SuperBlack12 @1x (12)", "SuperBlack12 @2x (24)", "SuperWhite12 @1x (12)", "SuperWhite12 @2x (24)"]:
		apply_dd.add_item(item)
	apply_dd.tooltip_text = "Apply an included font to the preview/theme UI at 1x or 2x scale"
	apply_dd.item_selected.connect(func(i): _on_apply_example(i))
	examples_row.add_child(apply_dd)

	atlas = FontAtlasView.new()
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas.size_flags_stretch_ratio = 3.0
	atlas.custom_minimum_size = Vector2(400, 300)
	atlas.glyph_selected.connect(_on_glyph_selected)
	atlas.glyph_changed.connect(_on_glyph_changed)
	left.add_child(atlas)

	var pv_lbl := Label.new(); pv_lbl.text = "Live preview"; left.add_child(pv_lbl)
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
	var hl := Label.new(); hl.text = "Glyphs (ASCII 32–126 shown; missing can be created)"; vb.add_child(hl)
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
	if data == null or data.fnt_path == "": _set_status("Nothing to save"); return
	var err := data.save_fnt(data.fnt_path)
	_set_status("Saved .fnt" if err == OK else "Save failed: %d" % err)

func _on_save_png() -> void:
	if data == null or data.image_path == "": _set_status("Nothing to save"); return
	var err := data.save_png(data.image_path)
	_set_status("Saved PNG" if err == OK else "Save failed: %d" % err)

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
		if a < best_area:
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
		1: "res://font/Venice16.fnt",
		2: "res://font/SuperBlack12.fnt",
		3: "res://font/SuperWhite12.fnt",
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
		1: "res://themes/venice16_x1.tres",
		2: "res://themes/venice16_x2.tres",
		3: "res://themes/superblack12_x1.tres",
		4: "res://themes/superblack12_x2.tres",
		5: "res://themes/superwhite12_x1.tres",
		6: "res://themes/superwhite12_x2.tres",
	}
	if idx == 0 or not theme_map.has(idx):
		theme = null
		preview_scale = 2.0
		if preview_edit:
			preview_edit.remove_theme_font_override("font")
			preview_edit.remove_theme_font_size_override("font_size")
		preview_canvas.queue_redraw()
		_set_status("Theme/demo cleared")
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
		var fpath := "res://font/Venice16.fnt"
		var sz := 16
		match idx:
			2: fpath = "res://font/Venice16.fnt"; sz = 32
			3: fpath = "res://font/SuperBlack12.fnt"; sz = 12
			4: fpath = "res://font/SuperBlack12.fnt"; sz = 24
			5: fpath = "res://font/SuperWhite12.fnt"; sz = 12
			6: fpath = "res://font/SuperWhite12.fnt"; sz = 24
		if ResourceLoader.exists(fpath):
			t.default_font = load(fpath)
		t.default_font_size = sz
		theme = t
	if preview_edit:
		preview_edit.remove_theme_font_override("font")
		preview_edit.remove_theme_font_size_override("font_size")
	# keep canvas preview scale in sync with selection (1x for odd, 2x for even >0)
	preview_scale = 2.0 if idx % 2 == 0 else 1.0
	preview_canvas.queue_redraw()
	_set_status("Applied theme to root: %s (live, no reload needed)" % tpath.get_file())
