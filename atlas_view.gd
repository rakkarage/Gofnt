@tool
class_name FontAtlasView
extends Control

signal glyph_selected(id: int)
signal glyph_changed(id: int)

var data: BMFontData
var zoom: float = 4.0
var pan: Vector2 = Vector2(20, 20)
var selected_id: int = -1
var dragging := false
var drag_mode := "" # move, n,s,e,w,nw,ne,sw,se
var drag_start_mouse := Vector2.ZERO
var drag_start_rect := Rect2i()
var hover_mode := ""
const HANDLE := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL

func set_data(d: BMFontData) -> void:
	data = d
	selected_id = -1
	queue_redraw()

func _tex_size() -> Vector2:
	if data and data.texture:
		return data.texture.get_size()
	return Vector2.ZERO

func _to_local_tex(p: Vector2) -> Vector2:
	return (p - pan) / zoom

func _glyph_rect(id: int) -> Rect2i:
	var c: Dictionary = data.chars[id]
	return Rect2i(int(c.get("x",0)), int(c.get("y",0)), int(c.get("width",0)), int(c.get("height",0)))

func _set_glyph_rect(id: int, r: Rect2i) -> void:
	var c: Dictionary = data.chars[id]
	c["x"] = r.position.x; c["y"] = r.position.y
	c["width"] = maxi(0, r.size.x); c["height"] = maxi(0, r.size.y)
	data.chars[id] = c

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.12, 0.16, 1.0))
	if data == null or data.texture == null:
		draw_string(get_theme_default_font(), Vector2(20, 30), "Load a .fnt to start", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.78, 0.86, 0.96, 0.9))
		draw_string(get_theme_default_font(), Vector2(20, 54), "Tip: drag files in or use Open / Import buttons above", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.62, 0.72, 0.84, 0.8))
		return
	var ts := _tex_size()
	var dst := Rect2(pan, ts * zoom)
	# checker
	var cs := 8.0 * zoom
	var c1 := Color(0.28, 0.30, 0.36); var c2 := Color(0.36, 0.39, 0.46)
	draw_rect(dst, c1)
	var cols := int(ceil(ts.x / 8.0)); var rows := int(ceil(ts.y / 8.0))
	for y in rows:
		for x in cols:
			if (x + y) % 2 == 0:
				var r := Rect2(dst.position + Vector2(x, y) * cs, Vector2(cs, cs)).intersection(dst)
				if r.size.x > 0 and r.size.y > 0:
					draw_rect(r, c2)
	draw_texture_rect(data.texture, dst, false)
	# glyphs
	for id in data.sorted_char_ids():
		var r := _glyph_rect(id)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var sr := Rect2(dst.position + Vector2(r.position) * zoom, Vector2(r.size) * zoom)
		var col := Color(0.35, 0.78, 1.0, 0.85)
		if id == selected_id:
			col = Color(1.0, 0.62, 0.28, 1.0)
			draw_rect(sr, Color(1.0, 0.62, 0.28, 0.12), true)
		draw_rect(sr, col, false, 1.0)
	# handles for selected
	if selected_id != -1 and data.chars.has(selected_id):
		var r := _glyph_rect(selected_id)
		var sr := Rect2(dst.position + Vector2(r.position) * zoom, Vector2(r.size) * zoom)
		for hp in _handle_points(sr):
			draw_rect(Rect2(hp - Vector2(3, 3), Vector2(6, 6)), Color(0.98, 0.99, 1.0))
			draw_rect(Rect2(hp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.62, 0.28), false, 1.0)

func _handle_points(sr: Rect2) -> Array[Vector2]:
	return [
		sr.position, sr.position + Vector2(sr.size.x/2,0), sr.position + Vector2(sr.size.x,0),
		sr.position + Vector2(0,sr.size.y/2), sr.position + sr.size/2, sr.position + Vector2(sr.size.x,sr.size.y/2),
		sr.position + Vector2(0,sr.size.y), sr.position + Vector2(sr.size.x/2,sr.size.y), sr.end
	]

