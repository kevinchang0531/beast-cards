class_name BattleUI
extends Control
## 對戰畫面：顯示場面、處理玩家點擊、驅動電腦或線上對手、播放動畫音效。
## 用法：var ui := BattleUI.new(); add_child(ui); ui.start(battle, me, opts)
## opts：{kind: "ai"/"online", level, opp_avatar, my_avatar, code, autosave: Callable(save_dict)}
## 結束時發出 finished({won, turns, stars, kos, surrendered, paused})

signal finished(result: Dictionary)

const OPP_BENCH_Y := 4.0
const OPP_ACT_Y := 128.0
const ME_ACT_Y := 292.0
const ME_BENCH_Y := 456.0
const HAND_Y := 584.0
const BENCH_SIZE := Vector2(84, 118)
const ACT_SIZE := Vector2(112, 157)
const HAND_SIZE := Vector2(96, 134)
const CENTER_X := 600.0

var b: Battle
var me := 0
var opts := {}
var rng := RandomNumberGenerator.new()

var busy := false
var sel_mode := ""          # "" / hand / retreat / promote
var sel_hand := -1
var sel_cands: Array = []
var ai_timer := 0.0
var polling := false
var send_queue: Array = []
var sending := false
var wait_time := 0.0
var done := false
var log_shown := 0

var board: Control
var detail: CardView
var log_box: RichTextLabel
var msg: Label
var banner: Label
var atk_btns: Array = []
var retreat_btn: Button
var end_btn: Button
var info := [{}, {}]
var slot_views := {}        # "p:slot" → CardView
var result_panel: Control


func start(battle: Battle, my_index: int, o: Dictionary) -> void:
	b = battle
	me = my_index
	opts = o
	rng.randomize()
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	_build()
	_render()
	Audio.bgm("bgm_boss" if int(opts.get("level", 0)) >= 3 else "bgm_battle")
	_show_banner("對戰開始！" + ("你先攻" if b.first == me else "對手先攻"))
	if b.winner >= 0:
		_show_result()


# ---------- 建立介面 ----------

func _build() -> void:
	for pi in 2:
		var who := 1 - me if pi == 0 else me
		var box := _panel(Rect2(8, 8 if pi == 0 else 512, 184, 200))
		var av := TextureRect.new()
		av.position = Vector2(8, 8)
		av.size = Vector2(64, 64)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.texture = CardView.tex(CardDB.avatar_path(str(opts.get("my_avatar" if who == me else "opp_avatar", "av_boy"))))
		box.add_child(av)
		var nm := _label(b.names[who], Vector2(76, 10), 15, Vector2(106, 24))
		nm.clip_text = true
		box.add_child(nm)
		var stars := _label("", Vector2(78, 36), 24, Vector2(100, 32))
		stars.add_theme_color_override("font_color", Color("ffd84a"))
		box.add_child(stars)
		var counts := _label("", Vector2(8, 80), 15, Vector2(170, 110))
		box.add_child(counts)
		info[who] = {"stars": stars, "counts": counts, "box": box}

	board = Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

	# 右側：卡片詳細、按鈕、紀錄
	detail = CardView.new()
	detail.position = Vector2(1046, 6)
	detail.size = Vector2(224, 314)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.visible = false
	add_child(detail)
	for n in 2:
		var bt := _button("", Rect2(1040, 326 + n * 52, 236, 48), _on_attack.bind(n))
		bt.add_theme_font_size_override("font_size", 15)
		atk_btns.append(bt)
	retreat_btn = _button("撤退", Rect2(1040, 432, 116, 40), _on_retreat)
	end_btn = _button("結束回合", Rect2(1160, 432, 116, 40), _on_end)
	_button("選單", Rect2(1040, 476, 70, 32), _on_menu).add_theme_font_size_override("font_size", 14)
	var mute := _button("音效", Rect2(1114, 476, 70, 32), func(): Audio.toggle_mute())
	mute.add_theme_font_size_override("font_size", 14)
	_button("規則", Rect2(1188, 476, 88, 32), _on_rules).add_theme_font_size_override("font_size", 14)
	log_box = RichTextLabel.new()
	log_box.position = Vector2(1040, 514)
	log_box.size = Vector2(236, 200)
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 13)
	var lb := StyleBoxFlat.new()
	lb.bg_color = Color(0, 0, 0, 0.6)
	lb.set_corner_radius_all(6)
	lb.content_margin_left = 6
	lb.content_margin_right = 6
	log_box.add_theme_stylebox_override("normal", lb)
	add_child(log_box)

	msg = _label("", Vector2(700, 262), 18, Vector2(330, 56))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_color_override("font_color", Color("ffe680"))
	msg.add_theme_constant_override("outline_size", 6)
	msg.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(msg)

	banner = _label("", Vector2(0, 300), 52, Vector2(1280, 90))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 14)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.add_theme_color_override("font_color", Color("fff2a8"))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0
	add_child(banner)


