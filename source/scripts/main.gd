extends Control
## 主程式：畫面切換（標題／建立玩家／主選單／玩家資料／電腦對手／線上大廳／卡包商店／牌組編輯／匯入卡包／戰績／規則／對戰）。
## 版面固定 1280×720、放在畫面正中央；背景鋪滿整個視窗，手機平板不同長寬比也不會有黑邊。
## 玩家資料由 SaveDB 存在 user://saves/，每次對戰動作、開卡包、改牌組都會自動存檔。

const PACK_PRICE := 100
const AVATARS := ["av_boy", "av_girl", "av_kid", "av_cool"]
const SECRET_TAPS := 5
const SECRET_WINDOW_MS := 3000
const UI_SIZE := Vector2(1280, 720)

var db := SaveDB.new()
var profile := {}
var rng := RandomNumberGenerator.new()
var screen: Control
var backdrop: TextureRect
var backdrop_shade: ColorRect
var secret_taps := 0
var secret_start := 0


func _ready() -> void:
	rng.randomize()
	theme = _make_theme()
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop_shade = ColorRect.new()
	backdrop_shade.color = Color(0, 0, 0, 0.35)
	backdrop_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop_shade)
	resized.connect(_center_screen)
	show_title()


func _center_screen() -> void:
	if screen:
		screen.position = ((size - UI_SIZE) / 2).floor()


func _make_theme() -> Theme:
	var t := Theme.new()
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 4
		s.content_margin_bottom = 4
		return s
	t.set_stylebox("normal", "Button", mk.call(Color("1d2b4a"), Color("c9a24a")))
	t.set_stylebox("hover", "Button", mk.call(Color("2c4272"), Color("ffd84a")))
	t.set_stylebox("pressed", "Button", mk.call(Color("13203a"), Color("ffd84a")))
	t.set_stylebox("disabled", "Button", mk.call(Color(0.15, 0.17, 0.22, 0.8), Color(0.35, 0.35, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color("fff4d6"))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.6))
	t.set_font_size("font_size", "Button", 20)
	t.set_font_size("font_size", "Label", 18)
	t.set_stylebox("normal", "LineEdit", mk.call(Color("0e1628"), Color("c9a24a")))
	t.set_font_size("font_size", "LineEdit", 22)
	return t


# ---------- 共用元件 ----------

func _clear(bg := "bg_menu", music := "bgm_menu") -> Control:
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.size = UI_SIZE
	add_child(screen)
	_center_screen()
	backdrop.texture = CardView.tex("res://assets/images/ui/%s.png" % bg)
	backdrop_shade.color.a = 0.25 if bg == "bg_battle" else 0.35
	if music != "":
		Audio.bgm(music)
	return screen


