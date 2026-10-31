extends SceneTree
## 引擎＋AI 快速測試：AI 對 AI 打 300 場，檢查不會卡住、都分出勝負、存檔重播結果一致。
## 用法：godot --headless --path . --script res://tests/engine_test.gd

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var decks := ["starter_fire", "starter_water", "starter_leaf", "starter_thunder", "starter_rock", "luna", "drake"]
	var wins := {}
	var turns_total := 0
	var fails := 0
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
