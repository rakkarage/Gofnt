class_name BMFontData
extends RefCounted

var info: Dictionary = {}
var common: Dictionary = {}
var pages: Array[Dictionary] = []
var chars: Dictionary = {} # id -> Dictionary
var kernings: Array[Dictionary] = []
var image: Image
var texture: ImageTexture
var fnt_path: String = ""
var image_path: String = ""

func clear() -> void:
	info.clear(); common.clear(); pages.clear(); chars.clear(); kernings.clear()
	image = null; texture = null; fnt_path = ""; image_path = ""

func load_fnt(path: String) -> Error:
	clear()
	fnt_path = path
	var text := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
	else:
		# In exports, .fnt sources may be imported as FontFile resources (not kept as raw files).
		# Try common raw-text fallbacks for bundled demos.
		var err := FileAccess.get_open_error()
		var candidates: PackedStringArray = []
		if path.begins_with("res://") and path.ends_with(".fnt"):
			candidates.append(path + ".txt")
			candidates.append(path.get_basename() + ".txt")
		var loaded := false
		for cand in candidates:
			if FileAccess.file_exists(cand):
				var cf := FileAccess.open(cand, FileAccess.READ)
				if cf != null:
					fnt_path = cand
					text = cf.get_as_text()
					loaded = true
					break
		if not loaded:
			# Last resort: if bytes are available, try decoding as text.
			if FileAccess.file_exists(path):
				var bytes := FileAccess.get_file_as_bytes(path)
				if not bytes.is_empty():
					text = bytes.get_string_from_utf8()
					loaded = true
		if not loaded:
			return err
	if text.strip_edges().begins_with("<"):
		return _parse_xml(text)
	return _parse_text(text)

func _to_num(v: String) -> Variant:
	if v.is_valid_int(): return int(v)
	if v.is_valid_float(): return float(v)
	return v

func _set_section(kind: String, attrs: Dictionary) -> void:
	match kind:
		"info": info = attrs
		"common": common = attrs
		"page": pages.append(attrs)
		"char":
			var id := int(attrs.get("id", -1))
			if id >= 0:
				attrs.erase("letter")
				chars[id] = attrs
		"kerning": kernings.append(attrs)

func _parse_text(text: String) -> Error:
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty(): continue
		var kind := line.get_slice(" ", 0)
		if kind not in ["info","common","page","char","kerning"]:
			continue
		var attrs: Dictionary = {}
		var i := kind.length()
		while i < line.length():
			while i < line.length() and line[i] <= " ": i += 1
			if i >= line.length(): break
			var eq := line.find("=", i)
			if eq == -1: break
			var key := line.substr(i, eq - i)
			i = eq + 1
			var val := ""
			if i < line.length() and line[i] == '"':
				var endq := line.find('"', i + 1)
				if endq == -1: endq = line.length()
				val = line.substr(i + 1, endq - i - 1)
				i = endq + 1
			else:
				var end := i
				while end < line.length() and line[end] > " ": end += 1
				val = line.substr(i, end - i)
				i = end
			attrs[key] = _to_num(val)
		_set_section(kind, attrs)
	if chars.is_empty():
		return ERR_PARSE_ERROR
	return _load_page_image()

func _parse_xml(text: String) -> Error:
	var p := XMLParser.new()
	if p.open_buffer(text.to_utf8_buffer()) != OK:
		return ERR_PARSE_ERROR
	while p.read() == OK:
		if p.get_node_type() in [XMLParser.NODE_ELEMENT, XMLParser.NODE_ELEMENT_END]:
			var kind := p.get_node_name()
			if kind in ["info","common","page","char","kerning"]:
				var attrs: Dictionary = {}
				for j in p.get_attribute_count():
					attrs[p.get_attribute_name(j)] = _to_num(p.get_attribute_value(j))
				_set_section(kind, attrs)
	if chars.is_empty():
		return ERR_PARSE_ERROR
	return _load_page_image()