func _hit_handle(sr: Rect2, p: Vector2) -> String:
	var pts := _handle_points(sr)
	var modes := ["nw","n","ne","w","move","e","sw","s","se"]
	for i in pts.size():
		if Rect2(pts[i]-Vector2(HANDLE,HANDLE), Vector2(HANDLE*2,HANDLE*2)).has_point(p):
			return modes[i]
	if sr.has_point(p):
		return "move"
	return ""

func _pick_glyph(p: Vector2) -> int:
	var best := -1
	var best_area := 1 << 30
	for id in data.sorted_char_ids():
		var r := _glyph_rect(id)
		if r.size.x <= 0 or r.size.y <= 0: continue
		if r.has_point(Vector2i(p.floor())):
			var a := r.size.x * r.size.y
			if a < best_area:
				best_area = a; best = id
	return best

func _gui_input(event: InputEvent) -> void:
	if data == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = clampf(zoom * 1.1, 0.5, 32.0); queue_redraw(); accept_event(); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = clampf(zoom / 1.1, 0.5, 32.0); queue_redraw(); accept_event(); return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed; drag_mode = "pan"; drag_start_mouse = mb.position; drag_start_rect = Rect2i(Vector2i(pan), Vector2i.ZERO); accept_event(); return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var tp := _to_local_tex(mb.position)
				if selected_id != -1 and data.chars.has(selected_id):
					var r := _glyph_rect(selected_id)
					var sr := Rect2(pan + Vector2(r.position)*zoom, Vector2(r.size)*zoom)
					var hm := _hit_handle(sr, mb.position)
					if hm != "":
						dragging = true; drag_mode = hm; drag_start_mouse = mb.position; drag_start_rect = r
						accept_event(); queue_redraw(); return
				var id := _pick_glyph(tp)
				selected_id = id
				glyph_selected.emit(id)
				if id != -1:
					dragging = true; drag_mode = "move"; drag_start_mouse = mb.position; drag_start_rect = _glyph_rect(id)
				queue_redraw(); accept_event()
			else:
				if dragging and drag_mode != "pan" and selected_id != -1:
					glyph_changed.emit(selected_id)
				dragging = false; drag_mode = ""
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			if drag_mode == "pan":
				pan = Vector2(drag_start_rect.position) + (mm.position - drag_start_mouse)
			elif selected_id != -1 and data.chars.has(selected_id):
				var delta := (mm.position - drag_start_mouse) / zoom
				var di := Vector2i(roundi(delta.x), roundi(delta.y))
				var r := drag_start_rect
				match drag_mode:
					"move": r.position += di
					"se": r.size += di
					"nw": r.position += di; r.size -= di
					"ne": r.position.y += di.y; r.size.y -= di.y; r.size.x += di.x
					"sw": r.position.x += di.x; r.size.x -= di.x; r.size.y += di.y
					"n": r.position.y += di.y; r.size.y -= di.y
					"s": r.size.y += di.y
					"w": r.position.x += di.x; r.size.x -= di.x
					"e": r.size.x += di.x
				if r.size.x < 0: r.position.x += r.size.x; r.size.x = -r.size.x
				if r.size.y < 0: r.position.y += r.size.y; r.size.y = -r.size.y
				var ts := Vector2i(_tex_size())
				r.position.x = clampi(r.position.x, 0, maxi(0, ts.x - r.size.x))
				r.position.y = clampi(r.position.y, 0, maxi(0, ts.y - r.size.y))
				_set_glyph_rect(selected_id, r)
				glyph_changed.emit(selected_id)
			queue_redraw(); accept_event()
		else:
			# hover cursor
			if selected_id != -1 and data.chars.has(selected_id):
				var r := _glyph_rect(selected_id)
				var sr := Rect2(pan + Vector2(r.position)*zoom, Vector2(r.size)*zoom)
				var hm := _hit_handle(sr, mm.position)
				match hm:
					"move": mouse_default_cursor_shape = Control.CURSOR_MOVE
					"n","s": mouse_default_cursor_shape = Control.CURSOR_VSIZE
					"e","w": mouse_default_cursor_shape = Control.CURSOR_HSIZE
					"nw","se": mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
					"ne","sw": mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
					_: mouse_default_cursor_shape = Control.CURSOR_ARROW
