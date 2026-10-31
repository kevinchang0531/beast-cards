class_name CardView
extends Control
## 一張卡片的畫法（全部用 _draw 畫，任意大小都清楚）。
## mode "full"：完整卡面（名字、HP、卡圖、招式、弱點、撤退）—— 手牌放大、詳細面板、卡包、牌組編輯用
## mode "mini"：場上用（大卡圖、名字、HP 條、能量、狀態）
## face_up = false 畫卡背。

signal pressed(view: CardView)
signal hovered(view: CardView)
signal unhovered(view: CardView)

const BASE := Vector2(200, 280)
const TRAINER_COLOR := Color("8a6cc8")
const HOLD_MS := 400
const TAP_SLOP := 12.0

var id := ""
var mode := "full"
var face_up := true
var beast = null              # 場上靈獸資料（Battle 的 beast dict）
var battle: Battle = null
var highlight := false        # 可以點（金框）
var selected := false         # 已選（藍框）
var dim := false
var count_label := ""         # 右上角張數（牌組編輯用）
var shake := 0.0
var flash := 0.0
## 牌組編輯用：滑鼠移上去只預覽、放開才算點；手指點一下加入、按住預覽、拖動是捲動
var tap_mode := false
var down_ms := 0
var down_pos := Vector2.ZERO
var down_touch := false
var holding := false
var hover_sent := false

static var _tex_cache := {}


static func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		if path.begins_with("user://"):
			var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
			_tex_cache[path] = ImageTexture.create_from_image(img) if img else null
		else:
			_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		if not tap_mode:
			hovered.emit(self))
	mouse_exited.connect(func():
		hover_sent = false
		unhovered.emit(self))


func setup(card_id: String, m := "full", up := true) -> CardView:
	id = card_id
	mode = m
	face_up = up
	queue_redraw()
	return self


func use_tap_mode() -> void:
	tap_mode = true
	mouse_filter = Control.MOUSE_FILTER_PASS   # 事件要傳給外層，手指才能捲動


func _tap_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if e.device != InputEvent.DEVICE_ID_EMULATION and not hover_sent:
			hover_sent = true
			hovered.emit(self)
		elif down_ms > 0 and e.global_position.distance_to(down_pos) > TAP_SLOP:
			down_ms = 0
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			down_ms = Time.get_ticks_msec()
			down_pos = e.global_position
			down_touch = e.device == InputEvent.DEVICE_ID_EMULATION
		else:
			if holding:
				unhovered.emit(self)
			elif down_ms > 0:
				pressed.emit(self)
			down_ms = 0
			holding = false


func _gui_input(e: InputEvent) -> void:
	if tap_mode:
		_tap_input(e)
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _process(delta: float) -> void:
	if down_touch and down_ms > 0 and not holding and Time.get_ticks_msec() - down_ms >= HOLD_MS:
		holding = true
		hovered.emit(self)
	if shake > 0 or flash > 0:
		shake = maxf(0.0, shake - delta * 2.5)
		flash = maxf(0.0, flash - delta * 2.0)
		queue_redraw()


func frame_color() -> Color:
	if CardDB.is_beast(id):
		return CardDB.TYPE_COLOR[CardDB.BEASTS[id].type]
	if CardDB.is_energy(id):
		return CardDB.TYPE_COLOR[CardDB.ENERGY[id].type]
	return TRAINER_COLOR


