extends Node
## 線上對戰測試（要有 config/online.cfg、Firestore 規則已部署）：
## 同一個程式裡模擬兩位玩家：A 開房間、B 用房號加入，各自跑一份 Battle 引擎，
## 輪到誰就由 AI 選動作、寫進 Firestore，另一邊讀出來照做，打完檢查兩邊結果完全一樣。
## 用法：godot --headless --path . res://tests/online_test.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	await _run()
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _run() -> void:
	check(Net.enabled(), "讀到線上設定")
	if not Net.enabled():
		return
	var deck_a := CardDB.starter("fire")
	var deck_b := CardDB.starter("water")
	var r: Dictionary = await Net.create_room("測試A", deck_a)
	check(not r.is_empty(), "開房間 " + str(r.get("code", "")) + " " + Net.last_error)
	if r.is_empty():
		return
	var bad: Dictionary = await Net.join_room("ZZZZZZ", "測試B", deck_b)
	check(bad.has("error"), "加入不存在的房號會失敗")
	var room: Dictionary = await Net.join_room(r.code, "測試B", deck_b)
	check(not room.has("error"), "B 加入房間 " + str(room.get("error", "")))
	var again: Dictionary = await Net.join_room(r.code, "路人C", deck_b)
	check(again.has("error"), "滿房後第三人不能加入")
	var host_view: Dictionary = await Net.get_room(r.code)
	check(host_view.get("guest", "") == "測試B" and host_view.get("status", "") == "play", "A 看到 B 已加入")
	# 兩份引擎
	var e: Array = []
	for i in 2:
		var b := Battle.new()
		b.setup(int(host_view.seed), str(host_view.host_deck).split(","), str(host_view.guest_deck).split(","),
			str(host_view.host), str(host_view.guest))
		e.append(b)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var steps := 0
	while e[0].winner < 0 and steps < 400:
		var who: int = e[0].actor()
		var a := BattleAI.choose(e[who], who, 2, rng)
		var idx: int = e[who].history.size()
		if not e[who].apply(a):
			check(false, "動作不合法 %s" % str(a))
			return
		var sent: bool = await Net.send_action(r.code, idx, who, a)
		if not sent:
			check(false, "傳送第 %d 個動作失敗 %s" % [idx, Net.last_error])
			return
		var got: Dictionary = await Net.get_action(r.code, idx)
		if got.is_empty() or not e[1 - who].apply(got.a):
			check(false, "對方讀取／套用第 %d 個動作失敗" % idx)
			return
		steps += 1
	check(e[0].winner >= 0, "線上對戰分出勝負（%d 個動作）" % steps)
	check(e[0].winner == e[1].winner and e[0].turn == e[1].turn and e[0].players[0].stars == e[1].players[0].stars
		and e[0].players[1].hand.size() == e[1].players[1].hand.size(), "兩邊狀態一致")
	var dup: Dictionary = await Net.get_action(r.code, 0)
	check(not dup.is_empty(), "動作紀錄可以重讀")
	await _ui_match()


## 第二部分：兩個真正的對戰畫面（BattleUI）透過 Firestore 對打，測畫面的傳送與輪詢
func _ui_match() -> void:
	Engine.time_scale = 4.0
	var r: Dictionary = await Net.create_room("畫面A", CardDB.starter("leaf"))
	var room: Dictionary = await Net.join_room(r.code, "畫面B", CardDB.starter("thunder"))
	check(not room.has("error"), "畫面對打：開房並加入 " + str(r.get("code", "")))
	var uis: Array = []
	for me in 2:
		var b := Battle.new()
		b.setup(int(room.seed), str(room.host_deck).split(","), str(room.guest_deck).split(","), str(room.host), str(room.guest))
		var ui := BattleUI.new()
		add_child(ui)
		ui.start(b, me, {"kind": "online", "code": r.code, "level": 1})
		uis.append(ui)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var t0 := Time.get_ticks_msec()
	while (uis[0].b.winner < 0 or uis[1].b.winner < 0) and Time.get_ticks_msec() - t0 < 300000:
		await get_tree().process_frame
		for ui in uis:
			if ui._can_input() and ui.send_queue.is_empty():
				ui._do(BattleAI.choose(ui.b, ui.me, 2, rng))
	check(uis[0].b.winner >= 0 and uis[0].b.winner == uis[1].b.winner and uis[0].b.history.size() == uis[1].b.history.size(),
		"畫面對打分出勝負且兩邊一致（%d 個動作）" % uis[0].b.history.size())