func _panel(r: Rect2) -> Panel:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.15, 0.78)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(0.85, 0.7, 0.3, 0.8)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _label(t: String, pos: Vector2, fs: int, sz := Vector2.ZERO) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	if sz != Vector2.ZERO:
		l.size = sz
	l.add_theme_font_size_override("font_size", fs)
	return l


func _button(t: String, r: Rect2, cb: Callable) -> Button:
	var bt := Button.new()
	bt.text = t
	bt.position = r.position
	bt.size = r.size
	bt.pressed.connect(func():
		Audio.play("click")
		cb.call())
	add_child(bt)
	return bt


# ---------- 畫面更新 ----------

func _render() -> void:
	for c in board.get_children():
		c.queue_free()
	slot_views.clear()
	for who in [1 - me, me]:
		var p: Dictionary = b.players[who]
		var top: bool = who != me
		# 戰鬥位置
		var act_y := OPP_ACT_Y if top else ME_ACT_Y
		if p.active != null:
			_add_beast(who, 0, Vector2(CENTER_X - ACT_SIZE.x / 2, act_y), ACT_SIZE)
		else:
			_add_slot_frame(Rect2(Vector2(CENTER_X - ACT_SIZE.x / 2, act_y), ACT_SIZE))
		# 後備
		var by := OPP_BENCH_Y if top else ME_BENCH_Y
		for i in CardDB.BENCH_MAX:
			var pos := Vector2(CENTER_X - 2 * 96 + i * 96 + 6, by)
			if i < p.bench.size():
				_add_beast(who, i + 1, pos, BENCH_SIZE)
			else:
				_add_slot_frame(Rect2(pos, BENCH_SIZE))
		# 牌堆與棄牌
		var deck := CardView.new().setup("", "full", false)
		deck.position = Vector2(860, by)
		deck.size = BENCH_SIZE
		deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck.count_label = str(p.deck.size())
		deck.visible = not p.deck.is_empty()
		board.add_child(deck)
		if not p.discard.is_empty():
			var dv := CardView.new().setup(b.card_id(p.discard[-1]), "mini")
			dv.position = Vector2(952, by)
			dv.size = BENCH_SIZE
			dv.count_label = str(p.discard.size())
			dv.hovered.connect(_on_hover)
			board.add_child(dv)
		# 對手手牌（卡背）
		if top:
			var n: int = p.hand.size()
			for i in n:
				var hv := CardView.new().setup("", "full", false)
				hv.position = Vector2(210 + i * minf(18.0, 150.0 / maxf(1, n)), 8)
				hv.size = Vector2(44, 62)
				hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				board.add_child(hv)
	# 我的手牌
	var hand: Array = b.players[me].hand
	var n := hand.size()
	var step := minf(102.0, (830.0 - HAND_SIZE.x) / maxf(1, n - 1))
	var x0 := CENTER_X - (step * (n - 1) + HAND_SIZE.x) / 2
	var my_turn := b.actor() == me and b.winner < 0 and b.pending.is_empty()
	for i in n:
		var cv := CardView.new().setup(b.card_id(hand[i]), "full")
		cv.position = Vector2(x0 + i * step, HAND_Y)
		cv.size = HAND_SIZE
		cv.set_meta("hand", i)
		var playable := false
		if my_turn:
			for a in b.legal_actions(me):
				if int(a.get("hand", -1)) == i:
					playable = true
					break
		cv.highlight = playable and sel_mode == ""
		cv.selected = sel_mode == "hand" and sel_hand == i
		cv.pressed.connect(_on_hand_pressed)
		cv.hovered.connect(_on_hover)
		cv.mouse_entered.connect(func(): cv.position.y = HAND_Y - 24)
		cv.mouse_exited.connect(func(): cv.position.y = HAND_Y)
		board.add_child(cv)
	# 目標高亮
	for k in _target_slots():
		var v: CardView = slot_views.get("%d:%d" % [me, k])
		if v:
			v.highlight = true
	_update_side()