func _draw() -> void:
	var s := size.x / BASE.x
	var off := Vector2(sin(Time.get_ticks_msec() * 0.06) * 8.0 * shake, 0)
	draw_set_transform(off, 0, Vector2(s, size.y / BASE.y))
	if not face_up or id == "":
		var back := tex("res://assets/images/ui/card_back.png")
		if back:
			draw_texture_rect(back, Rect2(Vector2.ZERO, BASE), false)
		_draw_border(Color("d4af37"), 4)
	elif mode == "mini":
		_draw_mini()
	else:
		_draw_full()
	if dim:
		draw_rect(Rect2(Vector2.ZERO, BASE), Color(0, 0, 0, 0.55))
	if flash > 0:
		draw_rect(Rect2(Vector2.ZERO, BASE), Color(1, 1, 1, flash * 0.7))
	if highlight:
		_draw_border(Color(1, 0.85, 0.2, 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)), 8)
	if selected:
		_draw_border(Color("38c8ff"), 9)
	if count_label != "":
		draw_circle(Vector2(180, 20), 22, Color(0, 0, 0, 0.8))
		_text(count_label, Vector2(158, 30), 44, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if highlight:
		queue_redraw()


func _draw_border(c: Color, w: float) -> void:
	draw_rect(Rect2(Vector2(w / 2, w / 2), BASE - Vector2(w, w)), c, false, w)


func _font() -> Font:
	return get_theme_default_font()


func _text(t: String, pos: Vector2, width: float, fs: int, c := Color.WHITE, al := HORIZONTAL_ALIGNMENT_LEFT, outline := 0) -> void:
	if outline > 0:
		draw_string_outline(_font(), pos, t, al, width, fs, outline, Color(0, 0, 0, 0.9))
	draw_string(_font(), pos, t, al, width, fs, c)


func _energy_dot(type: String, center: Vector2, r: float) -> void:
	var icon := tex("res://assets/images/icons/i_%s.png" % type)
	if icon:
		draw_texture_rect(icon, Rect2(center - Vector2(r, r), Vector2(r, r) * 2), false)
	else:
		draw_circle(center, r, CardDB.TYPE_COLOR[type])


func _draw_full() -> void:
	var fc := frame_color()
	draw_rect(Rect2(Vector2.ZERO, BASE), fc.darkened(0.25))
	draw_rect(Rect2(6, 6, 188, 268), fc.lightened(0.55))
	var art := tex(CardDB.art_path(id))
	if CardDB.is_beast(id):
		var bd: Dictionary = CardDB.BEASTS[id]
		_text(bd.name, Vector2(12, 27), 120, 17, Color("1a1a1a"))
		_text("HP", Vector2(124, 27), 30, 10, Color("aa2222"))
		_text(str(bd.hp), Vector2(138, 28), 40, 19, Color("aa2222"))
		_energy_dot(bd.type, Vector2(184, 21), 9)
		if art:
			draw_texture_rect(art, Rect2(12, 34, 176, 112), false)
		draw_rect(Rect2(12, 34, 176, 112), fc.darkened(0.4), false, 2)
		var stage: String = "基礎靈獸" if bd.stage == 0 else "%s階進化自 %s" % ["一" if bd.stage == 1 else "二", CardDB.BEASTS[bd.from].name]
		draw_rect(Rect2(12, 148, 176, 15), Color(1, 1, 1, 0.5))
		_text(stage, Vector2(16, 160), 170, 10, Color("333333"))
		var y := 168.0
		for atk in bd.attacks:
			var x := 18.0
			for c in atk.cost:
				_energy_dot(c, Vector2(x, y + 10), 7)
				x += 15
			_text(atk.name, Vector2(x + 2, y + 15), 110, 14, Color("1a1a1a"))
			if atk.dmg > 0:
				_text(str(atk.dmg) + ("+" if atk.get("fx", "") in ["flip_plus", "energy_plus"] else ""),
					Vector2(140, y + 16), 46, 16, Color("1a1a1a"), HORIZONTAL_ALIGNMENT_RIGHT)
			var fx_text := fx_desc(atk)
			if fx_text != "":
				_text(fx_text, Vector2(18, y + 30), 172, 9, Color("444444"))
			y += 40
		draw_line(Vector2(12, 252), Vector2(188, 252), Color(0, 0, 0, 0.3), 1)
		var weak := ""
		for t in CardDB.BEATS:
			if CardDB.BEATS[t] == bd.type:
				weak = t
		_text("弱點", Vector2(14, 268), 40, 10, Color("333333"))
		_energy_dot(weak, Vector2(48, 264), 6)
		_text("×2", Vector2(56, 268), 30, 10, Color("333333"))
		_text("撤退", Vector2(110, 268), 40, 10, Color("333333"))
		for i in bd.retreat:
			_energy_dot("any", Vector2(144 + i * 12, 264), 5)
	elif CardDB.is_energy(id):
		var ed: Dictionary = CardDB.ENERGY[id]
		_text(ed.name, Vector2(12, 27), 176, 17, Color("1a1a1a"))
		_text("基本能量", Vector2(12, 27), 176, 11, Color("444444"), HORIZONTAL_ALIGNMENT_RIGHT)
		if art:
			draw_texture_rect(art, Rect2(12, 34, 176, 176), false)
		_energy_dot(ed.type, Vector2(100, 240), 22)
	else:
		var tr: Dictionary = CardDB.TRAINERS[id]
		_text(tr.name, Vector2(12, 27), 176, 17, Color("1a1a1a"))
		_text("支援" if tr.kind == "support" else "道具", Vector2(12, 27), 176, 11, Color("552288"), HORIZONTAL_ALIGNMENT_RIGHT)
		if art:
			draw_texture_rect(art, Rect2(12, 34, 176, 132), false)
		draw_rect(Rect2(12, 172, 176, 94), Color(1, 1, 1, 0.6))
		draw_multiline_string(_font(), Vector2(18, 192), tr.text, HORIZONTAL_ALIGNMENT_LEFT, 164, 13, -1, Color("1a1a1a"))
	draw_rect(Rect2(Vector2.ZERO, BASE), fc.darkened(0.5), false, 3)


static func fx_desc(atk: Dictionary) -> String:
	var v := int(atk.get("v", 0))
	match atk.get("fx", ""):
		"burn": return "對手灼傷（每回合開始受 10 傷害）"
		"para": return "對手麻痺"
		"para_flip": return "擲硬幣正面：對手麻痺"
		"heal": return "自己回復 %d HP" % v
		"bench": return "對手每隻後備也受 %d 傷害" % v
		"flip_plus": return "擲硬幣正面：多 %d 傷害" % v
		"energy_plus": return "每多 1 個能量多 %d（最多 2 個）" % v
		"self_discard": return "自己丟棄 %d 個能量" % v
		"recoil": return "自己也受 %d 傷害" % v
		"snipe": return "對手 HP 最低的後備受 %d 傷害" % v
		"power_up": return "從牌組找 1 張能量附加到後備"
		"draw": return "抽 %d 張牌" % v
	return ""


func _draw_mini() -> void:
	var fc := frame_color()
	draw_rect(Rect2(Vector2.ZERO, BASE), fc.darkened(0.3))
	var art := tex(CardDB.art_path(id))
	if art:
		draw_texture_rect(art, Rect2(8, 8, 184, 184), false)
	var nm := CardDB.card_name(id)
	draw_rect(Rect2(8, 8, 184, 34), Color(0, 0, 0, 0.55))
	_text(nm, Vector2(14, 34), 180, 22, Color.WHITE)
	if CardDB.is_beast(id):
		var bd: Dictionary = CardDB.BEASTS[id]
		var dmg: int = beast.dmg if beast != null else 0
		var left := maxi(0, bd.hp - dmg)
		var ratio: float = float(left) / bd.hp
		draw_rect(Rect2(8, 196, 184, 26), Color(0.1, 0.1, 0.1))
		var hc := Color("44dd55") if ratio > 0.5 else (Color("eecc22") if ratio > 0.25 else Color("ee3333"))
		draw_rect(Rect2(10, 198, 180 * ratio, 22), hc)
		_text("%d/%d" % [left, bd.hp], Vector2(8, 218), 184, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 4)
		if beast != null and battle != null:
			var types := battle.energy_types(beast)
			for i in types.size():
				_energy_dot(types[i], Vector2(22 + (i % 7) * 26, 240 + (i / 7) * 24), 12)
			if beast.status == "burn":
				_status_tag("灼傷", Color("ff5522"))
			elif beast.status == "para":
				_status_tag("麻痺", Color("ddcc11"))
			if beast.stack.size() > 0:
				draw_rect(Rect2(150, 46, 42, 24), Color(0.9, 0.7, 0.1, 0.9))
				_text("進化", Vector2(150, 64), 42, 16, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
	elif CardDB.is_energy(id):
		_energy_dot(CardDB.ENERGY[id].type, Vector2(100, 238), 26)
	else:
		_text("支援卡" if CardDB.TRAINERS[id].kind == "support" else "道具卡", Vector2(8, 245), 184, 24, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, 4)
	draw_rect(Rect2(Vector2.ZERO, BASE), fc.darkened(0.6), false, 4)


func _status_tag(t: String, c: Color) -> void:
	draw_rect(Rect2(8, 46, 70, 28), c)
	_text(t, Vector2(8, 68), 70, 20, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER)