func _load_page_image() -> Error:
	if pages.is_empty():
		return ERR_FILE_NOT_FOUND
	var file: String = str(pages[0].get("file", ""))
	if file.is_empty():
		return ERR_FILE_NOT_FOUND
	image_path = fnt_path.get_base_dir().path_join(file)
	image = _load_image_compat(image_path)
	if image == null:
		image = _load_image_compat(fnt_path.get_base_dir().path_join(file))
	if image == null:
		# Last resort for web/packed exports: extract the atlas image from the
		# imported FontFile resource (which is always available when .fnt is).
		image = _load_image_from_fontfile(fnt_path)
	if image == null:
		return ERR_FILE_CANT_OPEN
	texture = ImageTexture.create_from_image(image)
	common["scaleW"] = image.get_width()
	common["scaleH"] = image.get_height()
	return OK

func _load_image_compat(path: String) -> Image:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		# Web/packed exports: prefer ResourceLoader for imported textures/resources.
		var candidates: PackedStringArray = [path]
		# Workarounds for export filters/packaging quirks: allow atlas bytes under alternate names.
		for suffix: String in [".txt", ".bytes", ".png", ".bin"]:
			var alt: String = path + suffix
			if not candidates.has(alt):
				candidates.append(alt)
		if path.get_extension().to_lower() == "png":
			var noext := path.get_basename()
			for alt: String in [noext + ".png.txt", noext + ".bin", noext + ".bytes"]:
				if not candidates.has(alt):
					candidates.append(alt)
		for p in candidates:
			var res = null
			if ResourceLoader.exists(p):
				res = ResourceLoader.load(p)
			if res == null:
				res = load(p)
			if res is Texture2D:
				var tex_img := (res as Texture2D).get_image()
				if tex_img != null:
					return tex_img.duplicate()
			elif res is Image:
				return (res as Image).duplicate()
		for p in candidates:
			var bytes := FileAccess.get_file_as_bytes(p)
			if bytes.is_empty():
				continue
			var lower := p.to_lower()
			# try formats based on candidate and original path
			var fmts: PackedStringArray = []
			if lower.ends_with(".png") or path.to_lower().ends_with(".png"):
				fmts.append("png")
			if lower.ends_with(".webp") or path.to_lower().ends_with(".webp"):
				fmts.append("webp")
			if lower.ends_with(".jpg") or lower.ends_with(".jpeg") or path.to_lower().ends_with(".jpg") or path.to_lower().ends_with(".jpeg"):
				fmts.append("jpg")
			if lower.ends_with(".bmp") or path.to_lower().ends_with(".bmp"):
				fmts.append("bmp")
			if fmts.is_empty():
				fmts = PackedStringArray(["png", "webp", "jpg", "bmp"])
			var img := Image.new()
			for fmt in fmts:
				var err := ERR_FILE_UNRECOGNIZED
				match fmt:
					"png": err = img.load_png_from_buffer(bytes)
					"webp": err = img.load_webp_from_buffer(bytes)
					"jpg": err = img.load_jpg_from_buffer(bytes)
					"bmp": err = img.load_bmp_from_buffer(bytes)
				if err == OK:
					return img
			# last-chance generic attempts
			for try_fmt in ["png", "webp", "jpg", "bmp"]:
				var e2 := ERR_FILE_UNRECOGNIZED
				match try_fmt:
					"png": e2 = img.load_png_from_buffer(bytes)
					"webp": e2 = img.load_webp_from_buffer(bytes)
					"jpg": e2 = img.load_jpg_from_buffer(bytes)
					"bmp": e2 = img.load_bmp_from_buffer(bytes)
				if e2 == OK:
					return img
		# Fallback for editor/desktop cases.
		var abs_path := ProjectSettings.globalize_path(path)
		if abs_path != "":
			var fimg := Image.load_from_file(abs_path)
			if fimg != null:
				return fimg
		return null
	var img := Image.load_from_file(path)
	if img == null and not path.is_absolute_path():
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	return img