func _add_beast(who: int, slot: int, pos: Vector2, sz: Vector2) -> void:
	var bt: Dictionary = b.beast_at(who, slot)
	var cv := CardView.new().setup(b.card_id(bt.uid), "mini")
	cv.beast = bt
	cv.battle = b
	cv.position = pos
	cv.size = sz
	cv.set_meta("who", who)
	cv.set_meta("slot", slot)
	cv.pressed.connect(_on_slot_pressed)
	cv.hovered.connect(_on_hover)
	board.add_child(cv)
	slot_views["%d:%d" % [who, slot]] = cv


func _add_slot_frame(r: Rect2) -> void:
	var f := Panel.new()
	f.position = r.position
	f.size = r.size
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.border_color = Color(0.6, 0.8, 1.0, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	f.add_theme_stylebox_override("panel", sb)
	board.add_child(f)


func _target_slots() -> Array:
	var out: Array = []
	for a in sel_cands:
		if sel_mode == "hand" and a.has("slot"):
			out.append(int(a.slot))
		elif sel_mode in ["retreat", "promote"]:
			out.append(int(a.bench) + 1)
	return out


func _update_side() -> void:
	for who in [0, 1]:
		var p: Dictionary = b.players[who]
		var st := ""
		for i in CardDB.STARS_TO_WIN:
			st += "★" if i < p.stars else "☆"
		info[who].stars.text = st
		info[who].counts.text = "牌組 %d 張\n手牌 %d 張\n棄牌 %d 張" % [p.deck.size(), p.hand.size(), p.discard.size()]
		var sb: StyleBoxFlat = info[who].box.get_theme_stylebox("panel")
		sb.border_color = Color("ffd84a") if b.current == who and b.winner < 0 else Color(0.5, 0.5, 0.6, 0.6)
		sb.set_border_width_all(4 if b.current == who else 2)
	var my_turn := b.actor() == me and b.winner < 0 and b.pending.is_empty() and not busy
	var act = b.players[me].active
	for n in 2:
		var bt: Button = atk_btns[n]
		if act == null or n >= b.beast_data(act).attacks.size():
			bt.visible = false
			continue
		bt.visible = true
		var atk: Dictionary = b.beast_data(act).attacks[n]
		var cost := ""
		for c in atk.cost:
			cost += CardDB.TYPE_NAME[c]
		var dmg := b.preview_damage(me, n)
		bt.text = "%s  %s\n[%s]" % [atk.name, (str(dmg) + " 傷害") if atk.dmg > 0 else "", cost]
		bt.disabled = not (my_turn and b.can_attack(me, n))
	var can_retreat := false
	for a in b.legal_actions(me):
		if a.t == "retreat":
			can_retreat = true
	retreat_btn.disabled = not (my_turn and can_retreat)
	end_btn.disabled = not my_turn
	# 訊息
	if b.winner >= 0:
		msg.text = ""
	elif b.actor() == me and not b.pending.is_empty():
		msg.text = "你的靈獸被擊倒了！\n請點一隻後備靈獸上場"
	elif b.actor() != me:
		msg.text = "對手思考中……" if opts.get("kind") == "ai" else "等待對手行動……"
	elif sel_mode == "hand":
		msg.text = "請點選目標靈獸（右鍵取消）"
	elif sel_mode == "retreat":
		msg.text = "請點要換上場的後備靈獸（右鍵取消）"
	elif b.turn == 1:
		msg.text = "先攻第一回合不能攻擊"
	else:
		msg.text = ""
	while log_shown < b.log_lines.size():
		var line: String = b.log_lines[log_shown]
		if line.begins_with("——"):
			log_box.append_text("[color=#ffd84a]%s[/color]\n" % line)
		elif line.begins_with("★"):
			log_box.append_text("[color=#ff9a4a][b]%s[/b][/color]\n" % line)
		else:
			log_box.append_text(line + "\n")
		log_shown += 1


func _show_banner(t: String) -> void:
	banner.text = t
	var tw := create_tween()
	banner.modulate.a = 0
	banner.scale = Vector2(1, 1)
	tw.tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.tween_interval(0.9)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)


