extends Control
## 主程式：畫面切換（標題／建立玩家／主選單／電腦對手／線上大廳／卡包商店／牌組編輯／戰績／規則／對戰）。
## 玩家資料由 SaveDB 存在 user://saves/，每次對戰動作、開卡包、改牌組都會自動存檔。

const PACK_PRICE := 100
const AVATARS := ["av_boy", "av_girl", "av_kid", "av_cool"]
const SECRET_TAPS := 5
const SECRET_WINDOW_MS := 3000

var db := SaveDB.new()
var profile := {}
var rng := RandomNumberGenerator.new()
var screen: Control
var secret_taps := 0
var secret_start := 0


func _ready() -> void:
	rng.randomize()
	theme = _make_theme()
	show_title()


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
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	if bg != "":
		var t := TextureRect.new()
		t.texture = CardView.tex("res://assets/images/ui/%s.png" % bg)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		screen.add_child(t)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.35)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		screen.add_child(shade)
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
	var l := _label(self, t, Vector2(0, 640), 24, Vector2(1280, 40), color)
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
		_tex_rect(row, "res://assets/images/avatars/%s.png" % pr.get("avatar", "av_boy"), Rect2(6, 4, 50, 50))
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
	_tex_rect(bar, "res://assets/images/avatars/%s.png" % profile.avatar, Rect2(8, 6, 54, 54))
	_label(bar, profile.name, Vector2(72, 16), 26)
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
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	var p := _panel(dim, Rect2(340, 170, 600, 360), 0.95)
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
		["牌組編輯", show_deck_editor], ["戰績紀錄", show_records], ["規則說明", show_rules], ["換玩家", show_title]]
	var p := _panel(s, Rect2(440, 100, 400, 80 + items.size() * 66))
	for i in items.size():
		var b := _button(p, items[i][0], Rect2(40, 30 + i * 66, 320, 54), items[i][1], 24)
		if i == 0 and profile.get("current_match") is Dictionary:
			b.add_theme_color_override("font_color", Color("7dff9a"))
	var mute := _button(s, "音效開關", Rect2(1130, 660, 130, 44), func(): Audio.toggle_mute(), 18)
	mute.tooltip_text = "開／關音效與音樂"


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
	var err := CardDB.validate_deck(_deck())
	if err != "":
		_toast("你的牌組不合法：" + err, Color("ff7070"))
		return
	var o: Dictionary = CardDB.OPPONENTS[i]
	var b := Battle.new()
	b.setup(rng.randi() % 2000000000, _deck(), CardDB.deck_by_name(o.deck), profile.name, o.name)
	profile.current_match = {"opp": i, "save": b.to_save()}
	_save()
	_run_ai_battle(b, i)


func resume_match() -> void:
	var cm: Dictionary = profile.current_match
	var b := Battle.from_save(cm.save)
	_run_ai_battle(b, int(cm.opp))


