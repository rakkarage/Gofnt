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
var _pan_tween: Tween = null
const HANDLE := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_ALL

func set_data(d: BMFontData) -> void:
	data = d
	selected_id = -1
	# Reset the view when a new font is loaded so a previously panned/zoomed
	# (possibly off-screen) view doesn't hide the freshly loaded atlas.
	zoom = 4.0
	pan = Vector2(20, 20)
	queue_redraw()

func _kill_pan_tween() -> void:
	if _pan_tween and is_instance_valid(_pan_tween):
		_pan_tween.kill()
	_pan_tween = null

func focus_glyph(id: int) -> void:
	_kill_pan_tween()
	selected_id = id
	if data == null:
		queue_redraw(); return
	if not data.chars.has(id):
		queue_redraw(); return
	var r := _glyph_rect(id)
	if r.size.x <= 0 or r.size.y <= 0:
		# No usable rect: just center the origin so the user can place it.
		pan = size * 0.5 - Vector2(zoom * 4.0, zoom * 4.0)
		queue_redraw(); return
	var center := Vector2(r.position) + Vector2(r.size) * 0.5
	# If the glyph (with a small margin) doesn't fit at the current zoom, zoom
	# out just enough so it becomes visible rather than staying off-screen.
	var margin := 24.0
	var avail := size - Vector2(margin * 2.0, margin * 2.0)
	if avail.x > 0 and avail.y > 0:
		var need_zoom_x := avail.x / float(r.size.x + 8)
		var need_zoom_y := avail.y / float(r.size.y + 8)
		var need_zoom := minf(need_zoom_x, need_zoom_y)
		if need_zoom < zoom:
			zoom = clampf(need_zoom, 0.5, 32.0)
	pan = size * 0.5 - center * zoom
	queue_redraw()

func reset_view() -> void:
	_kill_pan_tween()
	zoom = 4.0
	pan = Vector2(20, 20)
	queue_redraw()

func _tween_pan(target: Vector2) -> void:
	_kill_pan_tween()
	_pan_tween = create_tween()
	_pan_tween.tween_property(self, "pan", target, 0.3).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

func _constrain_pan() -> void:
	if data == null or data.texture == null:
		return
	var ts := _tex_size()
	if ts.x <= 0 or ts.y <= 0:
		return
	# Work in world/texture space, then convert deltas back to screen space.
	var view_rect := Rect2(-pan / zoom, size / zoom)
	var map_rect := Rect2(Vector2.ZERO, ts).grow(8.0 / zoom)
	if view_rect.intersects(map_rect):
		return
	var delta := Vector2.ZERO
	if view_rect.position.x > map_rect.position.x:
		delta.x += map_rect.position.x - view_rect.position.x
	if view_rect.end.x < map_rect.end.x:
		delta.x -= view_rect.end.x - map_rect.end.x
	if view_rect.position.y > map_rect.position.y:
		delta.y += map_rect.position.y - view_rect.position.y
	if view_rect.end.y < map_rect.end.y:
		delta.y -= view_rect.end.y - map_rect.end.y
	_tween_pan(pan + delta * zoom)

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
			_kill_pan_tween()
			var old_zoom := zoom
			zoom = clampf(zoom * 1.1, 0.5, 32.0)
			# Keep the point under the cursor anchored so zoom doesn't drift off-screen.
			if zoom != old_zoom and old_zoom > 0.0:
				pan = mb.position - (mb.position - pan) * (zoom / old_zoom)
			if zoom != old_zoom:
				_constrain_pan()
			queue_redraw(); accept_event(); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_kill_pan_tween()
			var old_zoom2 := zoom
			zoom = clampf(zoom / 1.1, 0.5, 32.0)
			if zoom != old_zoom2 and old_zoom2 > 0.0:
				pan = mb.position - (mb.position - pan) * (zoom / old_zoom2)
			if zoom != old_zoom2:
				_constrain_pan()
			queue_redraw(); accept_event(); return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_kill_pan_tween()
				dragging = true; drag_mode = "pan"; drag_start_mouse = mb.position; drag_start_rect = Rect2i(Vector2i(pan), Vector2i.ZERO); accept_event(); return
			else:
				dragging = false; drag_mode = ""
				_constrain_pan()
				accept_event(); return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_kill_pan_tween()
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