func _float_text(t: String, pos: Vector2, c: Color, fs := 40) -> void:
	var l := _label(t, pos, fs, Vector2(160, 60))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y - 60, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_callback(l.queue_free)


# ---------- 玩家輸入 ----------

func _on_hover(cv: CardView) -> void:
	if not cv.face_up or cv.id == "":
		return
	detail.setup(cv.id, "full")
	detail.visible = true


func _can_input() -> bool:
	return not busy and not done and b.winner < 0 and b.actor() == me


func _on_hand_pressed(cv: CardView) -> void:
	if not _can_input() or not b.pending.is_empty():
		return
	var i: int = cv.get_meta("hand")
	if sel_mode == "hand" and sel_hand == i:
		_cancel()
		return
	var cands: Array = []
	for a in b.legal_actions(me):
		if int(a.get("hand", -1)) == i:
			cands.append(a)
	if cands.is_empty():
		Audio.play("error")
		msg.text = _why_not(cv.id)
		return
	if cands.size() == 1 and (cands[0].t == "basic" or int(cands[0].get("slot", -1)) == -1):
		_do(cands[0])
		return
	sel_mode = "hand"
	sel_hand = i
	sel_cands = cands
	_render()


func _why_not(id: String) -> String:
	var p: Dictionary = b.players[me]
	if CardDB.is_energy(id):
		return "這回合已經附加過能量了"
	if CardDB.is_beast(id):
		if CardDB.BEASTS[id].stage == 0:
			return "後備已經滿了（最多 %d 隻）" % CardDB.BENCH_MAX
		if b.turn < 3:
			return "雙方第一回合不能進化"
		return "場上沒有可以進化成 %s 的靈獸（剛放上場的那回合不能進化）" % CardDB.BEASTS[id].name
	if CardDB.TRAINERS[id].kind == "support" and p.support_used:
		return "支援卡每回合只能用 1 張"
	return "現在不能使用這張卡"


func _on_slot_pressed(cv: CardView) -> void:
	var who: int = cv.get_meta("who")
	var slot: int = cv.get_meta("slot")
	if not _can_input() or who != me:
		return
	if sel_mode == "" and not b.pending.is_empty():
		sel_mode = "promote"
		sel_cands = b.legal_actions(me)
	for a in sel_cands:
		var s := int(a.slot) if sel_mode == "hand" else int(a.get("bench", -9)) + 1
		if s == slot:
			_do(a)
			return
	if sel_mode != "":
		Audio.play("error")


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_cancel()


func _cancel() -> void:
	if sel_mode in ["hand", "retreat"]:
		sel_mode = ""
		sel_hand = -1
		sel_cands = []
		_render()


func _on_attack(n: int) -> void:
	if _can_input() and b.can_attack(me, n):
		_do({"t": "attack", "p": me, "n": n})


func _on_retreat() -> void:
	if not _can_input():
		return
	sel_cands = b.legal_actions(me).filter(func(a): return a.t == "retreat")
	if sel_cands.is_empty():
		return
	sel_mode = "retreat"
	sel_hand = -1
	_render()


func _on_end() -> void:
	if _can_input() and b.pending.is_empty():
		if b.can_attack(me, 0) or b.can_attack(me, 1):
			var dlg := ConfirmationDialog.new()
			dlg.dialog_text = "你還可以攻擊，確定直接結束回合嗎？"
			dlg.ok_button_text = "結束回合"
			dlg.cancel_button_text = "取消"
			add_child(dlg)
			dlg.confirmed.connect(func(): _do({"t": "end", "p": me}))
			dlg.popup_centered()
			return
		_do({"t": "end", "p": me})


func _on_menu() -> void:
	var dlg := ConfirmationDialog.new()
	if opts.get("kind") == "ai":
		dlg.dialog_text = "要離開對戰嗎？\n「暫停離開」會保留進度，下次從主選單繼續。\n「投降」算輸一場。"
		dlg.ok_button_text = "暫停離開"
		dlg.add_button("投降", true, "surrender")
	else:
		dlg.dialog_text = "要投降並離開線上對戰嗎？（算輸一場）"
		dlg.ok_button_text = "投降"
	dlg.cancel_button_text = "繼續對戰"
	add_child(dlg)
	dlg.confirmed.connect(func():
		if opts.get("kind") == "ai":
			_finish({"paused": true})
		else:
			_surrender())
	dlg.custom_action.connect(func(act):
		if act == "surrender":
			dlg.hide()
			_surrender())
	dlg.popup_centered()


