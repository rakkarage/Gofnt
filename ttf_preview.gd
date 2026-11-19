@tool
extends Control

## Live paint-chip preview for the TTF import dialog.
## Mirrors the fill / outline settings so choices are visible before importing.

@export var font: Font
@export var fill_mode: int = 0
@export var gradient_dir: int = 1
@export var color1: Color = Color.WHITE
@export var color2: Color = Color(0.7, 0.85, 1.0, 1.0)
@export var proc_effect: int = 0
@export var proc_color: Color = Color.WHITE
@export var outline_px: int = 0
@export var outline_color: Color = Color.BLACK
@export var sample_text: String = "Ag"


func _draw() -> void:
	var r := size
	if r.x <= 4.0 or r.y <= 4.0:
		return

	# Transparency checkerboard so the fill reads as an atlas background.
	var cell := 12.0
	var x := 0.0
	while x < r.x:
		var y := 0.0
		while y < r.y:
			var w := minf(cell, r.x - x)
			var h := minf(cell, r.y - y)
			var dark := (int(x / cell) + int(y / cell)) % 2 == 0
			draw_rect(Rect2(x, y, w, h), Color(0.09, 0.11, 0.14, 1.0) if dark else Color(0.13, 0.16, 0.20, 1.0))
			y += cell
		x += cell

	var fnt: Font = font
	if fnt == null:
		fnt = get_theme_font("font")
	if fnt == null:
		fnt = ThemeDB.fallback_font

	var fs := clampf(r.y * 0.60, 11.0, 52.0)
	var ts := fnt.get_string_size(sample_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2((r.x - ts.x) * 0.5, r.y * 0.16 + fs)

	if outline_px > 0:
		var op: int = clampi(outline_px, 1, 8)
		for dy in range(-op, op + 1):
			for dx in range(-op, op + 1):
				if maxi(absi(dx), absi(dy)) < op:
					continue
				draw_string(fnt, base + Vector2(dx, dy), sample_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline_color)

	draw_string(fnt, base, sample_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color1 if fill_mode != 2 else proc_color)

	# Paint chip: exact fill style + outline thickness, at the bottom.
	var chip := Rect2(10.0, r.y - 18.0, maxf(1.0, r.x - 20.0), 9.0)
	draw_rect(chip, Color(0.04, 0.05, 0.07, 1.0))
	if fill_mode == 1:
		_draw_gradient(chip)
	elif fill_mode == 2:
		draw_rect(chip, proc_color * Color(0.45, 0.45, 0.45, 1.0))
		_draw_procedural(chip)
	else:
		draw_rect(chip, color1)
	if outline_px > 0:
		var w := maxf(1.0, float(clampi(outline_px, 1, 8)) * 0.5)
		draw_rect(Rect2(chip.position.x, chip.position.y, chip.size.x, w), outline_color)
		draw_rect(Rect2(chip.position.x, chip.position.y + chip.size.y - w, chip.size.x, w), outline_color)
		draw_rect(Rect2(chip.position.x, chip.position.y, w, chip.size.y), outline_color)
		draw_rect(Rect2(chip.position.x + chip.size.x - w, chip.position.y, w, chip.size.y), outline_color)


func _draw_gradient(chip: Rect2) -> void:
	if gradient_dir == 1:
		var n: int = maxi(1, int(chip.size.y))
		for i in range(n):
			var t := float(i) / float(maxi(1, n - 1))
			draw_rect(Rect2(chip.position.x, chip.position.y + i, chip.size.x, 1.0), color1.lerp(color2, t))
		return
	var m: int = maxi(1, int(chip.size.x))
	for i in range(m):
		var t := float(i) / float(maxi(1, m - 1))
		if gradient_dir == 4:
			t = 1.0 - t
		elif gradient_dir == 3:
			t = clampf(t * 0.7 + 0.15, 0.0, 1.0)
		draw_rect(Rect2(chip.position.x + i, chip.position.y, 1.0, chip.size.y), color1.lerp(color2, t))


func _draw_procedural(chip: Rect2) -> void:
	match proc_effect:
		0: # scanlines
			var y := 0.0
			while y < chip.size.y:
				draw_rect(Rect2(chip.position.x, chip.position.y + y, chip.size.x, 1.0), proc_color)
				y += 3.0
		1: # bayer dither
			var bayer := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
			for gy in range(int(chip.size.y / 2.0)):
				for gx in range(int(chip.size.x / 2.0)):
					if float(bayer[gy % 4][gx % 4]) / 16.0 < 0.5:
						draw_rect(Rect2(chip.position.x + gx * 2, chip.position.y + gy * 2, 2.0, 2.0), proc_color)
		2: # checker
			for gy in range(int(chip.size.y / 4.0)):
				for gx in range(int(chip.size.x / 4.0)):
					if (gx + gy) % 2 == 0:
						draw_rect(Rect2(chip.position.x + gx * 4, chip.position.y + gy * 4, 4.0, 4.0), proc_color)
		3: # noise grain (deterministic)
			for gy in range(int(chip.size.y / 2.0)):
				for gx in range(int(chip.size.x / 2.0)):
					var n: float = fmod(absf(sin(float(gx * 12.9898 + gy * 78.233)) * 43758.5453), 1.0)
					if n > 0.55:
						draw_rect(Rect2(chip.position.x + gx * 2, chip.position.y + gy * 2, 2.0, 2.0), proc_color)
		4: # edge tint / bevel
			draw_rect(Rect2(chip.position.x, chip.position.y, chip.size.x, 1.0), proc_color.lerp(Color.WHITE, 0.5))
			draw_rect(Rect2(chip.position.x, chip.position.y + chip.size.y - 1.0, chip.size.x, 1.0), Color(0.0, 0.0, 0.0, 0.55))
			draw_rect(Rect2(chip.position.x, chip.position.y, 1.0, chip.size.y), proc_color.lerp(Color.WHITE, 0.25))