func _load_image_from_fontfile(fnt_path: String) -> Image:
	if fnt_path.is_empty():
		return null
	var candidates: PackedStringArray = []
	if fnt_path.ends_with(".txt"):
		candidates.append(fnt_path.substr(0, fnt_path.length() - 4))
	else:
		candidates.append(fnt_path)
	# Also try a .fnt sibling in case fnt_path points at a raw text copy.
	var base := fnt_path.get_basename()
	if not base.ends_with(".fnt"):
		candidates.append(base + ".fnt")
	for cp in candidates:
		if cp.is_empty():
			continue
		if not ResourceLoader.exists(cp):
			continue
		var res = ResourceLoader.load(cp)
		if res is FontFile:
			var ff := res as FontFile
			for sz in [0, 8, 12, 16, 24, 32]:
				var cnt := ff.get_texture_count(0, Vector2i(sz, 0))
				if cnt <= 0:
					continue
				for ti in range(cnt):
					var img := ff.get_texture_image(0, Vector2i(sz, 0), ti)
					if img != null:
						return img.duplicate()
	return null

func sorted_char_ids() -> Array:
	var ids := chars.keys()
	ids.sort()
	return ids

func to_fnt_text() -> String:
	var out := PackedStringArray()
	out.append(_fmt_line("info", info, ["face","charset"]))
	out.append(_fmt_line("common", common, []))
	for p in pages:
		out.append(_fmt_line("page", p, ["file"]))
	var ids := sorted_char_ids()
	out.append("chars count=%d" % ids.size())
	# Compute per-field widths so char rows line up in columns.
	var char_widths: Dictionary = {}
	var letter_width := 0
	for id in ids:
		var c: Dictionary = chars[id]
		for k in c.keys():
			var token := "%s=%s" % [k, str(c[k])]
			var L := token.length()
			if not char_widths.has(k) or L > int(char_widths[k]):
				char_widths[k] = L
		# (letter width not padded; keeps trailing whitespace out of the file)
	for id in ids:
		var c: Dictionary = chars[id]
		var letter := "space" if id == 32 else String.chr(id)
		var ltoken := "letter=\"%s\"" % letter
		out.append(_fmt_line("char", c, [], char_widths) + " " + ltoken)
	if not kernings.is_empty():
		out.append("kernings count=%d" % kernings.size())
		for k in kernings:
			out.append(_fmt_line("kerning", k, []))
	return "\n".join(out) + "\n"

func _fmt_line(kind: String, d: Dictionary, quoted: Array, widths: Dictionary = {}) -> String:
	var parts := PackedStringArray([kind])
	for k in d.keys():
		var v = d[k]
		var token: String
		if k in quoted or (k == "file" and kind == "page"):
			token = "%s=\"%s\"" % [k, str(v)]
		else:
			token = "%s=%s" % [k, str(v)]
		if widths.has(k):
			token = token.rpad(int(widths[k]))
		parts.append(token)
	return " ".join(parts)

func save_fnt(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	if not pages.is_empty():
		var page_file := path.get_file().get_basename() + ".png"
		if image_path != "":
			page_file = image_path.get_file()
		pages[0]["file"] = page_file
	f.store_string(to_fnt_text())
	return OK

func save_png(path: String) -> Error:
	if image == null: return ERR_UNCONFIGURED
	return image.save_png(path)

func get_stats() -> Dictionary:
	var ids := sorted_char_ids()
	var area := 0
	var used_w := 0
	var used_h := 0
	var advances: Array[int] = []
	for id in ids:
		var c: Dictionary = chars[id]
		var gw := int(c.get("width",0)); var gh := int(c.get("height",0))
		area += gw * gh
		used_w = maxi(used_w, int(c.get("x",0)) + gw)
		used_h = maxi(used_h, int(c.get("y",0)) + gh)
		advances.append(int(c.get("xadvance",0)))
	advances.sort()
	var atlas_w := int(common.get("scaleW", image.get_width() if image else 0))
	var atlas_h := int(common.get("scaleH", image.get_height() if image else 0))
	var atlas_area := atlas_w * atlas_h
	var med := 0
	if not advances.is_empty(): med = advances[advances.size()/2.0]
	return {
		"glyphs": ids.size(),
		"kern_pairs": kernings.size(),
		"atlas_w": atlas_w,
		"atlas_h": atlas_h,
		"atlas_area": atlas_area,
		"glyph_area": area,
		"fill_ratio": (float(area)/float(atlas_area)) if atlas_area > 0 else 0.0,
		"used_bounds": Vector2i(used_w, used_h),
		"line_height": int(common.get("lineHeight",0)),
		"base": int(common.get("base",0)),
		"median_xadvance": med,
	}