func _on_rules() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "規則"
	dlg.dialog_text = RULES
	add_child(dlg)
	dlg.popup_centered()


func _surrender() -> void:
	if b.winner >= 0:
		return
	var a := {"t": "surrender", "p": me}
	b.apply(a)
	if opts.get("kind") == "online":
		send_queue.append([b.history.size() - 1, a])
		_pump_send()
	_after_apply()


# ---------- 執行動作與動畫 ----------

func _do(a: Dictionary) -> void:
	sel_mode = ""
	sel_hand = -1
	sel_cands = []
	if not b.apply(a):
		Audio.play("error")
		_render()
		return
	if opts.get("kind") == "online" and int(a.p) == me:
		send_queue.append([b.history.size() - 1, a])
		_pump_send()
	_after_apply()


func _pump_send() -> void:
	if sending:
		return
	sending = true
	while not send_queue.is_empty():
		var item: Array = send_queue[0]
		var ok: bool = await Net.send_action(str(opts.code), item[0], me, item[1])
		if ok:
			send_queue.pop_front()
		else:
			msg.text = "連線不穩，重新傳送中……"
			await get_tree().create_timer(2.0).timeout
	sending = false


func _after_apply() -> void:
	busy = true
	var evs: Array = b.events.duplicate()
	if opts.has("autosave") and opts.get("kind") == "ai":
		opts.autosave.call(b.to_save())
	var attack_ev = null
	for ev in evs:
		if ev.e == "attack":
			attack_ev = ev
	if attack_ev != null:
		# 先在攻擊前的畫面上播攻擊動畫（被擊倒的靈獸還在）
		var atk_view: CardView = slot_views.get("%d:0" % attack_ev.p)
		var def_view: CardView = slot_views.get("%d:0" % (1 - attack_ev.p))
		if atk_view:
			var p0 := atk_view.position
			var tw := create_tween()
			tw.tween_property(atk_view, "position:y", p0.y + (-30.0 if attack_ev.p == me else 30.0), 0.12)
			tw.tween_property(atk_view, "position:y", p0.y, 0.15)
		Audio.play("atk_" + str(attack_ev.type))
		await get_tree().create_timer(0.3).timeout
		if def_view and int(attack_ev.dmg) > 0:
			def_view.shake = 1.0
			def_view.flash = 1.0
			Audio.play("hit")
			_float_text("-%d" % attack_ev.dmg + ("!!" if attack_ev.weak else ""),
				def_view.position + Vector2(def_view.size.x / 2 - 80, 20), Color("ff5050") if not attack_ev.weak else Color("ffb020"))
			if attack_ev.weak:
				_float_text("屬性相剋！", def_view.position + Vector2(def_view.size.x / 2 - 80, -20), Color("ffe040"), 26)
		await get_tree().create_timer(0.55).timeout
	_render()
	for ev in evs:
		match ev.e:
			"turn":
				await get_tree().create_timer(0.25).timeout
				Audio.play("turn")
				_show_banner("你的回合" if ev.p == me else "對手的回合")
			"draw":
				if ev.p == me:
					Audio.play("draw")
			"play", "promote", "retreat":
				Audio.play("play")
				_flash_slot(ev.p, int(ev.get("slot", 0)))
			"evolve":
				Audio.play("evolve")
				_flash_slot(ev.p, ev.slot)
				var v: CardView = slot_views.get("%d:%d" % [ev.p, ev.slot])
				if v:
					_float_text("進化！", v.position + Vector2(v.size.x / 2 - 80, 0), Color("ffe040"), 30)
				await get_tree().create_timer(0.5).timeout
			"energy":
				Audio.play("energy")
				_flash_slot(ev.p, ev.slot)
			"trainer":
				Audio.play("play")
				detail.setup(ev.id, "full")
				detail.visible = true
				if ev.p != me:
					await get_tree().create_timer(0.6).timeout
			"shuffle":
				Audio.play("shuffle")
			"coin":
				Audio.play("coin")
				_float_text("擲硬幣：" + ("正面！" if ev.heads else "反面"), Vector2(CENTER_X - 80, 268), Color.WHITE, 26)
				await get_tree().create_timer(0.4).timeout
			"burn":
				Audio.play("burn")
			"para":
				Audio.play("paralyze")
			"heal":
				Audio.play("heal")
			"ko":
				Audio.play("ko")
				await get_tree().create_timer(0.35).timeout
			"star":
				Audio.play("star")
				_float_text("★ +1", Vector2(30, 40 if ev.p != me else 560), Color("ffd84a"), 36)
			"win":
				await get_tree().create_timer(0.6).timeout
				Audio.play("win" if ev.p == me else "lose")
	busy = false
	_update_side()
	if b.winner >= 0:
		_show_result()
	elif b.actor() == me and not b.pending.is_empty():
		sel_mode = "promote"
		sel_cands = b.legal_actions(me)
		_render()