func _label(parent: Control, t: String, pos: Vector2, fs := 18, sz := Vector2.ZERO, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	if sz != Vector2.ZERO:
		l.size = sz
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", maxi(4, fs / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(l)
	return l


func _button(parent: Control, t: String, r: Rect2, cb: Callable, fs := 20) -> Button:
	var b := Button.new()
	b.text = t
	b.position = r.position
	b.size = r.size
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(func():
		Audio.play("click")
		cb.call())
	parent.add_child(b)
	return b


func _panel(parent: Control, r: Rect2, alpha := 0.82) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.15, alpha)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(0.85, 0.7, 0.3, 0.9)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _tex_rect(parent: Control, path: String, r: Rect2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = CardView.tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = r.position
	t.size = r.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _toast(t: String, color := Color("ffe680")) -> void:
	var l := _label(self, t, ((size - UI_SIZE) / 2).floor() + Vector2(0, 640), 24, Vector2(1280, 40), color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 50
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func _save() -> void:
	if not profile.is_empty():
		db.save(profile)


func _deck() -> Array:
	var i := clampi(profile.active_deck, 0, profile.decks.size() - 1)
	return profile.decks[i].cards


func _deck_size() -> int:
	return int(profile.decks[clampi(profile.active_deck, 0, profile.decks.size() - 1)].deck_size)


func _deck_error() -> String:
	return CardDB.validate_deck(_deck(), _deck_size())


## 線上對手的電腦沒有你的自製卡，所以線上對戰不能帶自製卡
func _online_error() -> String:
	if CardDB.has_custom(_deck()):
		return "線上對戰不能使用自製卡，請換一副沒有自製卡的牌組"
	return _deck_error()


func _opt(parent: Control, r: Rect2, items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.position = r.position
	o.size = r.size
	o.clip_text = true
	o.add_theme_font_size_override("font_size", 17)
	for it in items:
		o.add_item(str(it))
	o.selected = sel
	o.item_selected.connect(cb)
	parent.add_child(o)
	return o


func _spin(parent: Control, r: Rect2, lo: int, hi: int, step: int, v: int, cb: Callable) -> SpinBox:
	var sp := SpinBox.new()
	sp.position = r.position
	sp.size = r.size
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = v
	sp.get_line_edit().add_theme_font_size_override("font_size", 17)
	sp.value_changed.connect(func(x): cb.call(int(x)))
	parent.add_child(sp)
	return sp


func _edit(parent: Control, r: Rect2, t: String, max_len: int, cb := Callable()) -> LineEdit:
	var e := LineEdit.new()
	e.position = r.position
	e.size = r.size
	e.text = t
	e.max_length = max_len
	e.add_theme_font_size_override("font_size", 18)
	if cb.is_valid():
		e.text_changed.connect(cb)
	parent.add_child(e)
	return e


# ---------- 標題 ----------

func show_title() -> void:
	var s := _clear("bg_title", "bgm_menu")
	var title := _label(s, "靈獸卡牌對戰", Vector2(0, 50), 84, Vector2(1280, 110), Color("ffe27a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 22)
	var sub := _label(s, "Elemental Beasts TCG", Vector2(0, 150), 28, Vector2(1280, 40), Color("cfe8ff"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var profiles := db.list_profiles()
	var p := _panel(s, Rect2(390, 230, 500, 440))
	_label(p, "選擇玩家" if not profiles.is_empty() else "歡迎來到靈獸卡牌的世界！", Vector2(0, 14), 24, Vector2(500, 36)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var y := 64
	for pr in profiles.slice(0, 5):
		var row := _button(p, "", Rect2(30, y, 440, 58), load_and_menu.bind(str(pr.name)))
		_tex_rect(row, CardDB.avatar_path(str(pr.get("avatar", "av_boy"))), Rect2(6, 4, 50, 50))
		var st: Dictionary = pr.get("stats", {})
		_label(row, "%s   %d 勝 %d 敗   金幣 %d" % [pr.name, int(st.get("wins", 0)), int(st.get("losses", 0)), int(pr.get("coins", 0))],
			Vector2(66, 14), 20)
		y += 66
	_button(p, "＋ 建立新玩家", Rect2(130, 376, 240, 50), show_new_profile)


func load_and_menu(pname: String) -> void:
	profile = db.load_profile(pname)
	if profile.is_empty():
		_toast("讀取存檔失敗", Color("ff7070"))
		return
	show_menu()


func show_new_profile() -> void:
	var s := _clear("bg_title", "")
	var p := _panel(s, Rect2(140, 40, 1000, 640))
	_label(p, "建立新玩家", Vector2(0, 16), 34, Vector2(1000, 50), Color("ffe27a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(p, "你的名字", Vector2(60, 90), 22)
	var name_edit := LineEdit.new()
	name_edit.position = Vector2(180, 82)
	name_edit.size = Vector2(320, 44)
	name_edit.max_length = 8
	name_edit.placeholder_text = "最多 8 個字"
	p.add_child(name_edit)
	# 手機或網頁不方便打中文時，可以直接隨機取名
	_button(p, "隨機取名", Rect2(512, 82, 130, 44), func():
		var adj := ["勇敢", "閃亮", "快樂", "神秘", "無敵", "飛天", "幸運", "熱血"]
		var bn: Array = CardDB.BEASTS.values().filter(func(x): return x.name.length() <= 3)
		name_edit.text = "%s%s%d" % [adj[rng.randi_range(0, adj.size() - 1)], bn[rng.randi_range(0, bn.size() - 1)].name,
			rng.randi_range(1, 99)], 18)
	_label(p, "選頭像", Vector2(60, 150), 22)
	var chosen := {"avatar": AVATARS[0], "type": "fire"}
	var av_btns: Array = []
	for i in AVATARS.size():
		var b := _button(p, "", Rect2(180 + i * 130, 140, 110, 110), func(): pass)
		_tex_rect(b, "res://assets/images/avatars/%s.png" % AVATARS[i], Rect2(6, 6, 98, 98))
		av_btns.append(b)
	_label(p, "選擇你的第一副起始牌組", Vector2(60, 274), 22)
	var t_btns: Array = []
	var types: Array = CardDB.TYPES
	for i in types.size():
		var t: String = types[i]
		var b := _button(p, "", Rect2(60 + i * 182, 310, 170, 230), func(): pass)
		var cv := CardView.new().setup(CardDB.LINES[t][0][0], "mini")
		cv.position = Vector2(20, 8)
		cv.size = Vector2(130, 182)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cv)
		_label(b, CardDB.STARTER_NAME[t], Vector2(0, 196), 17, Vector2(170, 28)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_btns.append(b)
	var refresh := func():
		for i in AVATARS.size():
			av_btns[i].modulate = Color.WHITE if AVATARS[i] == chosen.avatar else Color(0.5, 0.5, 0.5)
		for i in types.size():
			t_btns[i].modulate = Color.WHITE if types[i] == chosen.type else Color(0.5, 0.5, 0.5)
	for i in AVATARS.size():
		av_btns[i].pressed.connect(func():
			chosen.avatar = AVATARS[i]
			refresh.call())
	for i in types.size():
		t_btns[i].pressed.connect(func():
			chosen.type = types[i]
			refresh.call())
	refresh.call()
	_button(p, "返回", Rect2(300, 568, 160, 50), show_title)
	_button(p, "開始冒險！", Rect2(540, 568, 180, 50), func():
		var n := name_edit.text.strip_edges()
		if n == "":
			_toast("請輸入名字", Color("ff7070"))
			return
		if db.exists(n):
			_toast("這個名字已經有存檔了", Color("ff7070"))
			return
		profile = db.new_profile(n, chosen.avatar, chosen.type)
		_toast("拿到了 %s 和 200 金幣！" % CardDB.STARTER_NAME[chosen.type])
		show_menu())


# ---------- 主選單 ----------

func _top_bar(s: Control) -> void:
	var bar := _panel(s, Rect2(10, 8, 1260, 66))
	_tex_rect(bar, CardDB.avatar_path(profile.avatar), Rect2(8, 6, 54, 54))
	var player_title := str(profile.get("title", ""))
	_label(bar, profile.name, Vector2(72, 16 if player_title == "" else 4), 26)
	if player_title != "":
		_label(bar, player_title, Vector2(72, 38), 15, Vector2.ZERO, Color("ffd84a"))
	var st: Dictionary = profile.stats
	_label(bar, "戰績 %d 勝 %d 敗" % [st.wins, st.losses], Vector2(300, 20), 20)
	_tex_rect(bar, "res://assets/images/ui/coin.png", Rect2(1080, 13, 40, 40))
	_label(bar, str(profile.coins), Vector2(1126, 16), 26, Vector2.ZERO, Color("ffd84a"))
	var kinds := 0
	for id in CardDB.BEASTS.keys() + CardDB.TRAINERS.keys():
		if int(profile.collection.get(id, 0)) > 0:
			kinds += 1
	_label(bar, "卡片收集 %d / %d 種" % [kinds, CardDB.BEASTS.size() + CardDB.TRAINERS.size()], Vector2(540, 20), 20)
	_label(bar, "牌組：" + profile.decks[clampi(profile.active_deck, 0, profile.decks.size() - 1)].name, Vector2(800, 20), 18)
	# 隱藏功能：3 秒內連點頭像 5 下
	var hot := Control.new()
	hot.position = Vector2(8, 6)
	hot.size = Vector2(54, 54)
	hot.gui_input.connect(_on_avatar_tap)
	bar.add_child(hot)


func _on_avatar_tap(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var now := Time.get_ticks_msec()
	if now - secret_start > SECRET_WINDOW_MS:
		secret_start = now
		secret_taps = 0
	secret_taps += 1
	if secret_taps >= SECRET_TAPS:
		secret_taps = 0
		show_secret()


## 隱藏選單：補齊卡片、改名字
func show_secret() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.position = -screen.position
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	var p := _panel(dim, Rect2(screen.position + Vector2(340, 170), Vector2(600, 360)), 0.95)
	_label(p, "隱藏選單", Vector2(0, 16), 30, Vector2(600, 44), Color("ffe27a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, "補齊全部卡片", Rect2(150, 80, 300, 56), func():
		var added := SaveDB.fill_collection(profile)
		_save()
		_toast("補了 %d 張卡片" % added if added > 0 else "卡片已經全滿了")
		show_menu(), 22)
	_label(p, "新名字", Vector2(50, 168), 22)
	var name_edit := LineEdit.new()
	name_edit.position = Vector2(140, 160)
	name_edit.size = Vector2(290, 44)
	name_edit.max_length = 8
	name_edit.text = profile.name
	p.add_child(name_edit)
	_button(p, "改名", Rect2(444, 160, 110, 44), func():
		if rename_player(name_edit.text):
			show_menu(), 20)
	_button(p, "關閉", Rect2(220, 280, 160, 50), dim.queue_free)


## 改玩家名字；成功回傳 true
func rename_player(new_name: String) -> bool:
	var n := new_name.strip_edges()
	if n == "":
		_toast("請輸入名字", Color("ff7070"))
		return false
	if n == profile.name:
		_toast("名字沒有改變", Color("ff7070"))
		return false
	if db.exists(n):
		_toast("這個名字已經有存檔了", Color("ff7070"))
		return false
	db.rename_profile(profile, n)
	_toast("名字改成「%s」" % n)
	return true


func show_menu() -> void:
	var s := _clear("bg_menu", "bgm_menu")
	_top_bar(s)
	var items := []
	if profile.get("current_match") is Dictionary:
		items.append(["▶ 繼續上一場對戰", resume_match])
	items += [["電腦對戰", show_ai_select], ["線上對戰", show_lobby], ["卡包商店", show_shop],
		["牌組編輯", show_deck_editor], ["匯入卡包", show_import], ["玩家資料", show_profile],
		["戰績紀錄", show_records], ["規則說明", show_rules], ["換玩家", show_title]]
	var rows := (items.size() + 1) / 2
	var p := _panel(s, Rect2(240, 120, 800, 50 + rows * 86))
	for i in items.size():
		var b := _button(p, items[i][0], Rect2(40 + (i % 2) * 370, 28 + (i / 2) * 86, 350, 68), items[i][1], 26)
		if i == 0 and profile.get("current_match") is Dictionary:
			b.add_theme_color_override("font_color", Color("7dff9a"))
	var mute := _button(s, "音效開關", Rect2(1130, 660, 130, 44), func(): Audio.toggle_mute(), 18)
	mute.tooltip_text = "開／關音效與音樂"
	if OS.has_feature("web"):
		_button(s, "全螢幕", Rect2(990, 660, 130, 44), func(): JavaScriptBridge.eval("window.__bcFullscreen && __bcFullscreen()", true), 18)


# ---------- 玩家資料 ----------

func show_profile() -> void:
	var s := _clear()
	_top_bar(s)
	var p := _panel(s, Rect2(190, 90, 900, 610))
	_label(p, "玩家資料", Vector2(0, 14), 32, Vector2(900, 46), Color("ffe27a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chosen := {"avatar": profile.avatar}
	var preview := _tex_rect(p, CardDB.avatar_path(profile.avatar), Rect2(50, 80, 200, 200))
	var set_avatar := func(a: String):
		chosen.avatar = a
		preview.texture = CardView.tex(CardDB.avatar_path(a))
	_label(p, "名字", Vector2(290, 92), 22)
	var name_edit := _edit(p, Rect2(400, 84, 300, 44), profile.name, 8)
	_label(p, "稱號", Vector2(290, 152), 22)
	var title_edit := _edit(p, Rect2(400, 144, 300, 44), str(profile.get("title", "")), 10)
	title_edit.placeholder_text = "最多 10 個字"
	_label(p, "自我介紹", Vector2(290, 212), 22)
	var bio_edit := _edit(p, Rect2(400, 204, 450, 44), str(profile.get("bio", "")), 30)
	bio_edit.placeholder_text = "最多 30 個字"
	_label(p, "換頭像", Vector2(50, 306), 22)
	for i in AVATARS.size():
		var b := _button(p, "", Rect2(50 + i * 120, 342, 108, 108), set_avatar.bind(AVATARS[i]))
		_tex_rect(b, CardDB.avatar_path(AVATARS[i]), Rect2(6, 6, 96, 96))
	_button(p, "上傳自己的圖片", Rect2(540, 342, 310, 108), func():
		FilePick.pick(self, false, func(images: Array):
			var path := db.save_avatar(images[0])
			if path != "":
				set_avatar.call(path)), 22)
	_button(p, "返回", Rect2(260, 510, 160, 56), show_menu)
	_button(p, "儲存", Rect2(480, 510, 160, 56), func():
		if save_profile_info(name_edit.text, title_edit.text, bio_edit.text, chosen.avatar):
			show_menu())


## 儲存玩家資料；名字不合法回傳 false、其他欄位也不變
func save_profile_info(new_name: String, new_title: String, bio: String, avatar: String) -> bool:
	if new_name.strip_edges() != profile.name and not rename_player(new_name):
		return false
	profile.title = new_title.strip_edges()
	profile.bio = bio.strip_edges()
	profile.avatar = avatar
	_save()
	_toast("玩家資料已更新")
	return true


# ---------- 電腦對戰 ----------

func show_ai_select() -> void:
	var s := _clear()
	_top_bar(s)
	_label(s, "選擇對手（打贏前一位才能挑戰下一位）", Vector2(0, 86), 26, Vector2(1280, 40)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lv_names := ["簡單", "普通", "困難", "冠軍"]
	for i in CardDB.OPPONENTS.size():
		var o: Dictionary = CardDB.OPPONENTS[i]
		var p := _panel(s, Rect2(30 + i * 310, 140, 290, 470))
		_tex_rect(p, "res://assets/images/avatars/%s.png" % o.avatar, Rect2(55, 16, 180, 180))
		_label(p, o.name, Vector2(0, 204), 26, Vector2(290, 36)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(p, "難度：" + lv_names[o.level], Vector2(0, 242), 18, Vector2(290, 28), Color("ffb84a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var intro := _label(p, o.intro, Vector2(20, 274), 17, Vector2(250, 80))
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var beaten := int(profile.beaten.get(o.id, 0))
		_label(p, "獎金 %d 金幣　已打贏 %d 次" % [o.reward, beaten], Vector2(0, 360), 16, Vector2(290, 28)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var unlocked := i == 0 or int(profile.beaten.get(CardDB.OPPONENTS[i - 1].id, 0)) > 0
		var b := _button(p, "挑戰！" if unlocked else "尚未解鎖", Rect2(55, 400, 180, 52), start_ai_match.bind(i), 22)
		b.disabled = not unlocked
	_button(s, "返回", Rect2(560, 640, 160, 50), show_menu)


func start_ai_match(i: int) -> void:
	var err := _deck_error()
	if err != "":
		_toast("你的牌組不合法：" + err, Color("ff7070"))
		return
	var o: Dictionary = CardDB.OPPONENTS[i]
	var b := Battle.new()
	b.setup(rng.randi() % 2000000000, _deck(), CardDB.scaled_deck(CardDB.deck_by_name(o.deck), _deck_size()), profile.name, o.name)
	profile.current_match = {"opp": i, "save": b.to_save()}
	_save()
	_run_ai_battle(b, i)


func resume_match() -> void:
	var cm: Dictionary = profile.current_match
	var b := Battle.from_save(cm.save)
	_run_ai_battle(b, int(cm.opp))


func _run_ai_battle(b: Battle, i: int) -> void:
	var o: Dictionary = CardDB.OPPONENTS[i]
	var s := _clear("bg_battle", "")
	var ui := BattleUI.new()
	s.add_child(ui)
	ui.start(b, 0, {"kind": "ai", "level": o.level, "my_avatar": profile.avatar, "opp_avatar": o.avatar,
		"autosave": func(sv):
			profile.current_match = {"opp": i, "save": sv}
			_save()})
	ui.finished.connect(func(res): _on_ai_finished(res, i))


func _on_ai_finished(res: Dictionary, i: int) -> void:
	if res.get("paused", false) and not res.get("over", false):
		_save()
		show_menu()
		return
	var o: Dictionary = CardDB.OPPONENTS[i]
	profile.current_match = null
	var gain := 20
	var note := ""
	if res.won:
		gain = o.reward
		if int(profile.beaten.get(o.id, 0)) == 0:
			gain += 100
			note = "（第一次打贏，額外 +100！）"
		profile.beaten[o.id] = int(profile.beaten.get(o.id, 0)) + 1
	profile.coins += gain
	SaveDB.add_result(profile, "ai", o.name, res.won, res.turns, res.stars, res.kos)
	_save()
	show_menu()
	Audio.play("buy")
	_toast("獲得 %d 金幣 %s" % [gain, note])


# ---------- 線上對戰 ----------

func show_lobby() -> void:
	var s := _clear()
	_top_bar(s)
	var p := _panel(s, Rect2(290, 110, 700, 520))
	_label(p, "線上對戰", Vector2(0, 16), 34, Vector2(700, 50), Color("ffe27a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not Net.enabled():
		_label(p, "這個版本沒有線上設定（config/online.cfg），暫時不能線上對戰。", Vector2(40, 120), 20, Vector2(620, 80)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(p, "返回", Rect2(270, 440, 160, 50), show_menu)
		return
	var help := _label(p, "一人「開房間」把 6 碼房號告訴朋友，另一人輸入房號「加入」。\n電腦版和網頁版可以互打，使用你目前的牌組（不能帶自製卡）。",
		Vector2(40, 76), 18, Vector2(620, 60))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status := _label(p, "", Vector2(40, 330), 22, Vector2(620, 90), Color("7dff9a"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var state := {"cancel": false, "busy": false}
	var create := _button(p, "開房間", Rect2(60, 160, 260, 60), func(): pass, 24)
	var code_edit := LineEdit.new()
	code_edit.position = Vector2(380, 160)
	code_edit.size = Vector2(150, 60)
	code_edit.max_length = 6
	code_edit.placeholder_text = "房號"
	code_edit.add_theme_font_size_override("font_size", 28)
	p.add_child(code_edit)
	var join := _button(p, "加入", Rect2(540, 160, 110, 60), func(): pass, 24)
	_button(p, "返回", Rect2(270, 440, 160, 50), func():
		state.cancel = true
		show_menu())
	create.pressed.connect(func():
		if state.busy:
			return
		if _online_error() != "":
			status.text = _online_error()
			return
		state.busy = true
		status.text = "開房間中……"
		var r: Dictionary = await Net.create_room(profile.name, _deck())
		if r.is_empty():
			status.text = "開房間失敗，請檢查網路。" + Net.last_error
			state.busy = false
			return
		status.text = "房號：%s\n把房號告訴朋友，等待對手加入……" % r.code
		while not state.cancel:
			await get_tree().create_timer(1.5).timeout
			if state.cancel or not is_instance_valid(status):
				return
			var room: Dictionary = await Net.get_room(r.code)
			if str(room.get("guest", "")) != "":
				_start_online(r.code, room, 0)
				return)
	join.pressed.connect(func():
		if state.busy:
			return
		var code := code_edit.text.strip_edges().to_upper()
		if code.length() != 6:
			status.text = "請輸入 6 碼房號"
			return
		if _online_error() != "":
			status.text = _online_error()
			return
		state.busy = true
		status.text = "加入中……"
		var room: Dictionary = await Net.join_room(code, profile.name, _deck())
		if room.has("error"):
			status.text = room.error
			state.busy = false
			return
		_start_online(code, room, 1))


func _start_online(code: String, room: Dictionary, me: int) -> void:
	var b := Battle.new()
	b.setup(int(room.seed), str(room.host_deck).split(","), str(room.guest_deck).split(","), str(room.host), str(room.guest))
	var s := _clear("bg_battle", "")
	var ui := BattleUI.new()
	s.add_child(ui)
	ui.start(b, me, {"kind": "online", "code": code, "level": 1, "my_avatar": profile.avatar, "opp_avatar": "av_cool"})
	ui.finished.connect(func(res):
		if res.get("over", false):
			var gain := 100 if res.won else 30
			profile.coins += gain
			SaveDB.add_result(profile, "online", str(room.guest if me == 0 else room.host), res.won, res.turns, res.stars, res.kos)
			_save()
			show_menu()
			_toast("線上對戰結束，獲得 %d 金幣" % gain)
		else:
			show_menu())


# ---------- 卡包商店 ----------

func show_shop() -> void:
	var s := _clear()
	_top_bar(s)
	var p := _panel(s, Rect2(40, 90, 1200, 610))
	_label(p, "卡包商店", Vector2(30, 14), 32, Vector2.ZERO, Color("ffe27a"))
	_label(p, "每包 5 張：3 張普通、1 張不普通，最後一張有機會是稀有進化靈獸！", Vector2(250, 22), 20)
	var pack := _tex_rect(p, "res://assets/images/ui/pack.png", Rect2(60, 90, 300, 400))
	var reveal := Control.new()
	reveal.position = Vector2(400, 90)
	p.add_child(reveal)
	var packs: Array = db.library.packs.filter(func(x): return not x.cards.is_empty())
	var pack_pick := _opt(p, Rect2(400, 66, 400, 44), ["標準卡包"] + packs.map(func(x): return x.name), 0, func(_i): pass)
	var buy := _button(p, "購買（%d 金幣）" % PACK_PRICE, Rect2(80, 510, 260, 60), func(): pass, 24)
	buy.pressed.connect(func():
		if profile.coins < PACK_PRICE:
			Audio.play("error")
			_toast("金幣不夠，去打電腦對戰賺金幣吧！", Color("ff7070"))
			return
		buy.disabled = true
		profile.coins -= PACK_PRICE
		var i_pack := pack_pick.selected
		var got: Array = SaveDB.open_pack(rng) if i_pack == 0 else SaveDB.open_custom_pack(packs[i_pack - 1], rng)
		for id in got:
			profile.collection[id] = int(profile.collection.get(id, 0)) + 1
		profile.stats.packs += 1
		_save()
		Audio.play("pack")
		var tw := create_tween()
		tw.tween_property(pack, "scale", Vector2(1.08, 1.08), 0.12)
		tw.tween_property(pack, "scale", Vector2.ONE, 0.12)
		for c in reveal.get_children():
			c.queue_free()
		for i in got.size():
			var cv := CardView.new().setup(got[i], "full", false)
			cv.position = Vector2(i * 156, 40 + (i % 2) * 20)
			cv.size = Vector2(150, 210)
			cv.hovered.connect(func(_v): pass)
			reveal.add_child(cv)
		for i in got.size():
			await get_tree().create_timer(0.45).timeout
			if not is_instance_valid(reveal):
				return
			var cv: CardView = reveal.get_child(i)
			cv.face_up = true
			cv.flash = 1.0
			cv.queue_redraw()
			Audio.play("rare" if CardDB.rarity(got[i]) == 2 else "draw")
			if CardDB.rarity(got[i]) == 2:
				var star := _label(reveal, "★稀有★", cv.position + Vector2(30, 216), 22, Vector2.ZERO, Color("ffd84a"))
				star.z_index = 5
		_top_bar(s)
		buy.disabled = false)
	_button(s, "返回", Rect2(1070, 630, 150, 50), show_menu)


# ---------- 牌組編輯 ----------

var edit_deck: Array = []
var edit_index := 0
var edit_filter := "all"
var edit_size := CardDB.DECK_SIZE
var preview: CardView


func show_deck_editor(idx := -1) -> void:
	if idx >= 0:
		edit_index = idx
	else:
		edit_index = clampi(profile.active_deck, 0, profile.decks.size() - 1)
	edit_deck = profile.decks[edit_index].cards.duplicate()
	edit_size = int(profile.decks[edit_index].deck_size)
	_draw_editor()


func _draw_editor() -> void:
	var s := _clear()
	var top := _panel(s, Rect2(10, 8, 1260, 60))
	_label(top, "牌組編輯", Vector2(16, 12), 26, Vector2.ZERO, Color("ffe27a"))
	var pick := OptionButton.new()
	pick.position = Vector2(150, 10)
	pick.size = Vector2(250, 40)
	for d in profile.decks:
		pick.add_item(d.name)
	pick.selected = edit_index
	pick.item_selected.connect(func(i): show_deck_editor(i))
	top.add_child(pick)
	var name_edit := LineEdit.new()
	name_edit.position = Vector2(410, 10)
	name_edit.size = Vector2(200, 40)
	name_edit.text = profile.decks[edit_index].name
	name_edit.max_length = 10
	name_edit.add_theme_font_size_override("font_size", 18)
	top.add_child(name_edit)
	_button(top, "新增牌組", Rect2(620, 10, 120, 40), func():
		profile.decks.append({"name": "新牌組 %d" % (profile.decks.size() + 1), "cards": [], "deck_size": edit_size})
		_save()
		show_deck_editor(profile.decks.size() - 1), 17)
	_button(top, "刪除", Rect2(746, 10, 80, 40), func():
		if profile.decks.size() <= 1:
			_toast("至少要留一副牌組", Color("ff7070"))
			return
		profile.decks.remove_at(edit_index)
		profile.active_deck = clampi(profile.active_deck, 0, profile.decks.size() - 1)
		_save()
		show_deck_editor(0), 17)
	_button(top, "自動組牌", Rect2(832, 10, 120, 40), func():
		edit_deck = _auto_deck(edit_size)
		_draw_editor_lists(s), 17)
	var save_btn := _button(top, "儲存並使用", Rect2(958, 10, 150, 40), func(): pass, 17)
	_button(top, "返回", Rect2(1114, 10, 130, 40), show_menu, 17)
	save_btn.pressed.connect(func():
		var err := CardDB.validate_deck(edit_deck, edit_size)
		profile.decks[edit_index].deck_size = edit_size
		profile.decks[edit_index].name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "我的牌組"
		profile.decks[edit_index].cards = edit_deck.duplicate()
		if err == "":
			profile.active_deck = edit_index
			_save()
			_toast("已儲存，對戰會使用這副牌組")
		else:
			_save()
			_toast("已儲存，但還不能使用：" + err, Color("ffb070")))
	# 篩選
	var filters := [["all", "全部"], ["fire", "火"], ["water", "水"], ["leaf", "草"], ["thunder", "雷"], ["rock", "岩"],
		["energy", "能量"], ["trainer", "訓練家"], ["custom", "自製"]]
	for i in filters.size():
		var f: Array = filters[i]
		var b := _button(s, f[1], Rect2(14 + i * 98, 76, 92, 36), func():
			edit_filter = f[0]
			_draw_editor_lists(s), 17)
		b.modulate = Color.WHITE if edit_filter == f[0] else Color(0.7, 0.7, 0.7)
	_draw_editor_lists(s)
	preview = CardView.new()
	preview.size = Vector2(360, 504)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.visible = false
	preview.z_index = 20
	s.add_child(preview)


## 放大看一張卡；at_left 用在右邊的牌組清單，放大圖才不會蓋住滑鼠
func _show_preview(id: String, at_left := false) -> void:
	preview.setup(id, "full")
	preview.position = Vector2(520 if at_left else 905, 112)
	preview.visible = true


func _draw_editor_lists(s: Control) -> void:
	for n in ["coll", "decklist"]:
		var old := s.get_node_or_null(n)
		if old:
			old.name = n + "_old"
			old.queue_free()
	var counts := {}
	for id in edit_deck:
		counts[id] = counts.get(id, 0) + 1
	# 左：收藏
	var scroll := ScrollContainer.new()
	scroll.name = "coll"
	scroll.position = Vector2(10, 118)
	scroll.size = Vector2(880, 594)
	s.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for id in CardDB.all_ids():
		if not _filter_ok(id):
			continue
		var owned := int(profile.collection.get(id, 0))
		var cv := CardView.new().setup(id, "full", true)
		cv.custom_minimum_size = Vector2(116, 162)
		var in_deck := int(counts.get(id, 0))
		if owned <= 0:
			cv.dim = true
			cv.count_label = "0"
		else:
			cv.count_label = ("%d" % in_deck) if CardDB.is_energy(id) else "%d/%d" % [in_deck, owned]
		cv.use_tap_mode()
		cv.hovered.connect(func(_v): _show_preview(id))
		cv.unhovered.connect(func(_v): preview.visible = false)
		cv.pressed.connect(func(_v):
			var limit := 99 if CardDB.is_energy(id) else mini(owned, CardDB.max_copies(edit_size))
			if owned <= 0:
				Audio.play("error")
				_toast("還沒有這張卡，去卡包商店抽抽看！", Color("ffb070"))
			elif edit_deck.size() >= edit_size:
				Audio.play("error")
				_toast("牌組已經 %d 張了" % edit_size, Color("ffb070"))
			elif int(counts.get(id, 0)) >= limit:
				Audio.play("error")
				_toast("這張卡最多放 %d 張" % limit, Color("ffb070"))
			else:
				Audio.play("play")
				edit_deck.append(id)
				_draw_editor_lists(s))
		grid.add_child(cv)
	# 右：牌組清單
	var p := _panel(s, Rect2(900, 76, 370, 636))
	p.name = "decklist"
	var err := CardDB.validate_deck(edit_deck, edit_size)
	_label(p, "牌組 %d / %d 張" % [edit_deck.size(), edit_size], Vector2(14, 8), 22, Vector2.ZERO,
		Color("7dff9a") if err == "" else Color("ffb070"))
	for i in CardDB.DECK_SIZES.size():
		var n: int = CardDB.DECK_SIZES[i]
		var b := _button(p, "%d 張" % n, Rect2(206 + i * 78, 6, 72, 34), func():
			edit_size = n
			_draw_editor_lists(s), 16)
		b.modulate = Color.WHITE if edit_size == n else Color(0.6, 0.6, 0.6)
	var e := _label(p, "可以使用！" if err == "" else err, Vector2(14, 40), 15, Vector2(340, 40))
	e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ds := ScrollContainer.new()
	ds.position = Vector2(8, 84)
	ds.size = Vector2(354, 544)
	p.add_child(ds)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(340, 0)
	ds.add_child(vb)
	var order := CardDB.all_ids()
	var ids := counts.keys()
	ids.sort_custom(func(a, b): return order.find(a) < order.find(b))
	for id in ids:
		var row := Button.new()
		row.custom_minimum_size = Vector2(336, 34)
		row.text = "%s  ×%d" % [CardDB.card_name(id), counts[id]]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 17)
		var c: Color = CardDB.TYPE_COLOR.get(CardDB.BEASTS[id].type if CardDB.is_beast(id) else (CardDB.ENERGY[id].type if CardDB.is_energy(id) else "any"))
		row.add_theme_color_override("font_color", c.lightened(0.3))
		row.tooltip_text = "點一下拿掉一張"
		row.gui_input.connect(func(ev):
			if ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
				_show_preview(id, true))
		row.mouse_exited.connect(func(): preview.visible = false)
		row.pressed.connect(func():
			Audio.play("click")
			edit_deck.erase(id)
			preview.visible = false
			_draw_editor_lists(s))
		vb.add_child(row)


func _filter_ok(id: String) -> bool:
	match edit_filter:
		"all": return true
		"energy": return CardDB.is_energy(id)
		"trainer": return CardDB.is_trainer(id)
		"custom": return CardDB.is_custom(id)
	if CardDB.is_beast(id):
		return CardDB.BEASTS[id].type == edit_filter
	if CardDB.is_energy(id):
		return CardDB.ENERGY[id].type == edit_filter
	return false


## 依收藏自動組一副：挑擁有最多靈獸的兩種屬性；60 張時每種卡的張數都放大兩倍
## 每條進化線依基礎 3、一階 2、二階 1 張放
func _auto_deck(n := CardDB.DECK_SIZE) -> Array:
	var k_n := n / CardDB.DECK_SIZE
	var score := {}
	for t in CardDB.TYPES:
		score[t] = 0
		for line in CardDB.LINES[t]:
			for id in line:
				score[t] += mini(int(profile.collection.get(id, 0)), 3 * k_n)
	var types: Array = CardDB.TYPES.duplicate()
	types.sort_custom(func(a, b): return score[a] > score[b])
	var d: Array = []
	for t in types.slice(0, 2):
		for line in CardDB.LINES[t]:
			for id in line:
				for i in mini(int(profile.collection.get(id, 0)), (3 - CardDB.BEASTS[id].stage) * k_n):
					if d.size() < 14 * k_n:
						d.append(id)
	for id in ["potion", "finder", "journal", "scroll", "whistle", "notes", "band", "bell", "recycle"]:
		for i in mini(int(profile.collection.get(id, 0)), 2 * k_n):
			if d.size() < 20 * k_n:
				d.append(id)
	var main_types: Array = []
	for id in d:
		if CardDB.is_beast(id) and not main_types.has(CardDB.BEASTS[id].type):
			main_types.append(CardDB.BEASTS[id].type)
	if main_types.is_empty():
		main_types = [types[0]]
	var k := 0
	while d.size() < n:
		d.append("e_" + main_types[k % main_types.size()])
		k += 1
	return d


# ---------- 匯入卡包 ----------

var edit_pack := {}
var edit_card := ""
var pack_view: CardView


func show_import() -> void:
	var s := _clear()
	_top_bar(s)
	var p := _panel(s, Rect2(140, 90, 1000, 610))
	_label(p, "匯入卡包", Vector2(30, 14), 32, Vector2.ZERO, Color("ffe27a"))
	var help := _label(p, "一次選多張圖片就是一個卡包，每張圖變成一張卡，再逐張設定屬性。圖片會裁成正方形（%d×%d），和內建卡圖一樣。匯入後你會得到每張卡 3 張，卡包商店也買得到；這台裝置的其他玩家從商店抽。線上對戰不能帶自製卡。" % [SaveDB.ART_SIZE, SaveDB.ART_SIZE],
		Vector2(30, 62), 18, Vector2(940, 80))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size = Vector2(940, 80)
	_button(p, "選擇圖片匯入", Rect2(30, 150, 300, 60), func():
		FilePick.pick(self, true, func(images: Array): import_images(images)), 24)
	_button(p, "用內建圖片做範例卡包", Rect2(350, 150, 340, 60), import_example, 22)
	_label(p, "已匯入的卡包", Vector2(30, 226), 22, Vector2.ZERO, Color("ffe27a"))
	var sc := ScrollContainer.new()
	sc.position = Vector2(30, 262)
	sc.size = Vector2(940, 270)
	p.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(920, 0)
	sc.add_child(vb)
	if db.library.packs.is_empty():
		var none := Label.new()
		none.text = "還沒有卡包。"
		vb.add_child(none)
	for pack in db.library.packs:
		var row := Control.new()
		row.custom_minimum_size = Vector2(920, 56)
		vb.add_child(row)
		_label(row, "%s（%d 張）" % [pack.name, pack.cards.size()], Vector2(6, 12), 22)
		_button(row, "編輯", Rect2(620, 4, 130, 46), show_pack_editor.bind(pack))
		var del := _button(row, "刪除", Rect2(770, 4, 130, 46), func(): pass)
		del.pressed.connect(func():
			if del.text == "刪除":
				del.text = "確定刪除？"
			else:
				delete_pack(pack)
				show_import())
	_button(p, "返回", Rect2(420, 544, 160, 50), show_menu)


## 匯入圖片變成新卡包，並打開設定畫面
func import_images(images: Array, pname := "", defs: Array = []) -> Dictionary:
	if images.size() > SaveDB.MAX_PACK_CARDS:
		_toast("一個卡包最多 %d 張，多的沒有匯入" % SaveDB.MAX_PACK_CARDS, Color("ffb070"))
	var pack := db.add_pack(pname if pname != "" else "我的卡包 %d" % (db.library.packs.size() + 1), images, defs)
	SaveDB.grant_pack(profile, pack)
	_save()
	show_pack_editor(pack)
	return pack


## 範例：拿內建卡圖做一包，靈獸、進化、訓練家、能量各一種示範
func import_example() -> Dictionary:
	var files := ["b_embertail", "b_blazecrown", "b_bubbotter", "t_potion", "e_water"]
	var images: Array = files.map(func(f): return load("res://assets/images/cards/%s.png" % f).get_image())
	var d0 := SaveDB.default_card(1)
	d0.name = "範例幼狐"
	var d1 := SaveDB.default_card(2)
	d1.name = "範例狐王"
	d1.hp = 130
	d1.attacks[0].dmg = 40
	d1.attacks[1].merge({"name": "範例火焰", "dmg": 90, "n_type": 2, "n_any": 1, "fx": "burn"}, true)
	var d2 := SaveDB.default_card(3)
	d2.name = "範例水獺"
	d2.type = "water"
	var d3 := SaveDB.default_card(4)
	d3.merge({"kind": "trainer", "name": "範例回復藥", "effect": "potion"}, true)
	var d4 := SaveDB.default_card(5)
	d4.merge({"kind": "energy", "name": "範例水能量", "type": "water"}, true)
	var pack := import_images(images, "範例卡包 %d" % (db.library.packs.size() + 1), [d0, d1, d2, d3, d4])
	db.library.cards[pack.cards[1]].from = pack.cards[0]
	db.save_library()
	show_pack_editor(pack)
	return pack


func delete_pack(pack: Dictionary) -> void:
	db.delete_pack(pack)
	SaveDB.purge_missing(profile)
	_save()


func show_pack_editor(pack: Dictionary, id := "") -> void:
	edit_pack = pack
	if pack.cards.is_empty():
		show_import()
		return
	edit_card = id if id != "" else str(pack.cards[0])
	db.save_library()
	var s := _clear()
	var top := _panel(s, Rect2(10, 8, 1260, 60))
	_label(top, "卡包名稱", Vector2(16, 14), 22, Vector2.ZERO, Color("ffe27a"))
	_edit(top, Rect2(130, 8, 340, 44), pack.name, 12, func(t): pack.name = t)
	_label(top, "點左邊的卡片，在右邊設定屬性", Vector2(490, 16), 18)
	_button(top, "完成", Rect2(1100, 8, 146, 44), func():
		db.save_library()
		show_import())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10, 76)
	scroll.size = Vector2(464, 636)
	s.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for cid in pack.cards:
		var cv := CardView.new().setup(cid, "full")
		cv.custom_minimum_size = Vector2(108, 151)
		cv.selected = cid == edit_card
		cv.use_tap_mode()
		cv.pressed.connect(func(_v): show_pack_editor(pack, cid))
		grid.add_child(cv)
	pack_view = CardView.new().setup(edit_card, "full")
	pack_view.position = Vector2(482, 150)
	pack_view.size = Vector2(290, 406)
	pack_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(pack_view)
	_draw_card_form(_panel(s, Rect2(780, 76, 490, 636)))


## 改了一個欄位：更新卡片資料與預覽（按「完成」或換卡片時才寫進檔案）
func set_card(key: String, v) -> void:
	db.library.cards[edit_card][key] = v
	CardDB.set_custom(db.library.cards, db.custom_dir())
	pack_view.queue_redraw()


func _draw_card_form(f: Control) -> void:
	var c: Dictionary = db.library.cards[edit_card]
	var kinds := ["beast", "trainer", "energy"]
	var type_names: Array = CardDB.TYPES.map(func(t): return CardDB.TYPE_NAME[t])
	var redraw := func(): show_pack_editor(edit_pack, edit_card)
	_label(f, "種類", Vector2(14, 20), 18)
	_opt(f, Rect2(66, 12, 150, 40), ["靈獸", "訓練家", "能量"], kinds.find(c.kind), func(i):
		set_card("kind", kinds[i])
		redraw.call())
	_label(f, "名字", Vector2(232, 20), 18)
	_edit(f, Rect2(284, 12, 192, 40), c.name, 6, func(t): set_card("name", t))
	if c.kind == "trainer":
		var effects: Array = CardDB.BASE_TRAINERS.keys()
		_label(f, "效果", Vector2(14, 76), 18)
		_opt(f, Rect2(66, 68, 410, 40), effects.map(func(e): return CardDB.BASE_TRAINERS[e].name), maxi(0, effects.find(c.effect)), func(i):
			set_card("effect", effects[i])
			redraw.call())
		var t := _label(f, CardDB.BASE_TRAINERS[c.effect].text, Vector2(14, 124), 18, Vector2(460, 100))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	_label(f, "屬性", Vector2(14, 76), 18)
	_opt(f, Rect2(66, 68, 150, 40), type_names, CardDB.TYPES.find(c.type), func(i):
		set_card("type", CardDB.TYPES[i])
		redraw.call())
	if c.kind == "energy":
		return
	_label(f, "HP", Vector2(232, 76), 18)
	_spin(f, Rect2(284, 68, 192, 40), 10, 300, 10, int(c.hp), func(v): set_card("hp", v))
	var froms: Array = [""]
	for id in CardDB.BEASTS:
		if id != edit_card and CardDB.BEASTS[id].stage <= 1:
			froms.append(id)
	_label(f, "進化自", Vector2(14, 132), 18)
	_opt(f, Rect2(84, 124, 212, 40), froms.map(func(id): return "基礎靈獸" if id == "" else CardDB.card_name(id)),
		maxi(0, froms.find(str(c.get("from", "")))), func(i): set_card("from", froms[i]))
	_label(f, "撤退", Vector2(312, 132), 18)
	_spin(f, Rect2(362, 124, 114, 40), 0, 4, 1, int(c.retreat), func(v): set_card("retreat", v))
	var fx_ids: Array = CardDB.FX_CHOICES.map(func(x): return x[0])
	for n in 2:
		var a: Dictionary = c.attacks[n]
		var y := 180 + n * 226
		var set_atk := func(key: String, v):
			a[key] = v
			set_card("attacks", c.attacks)
		_label(f, "招式 %d%s" % [n + 1, "（名字留空就沒有這招）" if n == 1 else ""], Vector2(14, y), 18, Vector2.ZERO, Color("ffe27a"))
		_label(f, "名字", Vector2(14, y + 38), 18)
		_edit(f, Rect2(66, y + 30, 170, 40), str(a.name), 6, func(t): set_atk.call("name", t))
		_label(f, "傷害", Vector2(252, y + 38), 18)
		_spin(f, Rect2(304, y + 30, 172, 40), 0, 300, 10, int(a.dmg), func(v): set_atk.call("dmg", v))
		_label(f, "同屬性能量", Vector2(14, y + 90), 18)
		_spin(f, Rect2(124, y + 82, 112, 40), 0, CardDB.MAX_COST, 1, int(a.n_type), func(v): set_atk.call("n_type", v))
		_label(f, "任意能量", Vector2(252, y + 90), 18)
		_spin(f, Rect2(342, y + 82, 134, 40), 0, CardDB.MAX_COST, 1, int(a.n_any), func(v): set_atk.call("n_any", v))
		_label(f, "效果", Vector2(14, y + 142), 18)
		_opt(f, Rect2(66, y + 134, 240, 40), CardDB.FX_CHOICES.map(func(x): return x[1]), maxi(0, fx_ids.find(str(a.fx))),
			func(i): set_atk.call("fx", fx_ids[i]))
		_label(f, "數值", Vector2(322, y + 142), 18)
		_spin(f, Rect2(372, y + 134, 104, 40), 0, 100, 10, int(a.v), func(v): set_atk.call("v", v))


# ---------- 戰績 ----------

func show_records() -> void:
	var s := _clear()
	_top_bar(s)
	var st: Dictionary = profile.stats
	var p := _panel(s, Rect2(40, 90, 380, 540))
	_label(p, "統計", Vector2(20, 14), 28, Vector2.ZERO, Color("ffe27a"))
	var rate: float = 0.0 if st.games == 0 else 100.0 * st.wins / st.games
	var lines := "總場數：%d\n勝場：%d\n敗場：%d\n勝率：%.0f%%\n擊倒靈獸：%d 隻\n開卡包：%d 包\n線上對戰：%d 場（%d 勝）\n\n建立時間：%s\n最後存檔：%s" % [
		st.games, st.wins, st.losses, rate, st.kos, st.packs, st.online_games, st.online_wins,
		profile.created, profile.updated]
	_label(p, lines, Vector2(20, 60), 19, Vector2(340, 400))
	var p2 := _panel(s, Rect2(440, 90, 800, 540))
	_label(p2, "對戰紀錄（最近 %d 場）" % profile.history.size(), Vector2(20, 14), 28, Vector2.ZERO, Color("ffe27a"))
	var sc := ScrollContainer.new()
	sc.position = Vector2(16, 60)
	sc.size = Vector2(768, 466)
	p2.add_child(sc)
	var vb := VBoxContainer.new()
	sc.add_child(vb)
	if profile.history.is_empty():
		var l := Label.new()
		l.text = "還沒有對戰紀錄，快去挑戰吧！"
		vb.add_child(l)
	for h in profile.history:
		var l := Label.new()
		l.text = "%s　%s　vs %s　%s　%d 回合　★%d" % [h.date, "線上" if h.mode == "online" else "電腦", h.opp,
			"勝" if h.won else "敗", int(h.turns), int(h.stars)]
		l.add_theme_color_override("font_color", Color("7dff9a") if h.won else Color("ff9a9a"))
		l.add_theme_font_size_override("font_size", 17)
		vb.add_child(l)
	_button(s, "返回", Rect2(560, 650, 160, 50), show_menu)


func show_rules() -> void:
	var s := _clear()
	var p := _panel(s, Rect2(140, 30, 1000, 600))
	_label(p, "規則說明", Vector2(30, 14), 30, Vector2.ZERO, Color("ffe27a"))
	var l := _label(p, BattleUI.RULES, Vector2(30, 64), 18, Vector2(940, 520))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(s, "返回", Rect2(560, 650, 160, 50), show_menu if not profile.is_empty() else show_title)
