extends SceneTree
## 引擎＋AI 快速測試：AI 對 AI 打 300 場，檢查不會卡住、都分出勝負、存檔重播結果一致。
## 用法：godot --headless --path . --script res://tests/engine_test.gd

## 內建卡的舊存檔重播指紋：批次匯入版本加入前算的，改了內建卡或規則才會變
const OLD_REPLAY_HASH := "d840b85f7ed8a6c4dd98453de1c5c1f7"
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "FAIL  ") + what)
	fails += 0 if ok else 1


func _test_old_replay() -> void:
	var names := ["starter_fire", "starter_water", "starter_leaf", "starter_thunder", "starter_rock", "luna", "drake"]
	var all := ""
	var no_field := true
	for g in 14:
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + g
		var b := Battle.new()
		b.setup(5000 + g, CardDB.deck_by_name(names[g % 7]), CardDB.deck_by_name(names[(g + 3) % 7]), "甲", "乙")
		var guard := 0
		while b.winner < 0 and guard < 3000:
			guard += 1
			if not b.apply(BattleAI.choose(b, b.actor(), 2, rng)):
				break
		var save = JSON.parse_string(JSON.stringify(b.to_save()))
		no_field = no_field and not save.has("fx_ver")
		var r := Battle.from_save(save)
		all += JSON.stringify([r.cards, r.players, r.turn, r.current, r.winner, r.log_lines]) + str(r.rng.state)
	check(no_field, "內建卡存檔格式不變（沒有 fx_ver）")
	check(all.md5_text() == OLD_REPLAY_HASH, "舊 Battle 重播結果和改版前完全相同")


func _imported_defs(ver: int) -> Dictionary:
	var a1 := {"name": "連擊", "dmg": 20, "n_type": 1, "n_any": 0, "fx": "flip_plus", "v": 30}
	var a2 := {"name": "猛火", "dmg": 60, "n_type": 1, "n_any": 1, "fx": "burn", "v": 0}
	return {
		"x_T_1": {"kind": "beast", "name": "匯入甲", "type": "fire", "hp": 80, "retreat": 1, "from": "", "attacks": [a1, a2], "fx_ver": ver},
		"x_T_2": {"kind": "beast", "name": "匯入乙", "type": "fire", "hp": 140, "retreat": 1, "from": "x_T_1", "attacks": [a1, a2], "fx_ver": ver},
		"x_T_3": {"kind": "trainer", "name": "匯入博士", "effect": "journal", "fx_ver": ver},
	}


func _play(sd: int, deck: Array, actions: Array) -> Battle:
	var b := Battle.new()
	b.setup(sd, deck, CardDB.deck_by_name("starter_water"), "甲", "乙")
	for a in actions:
		if not b.apply(a):
			break
	return b


func _test_versioned_replay() -> void:
	CardDB.set_custom(_imported_defs(Battle.FX_VERSION), "user://none")
	var deck: Array = []
	for i in 5:
		deck += ["x_T_1", "x_T_1", "x_T_2", "x_T_3", "e_fire", "e_fire"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var b := Battle.new()
	b.setup(777, deck, CardDB.deck_by_name("starter_water"), "甲", "乙")
	var guard := 0
	while b.winner < 0 and guard < 3000:
		guard += 1
		if not b.apply(BattleAI.choose(b, b.actor(), 2, rng)):
			break
	check(b.winner >= 0 and b.history.size() > 10, "匯入卡對戰打完（%d 個動作）" % b.history.size())
	var again := _play(777, deck, b.history)
	check(again.state_hash() == b.state_hash(), "相同種子與動作得到相同狀態")
	var half := _play(777, deck, b.history.slice(0, b.history.size() / 2))
	var half2 := _play(777, deck, b.history.slice(0, b.history.size() / 2))
	check(half.state_hash() == half2.state_hash() and half.state_hash() != b.state_hash(), "打到一半也相同，且和打完的狀態不同")
	var other := _play(778, deck, [])
	check(other.state_hash() != _play(777, deck, []).state_hash(), "不同種子得到不同狀態")
	var save = JSON.parse_string(JSON.stringify(b.to_save()))
	check(int(save.get("fx_ver", 0)) == Battle.FX_VERSION, "匯入卡存檔記下效果版本")
	var r := Battle.from_save(save)
	check(r != null and r.state_hash() == b.state_hash(), "存檔經 JSON 重播後狀態相同")
	var missing: Dictionary = save.duplicate(true)
	missing.erase("fx_ver")
	check(Battle.from_save(missing) == null and Battle.last_error.contains("缺少效果版本"), "缺少版本時回報錯誤")
	var nulled: Dictionary = save.duplicate(true)
	nulled.fx_ver = null
	check(Battle.from_save(nulled) == null and Battle.last_error.contains("缺少效果版本"), "版本是 null 也回報錯誤")
	var newer: Dictionary = save.duplicate(true)
	newer.fx_ver = Battle.FX_VERSION + 1
	check(Battle.from_save(newer) == null and Battle.last_error.contains("只支援"), "未來版本回報錯誤")
	var bad: Dictionary = save.duplicate(true)
	bad.history = bad.history.slice(0, 3) + [{"t": "attach", "p": 0, "hand": 99, "slot": 0}]
	check(Battle.from_save(bad) == null and Battle.last_error.contains("重播失敗"), "動作不合法時回報錯誤")
	CardDB.set_custom(_imported_defs(Battle.FX_VERSION + 1), "user://none")
	check(Battle.from_save(save) == null and Battle.last_error.contains("匯入甲"), "卡片和存檔版本不同時回報錯誤")
	CardDB.set_custom({}, "user://none")
	check(Battle.from_save(save) == null and Battle.last_error.contains("不在了"), "卡片被刪掉時回報錯誤")
	check(Battle.from_save(missing) == null, "卡片被刪掉又缺版本也回報錯誤、不會當掉")


func _init() -> void:
	_test_old_replay()
	_test_versioned_replay()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var decks := ["starter_fire", "starter_water", "starter_leaf", "starter_thunder", "starter_rock", "luna", "drake"]
	var wins := {}
	var turns_total := 0
	var n := int(OS.get_environment("NGAMES")) if OS.get_environment("NGAMES") != "" else 300
	for g in n:
		var da: String = decks[g % decks.size()]
		var dbn: String = decks[(g * 3 + 1) % decks.size()]
		var b := Battle.new()
		b.setup(1000 + g, CardDB.deck_by_name(da), CardDB.deck_by_name(dbn), "A", "B")
		var steps := 0
		while b.winner < 0 and steps < 3000:
			var pi := b.actor()
			var a := BattleAI.choose(b, pi, 3 if pi == 0 else (g % 4), rng)
			if a.is_empty() or not b.apply(a):
				print("非法或空動作 game=%d %s" % [g, str(a)])
				fails += 1
				break
			steps += 1
		if b.winner < 0:
			print("沒分出勝負 game=%d turn=%d" % [g, b.turn])
			fails += 1
			continue
		var key := da if b.winner == 0 else dbn
		wins[key] = wins.get(key, 0) + 1
		turns_total += b.turn
		# 存檔重播
		var j = JSON.parse_string(JSON.stringify(b.to_save()))
		var r := Battle.from_save(j)
		if r.winner != b.winner or r.turn != b.turn or r.players[0].stars != b.players[0].stars:
			print("重播不一致 game=%d" % g)
			fails += 1
	print("勝場：", wins)
	print("平均回合：%.1f" % (float(turns_total) / n))
	print("失敗：%d" % fails)
	print("RESULT ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