func _flash_slot(who: int, slot: int) -> void:
	var v: CardView = slot_views.get("%d:%d" % [who, slot])
	if v:
		v.flash = 1.0


# ---------- 對手驅動 ----------

func _process(delta: float) -> void:
	if done or busy or b == null or b.winner >= 0 or b.actor() == me:
		wait_time = 0.0
		return
	if opts.get("kind") == "ai":
		ai_timer += delta
		if ai_timer >= 0.75:
			ai_timer = 0.0
			var a := BattleAI.choose(b, b.actor(), int(opts.get("level", 1)), rng)
			if a.is_empty() or not b.apply(a):
				b.apply({"t": "end", "p": b.actor()})
			_after_apply()
	elif opts.get("kind") == "online":
		wait_time += delta
		if not polling:
			_poll()
		if wait_time > 1.0:
			msg.text = "等待對手行動……（%d 秒）" % int(wait_time)


func _poll() -> void:
	polling = true
	var idx := b.history.size()
	var got: Dictionary = await Net.get_action(str(opts.code), idx)
	if not done and not got.is_empty() and b.history.size() == idx:
		if int(got.by) != me and b.apply(got.a):
			wait_time = 0.0
			_after_apply()
	else:
		await get_tree().create_timer(1.0).timeout
	polling = false


# ---------- 結算 ----------

func _show_result() -> void:
	if result_panel != null:
		return
	var won := b.winner == me
	Audio.bgm("bgm_victory" if won else "")
	result_panel = _panel(Rect2(390, 200, 500, 300))
	var t := _label("勝利！" if won else "落敗……", Vector2(0, 24), 56, Vector2(500, 80))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color("ffd84a") if won else Color("aab4c8"))
	result_panel.add_child(t)
	var r := _label(b.win_reason + "\n共 %d 回合" % b.turn, Vector2(0, 110), 20, Vector2(500, 70))
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(r)
	var bt := Button.new()
	bt.text = "回到選單"
	bt.position = Vector2(170, 210)
	bt.size = Vector2(160, 54)
	bt.pressed.connect(func():
		Audio.play("click")
		_finish({}))
	result_panel.add_child(bt)


func _finish(extra: Dictionary) -> void:
	if done:
		return
	done = true
	var res := {"won": b.winner == me, "turns": b.turn, "stars": b.players[me].stars,
		"kos": b.players[me].stars, "over": b.winner >= 0}
	res.merge(extra, true)
	finished.emit(res)


const RULES := """【目標】先擊倒對手 3 隻靈獸（拿到 3 顆★星徽）就獲勝；對手場上沒有靈獸、或輪到他時牌組抽光，也算你贏。

【每回合可以做】
・抽 1 張牌（自動）
・把基礎靈獸放到後備（最多 4 隻）
・進化：把進化卡疊在對應的靈獸上，可以從基礎到一階、再到二階（雙方第一回合、剛上場或剛進化那回合不能進化），傷害保留、狀態解除
・附加 1 張能量卡到自己任一隻靈獸
・使用道具卡（不限張數）、支援卡（每回合 1 張）
・撤退 1 次：丟掉撤退費用的能量，和後備交換
・最後用戰鬥靈獸攻擊（需要的能量要夠），攻擊後回合結束。先攻第一回合不能攻擊。

【屬性相剋】火 → 草 → 岩 → 雷 → 水 → 火，打被剋的屬性傷害 ×2。
【狀態】灼傷：每回合開始受 10 傷害。麻痺：下回合不能攻擊和撤退。撤退或進化會解除。

【操作】點手牌出牌（金框＝可以出），需要目標時再點自己的靈獸；滑鼠移到卡片上可在右邊看詳細內容；右鍵取消選擇。"""
