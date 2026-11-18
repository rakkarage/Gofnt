@tool
class_name CharPreview
extends Control

var data: BMFontData = null

# Colors for guides and glyphs
var col_baseline := Color(1.0, 0.55, 0.25, 0.9)
var col_line_height := Color(0.45, 0.75, 1.0, 0.6)
var col_bg := Color(0.08, 0.09, 0.11, 1.0)
var col_text_dim := Color(1, 1, 1, 0.85)

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 80)
	queue_redraw()

func set_data(d: BMFontData) -> void:
	data = d
	_update_min_height()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_min_height()
		queue_redraw()

func _update_min_height() -> void:
	if data == null or data.texture == null:
		custom_minimum_size.y = 80
		return
	var lh := maxi(1, int(data.common.get("lineHeight", 16)))
	var pad := 8
	var rows := _layout_rows().size()
	custom_minimum_size.y = float(pad * 2 + maxi(1, rows) * (lh + 6))

func _get_char_ids() -> Array:
	if data == null:
		return []
	var ids: Array = []
	# Show all defined chars in sorted order (includes space if present)
	for id in data.sorted_char_ids():
		ids.append(int(id))
	return ids

func _layout_rows() -> Array:
	# Returns array of arrays of char ids, wrapped to fit width
	var rows: Array = []
	var ids := _get_char_ids()
	if ids.is_empty():
		return rows
	var pad := 8
	var x := pad
	var max_w := maxi(40, int(size.x) - pad)
	var row: Array = []
	for id in ids:
		var c: Dictionary = data.chars[id]
		var adv := maxi(1, int(c.get("xadvance", 0)))
		# Ensure very narrow glyphs still take some space
		var cell_w := maxi(adv, int(c.get("width", 0)) + int(c.get("xoffset", 0)))
		cell_w = maxi(cell_w, 4)
		if x + cell_w > max_w and not row.is_empty():
			rows.append(row)
			row = []
			x = pad
		row.append(id)
		x += cell_w + 1
	if not row.is_empty():
		rows.append(row)
	return rows

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, col_bg)
	if data == null or data.texture == null or data.image == null:
		var f := get_theme_default_font()
		if f:
			draw_string(f, Vector2(8, 20), "No font loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.82, 0.8))
		return
	var lh := maxi(1, int(data.common.get("lineHeight", 16)))
	var base := int(data.common.get("base", lh))
	var pad := 8
	var rows := _layout_rows()
	var y := pad
	var tex: Texture2D = data.texture
	for row in rows:
		# Guidelines for this line: baseline and line-height bottom (line box)
		draw_line(Vector2(0, y + base), Vector2(size.x, y + base), col_baseline, 1.0)
		draw_line(Vector2(0, y + lh), Vector2(size.x, y + lh), col_line_height, 1.0)
		var x := pad
		for id in row:
			if not data.chars.has(id):
				continue
			var c: Dictionary = data.chars[id]
			var gw := int(c.get("width", 0))
			var gh := int(c.get("height", 0))
			var gx := int(c.get("x", 0))
			var gy := int(c.get("y", 0))
			var xoff := int(c.get("xoffset", 0))
			var yoff := int(c.get("yoffset", 0))
			var adv := maxi(1, int(c.get("xadvance", 0)))
			if gw > 0 and gh > 0 and tex != null:
				var src := Rect2(gx, gy, gw, gh)
				var dst := Rect2(Vector2(x + xoff, y + yoff), Vector2(gw, gh))
				draw_texture_rect_region(tex, dst, src)
			var cell_w := maxi(adv, gw + xoff)
			cell_w = maxi(cell_w, 4)
			x += cell_w + 1
		y += lh + 6
	# Legend hint
	var f2 := get_theme_default_font()
	if f2 and not rows.is_empty():
		var legend_y := float(mini(int(size.y) - 4, y - 2))
		# draw small legend if space
		if legend_y > lh + pad:
			pass
