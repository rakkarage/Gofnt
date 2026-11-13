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
var sel_id: int = -1
var _updating_ui := false

func _ready() -> void:
	name = "JuicyFontEditor"
	data = BMFontData.new()
	_build_ui()
	_set_status("Drop-ready: use Open .fnt to load a bitmap font (text BMFont) and its atlas PNG.")

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

	var bar := HBoxContainer.new()
	left.add_child(bar)
	var open_btn := Button.new(); open_btn.text = "Open .fnt"; open_btn.pressed.connect(_on_open); bar.add_child(open_btn)
	var save_fnt_btn := Button.new(); save_fnt_btn.text = "Save .fnt"; save_fnt_btn.pressed.connect(_on_save_fnt); bar.add_child(save_fnt_btn)
	var save_png_btn := Button.new(); save_png_btn.text = "Save PNG"; save_png_btn.pressed.connect(_on_save_png); bar.add_child(save_png_btn)
	bar.add_child(VSeparator.new())
	var autoslice_btn := Button.new(); autoslice_btn.text = "Auto-slice selected"; autoslice_btn.pressed.connect(_on_autoslice_selected); bar.add_child(autoslice_btn)
	var autoslice_all_btn := Button.new(); autoslice_all_btn.text = "Auto-slice all"; autoslice_all_btn.pressed.connect(_on_autoslice_all); bar.add_child(autoslice_all_btn)
	var repack_btn := Button.new(); repack_btn.text = "Repack atlas"; repack_btn.pressed.connect(_on_repack); bar.add_child(repack_btn)
	status_lbl = Label.new(); status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; status_lbl.text = ""; status_lbl.clip_text = true; bar.add_child(status_lbl)

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
	preview_edit.custom_minimum_size = Vector2(0, 60)
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
	var hl := Label.new(); hl.text = "Glyphs (click atlas or list)"; vb.add_child(hl)
	glyph_list = ItemList.new(); glyph_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; glyph_list.custom_minimum_size = Vector2(0, 180)
	glyph_list.item_selected.connect(_on_list_selected)
	vb.add_child(glyph_list)
	var grid := GridContainer.new(); grid.columns = 2; vb.add_child(grid)
	for key in ["x", "y", "width", "height", "xoffset", "yoffset", "xadvance"]:
		var l := Label.new(); l.text = key; grid.add_child(l)
		var s := SpinBox.new(); s.min_value = -4096; s.max_value = 4096; s.step = 1; s.allow_greater = true; s.allow_lesser = true
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(v): _on_prop_changed(key, int(v)))
		grid.add_child(s)
		prop_spin[key] = s
	var hint := Label.new(); hint.text = "Tip: drag in atlas to move, drag corners/edges to resize. Mouse wheel zooms, middle-drag pans."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	if data == null: return
	for id in data.sorted_char_ids():
		var ch := "space" if id == 32 else String.chr(id)
		var c: Dictionary = data.chars[id]
		var idx := glyph_list.add_item("%s  (%d)  adv:%s" % [ch, id, str(c.get("xadvance", 0))])
		glyph_list.set_item_metadata(idx, id)

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
	sel_id = id
	_sync_props()
	# select in list
	for i in glyph_list.item_count:
		if int(glyph_list.get_item_metadata(i)) == id:
			glyph_list.select(i); glyph_list.ensure_current_is_visible(); break

func _on_list_selected(idx: int) -> void:
	sel_id = int(glyph_list.get_item_metadata(idx))
	atlas.selected_id = sel_id
	atlas.queue_redraw()
	_sync_props()

func _sync_props() -> void:
	_updating_ui = true
	var has := sel_id != -1 and data.chars.has(sel_id)
	for k in prop_spin.keys():
		var s: SpinBox = prop_spin[k]
		s.editable = has
		s.value = int(data.chars[sel_id].get(k, 0)) if has else 0
	_updating_ui = false

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
	var s := 2.0
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