func _run_ai_battle(b: Battle, i: int) -> void:
	var o: Dictionary = CardDB.OPPONENTS[i]
	var s := _clear("", "")
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
	var help := _label(p, "一人「開房間」把 6 碼房號告訴朋友，另一人輸入房號「加入」。\n電腦版和網頁版可以互打，使用你目前的牌組。",
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
		if CardDB.validate_deck(_deck()) != "":
			status.text = "牌組不合法：" + CardDB.validate_deck(_deck())
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
		if CardDB.validate_deck(_deck()) != "":
			status.text = "牌組不合法：" + CardDB.validate_deck(_deck())
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
	var s := _clear("", "")
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
	var buy := _button(p, "購買（%d 金幣）" % PACK_PRICE, Rect2(80, 510, 260, 60), func(): pass, 24)
	buy.pressed.connect(func():
		if profile.coins < PACK_PRICE:
			Audio.play("error")
			_toast("金幣不夠，去打電腦對戰賺金幣吧！", Color("ff7070"))
			return
		buy.disabled = true
		profile.coins -= PACK_PRICE
		var got := SaveDB.open_pack(rng)
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


func show_deck_editor(idx := -1) -> void:
	if idx >= 0:
		edit_index = idx
	else:
		edit_index = clampi(profile.active_deck, 0, profile.decks.size() - 1)
	edit_deck = profile.decks[edit_index].cards.duplicate()
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
		profile.decks.append({"name": "新牌組 %d" % (profile.decks.size() + 1), "cards": []})
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
		edit_deck = _auto_deck()
		_draw_editor_lists(s), 17)
	var save_btn := _button(top, "儲存並使用", Rect2(958, 10, 150, 40), func(): pass, 17)
	_button(top, "返回", Rect2(1114, 10, 130, 40), show_menu, 17)
	save_btn.pressed.connect(func():
		var err := CardDB.validate_deck(edit_deck)
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
		["energy", "能量"], ["trainer", "訓練家"]]
	for i in filters.size():
		var f: Array = filters[i]
		var b := _button(s, f[1], Rect2(14 + i * 100, 76, 94, 36), func():
			edit_filter = f[0]
			_draw_editor_lists(s), 17)
		b.modulate = Color.WHITE if edit_filter == f[0] else Color(0.7, 0.7, 0.7)
	_draw_editor_lists(s)


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
		cv.tooltip_text = "點一下加入牌組"
		cv.pressed.connect(func(_v):
			var limit := 99 if CardDB.is_energy(id) else mini(owned, CardDB.MAX_COPIES)
			if owned <= 0:
				Audio.play("error")
				_toast("還沒有這張卡，去卡包商店抽抽看！", Color("ffb070"))
			elif edit_deck.size() >= CardDB.DECK_SIZE:
				Audio.play("error")
				_toast("牌組已經 %d 張了" % CardDB.DECK_SIZE, Color("ffb070"))
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
	var err := CardDB.validate_deck(edit_deck)
	_label(p, "牌組 %d / %d 張" % [edit_deck.size(), CardDB.DECK_SIZE], Vector2(14, 8), 22, Vector2.ZERO,
		Color("7dff9a") if err == "" else Color("ffb070"))
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
		row.pressed.connect(func():
			Audio.play("click")
			edit_deck.erase(id)
			_draw_editor_lists(s))
		vb.add_child(row)


func _filter_ok(id: String) -> bool:
	match edit_filter:
		"all": return true
		"energy": return CardDB.is_energy(id)
		"trainer": return CardDB.is_trainer(id)
	if CardDB.is_beast(id):
		return CardDB.BEASTS[id].type == edit_filter
	if CardDB.is_energy(id):
		return CardDB.ENERGY[id].type == edit_filter
	return false


## 依收藏自動組一副：挑擁有最多靈獸的兩種屬性
func _auto_deck() -> Array:
	var score := {}
	for t in CardDB.TYPES:
		score[t] = 0
		for line in CardDB.LINES[t]:
			for id in line:
				score[t] += mini(int(profile.collection.get(id, 0)), 3)
	var types: Array = CardDB.TYPES.duplicate()
	types.sort_custom(func(a, b): return score[a] > score[b])
	var d: Array = []
	for t in types.slice(0, 2):
		for line in CardDB.LINES[t]:
			for id in line:
				for i in mini(int(profile.collection.get(id, 0)), 3 if CardDB.BEASTS[id].stage == 0 else 2):
					if d.size() < 14:
						d.append(id)
	for id in ["potion", "finder", "journal", "scroll", "whistle", "notes", "band", "bell", "recycle"]:
		for i in mini(int(profile.collection.get(id, 0)), 2):
			if d.size() < 20:
				d.append(id)
	var main_types: Array = []
	for id in d:
		if CardDB.is_beast(id) and not main_types.has(CardDB.BEASTS[id].type):
			main_types.append(CardDB.BEASTS[id].type)
	if main_types.is_empty():
		main_types = [types[0]]
	var k := 0
	while d.size() < CardDB.DECK_SIZE:
		d.append("e_" + main_types[k % main_types.size()])
		k += 1
	return d


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
