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
	CardDB.set_custom(_imported_defs(1), "user://none")
	var old_save: Dictionary = save.duplicate(true)
	old_save.fx_ver = 1
	var old_r := Battle.from_save(old_save)
	check(old_r != null and old_r.state_hash() == b.state_hash(), "舊版本存檔配舊卡仍可重播")
	CardDB.set_custom(_imported_defs(Battle.FX_VERSION), "user://none")
	check(Battle.from_save(old_save) == null and Battle.last_error.contains("匯入甲"), "卡片升級後舊存檔回報錯誤")
	CardDB.set_custom(_imported_defs(Battle.FX_VERSION + 1), "user://none")
	check(Battle.from_save(save) == null and Battle.last_error.contains("匯入甲"), "卡片和存檔版本不同時回報錯誤")
	CardDB.set_custom({}, "user://none")
	check(Battle.from_save(save) == null and Battle.last_error.contains("不在了"), "卡片被刪掉時回報錯誤")
	check(Battle.from_save(missing) == null, "卡片被刪掉又缺版本也回報錯誤、不會當掉")


## 10 屬性規則：對照表和 JSON 一致、無色替代、複合能量
func _test_attr_rules() -> void:
	var R = load("res://scripts/attr_rules.gd")
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/attributes.json"))
	check(d.attributes.size() == 10 and R.ATTRS.size() == 10, "屬性共 10 種")
	var same := true
	var mains := 0
	for a in d.attributes:
		var row: Array = R.ATTRS[a.id]
		same = same and row == [a.gameKey, a.name, a.hasBasicEnergy, a.fallback]
		for t in a.includedTypes:
			mains += 1
			same = same and R.MAIN_TYPES[t] == a.id
	check(same and mains == R.MAIN_TYPES.size(), "JSON 和 AttrRules 一致")
	check(R.MAIN_TYPES["毒"] == "Darkness" and R.MAIN_TYPES["幽靈"] == "Psychic", "毒歸惡、幽靈歸超")
	var dragon: Array = R.cost_keys(["Lightning", "Fighting", "Colorless"])
	check(dragon == ["thunder", "rock", "any"], "費用陣列保留混合屬性")
	var have := ["thunder", "rock", "fire"]
	var r: Dictionary = R.check_and_deduct_energy(have, dragon)
	check(r.ok and r.left.is_empty() and r.paid.size() == 3, "複合費用加無色：火補無色")
	check(have.size() == 3, "檢查費用不改動身上的能量")
	r = R.check_and_deduct_energy(["thunder", "thunder", "fire"], dragon)
	check(not r.ok and r.missing == ["rock"], "複合費用缺一種就不能出招")
	r = R.check_and_deduct_energy(["fire", "water"], ["fire", "fire"])
	check(not r.ok and r.missing == ["fire"], "同屬性數量不夠")
	r = R.check_and_deduct_energy(["water", "fire"], ["any", "fire"])
	check(r.ok and r.left.is_empty(), "無色寫在前面也先配指定屬性")
	r = R.check_and_deduct_energy(["fire"], ["fire", "any"])
	check(not r.ok and r.missing == ["any"], "無色沒有能量可補")
	for c in [[["fire", "rock"], ["fire", "any"]], [["fire"], ["water"]], [["leaf", "metal"], ["metal", "leaf", "any"]]]:
		check(R.check_and_deduct_energy(c[0], c[1]).ok == Battle.can_pay(c[0], c[1]), "和 Battle.can_pay 結果相同：%s" % str(c))
	var no_art := func(k): return k in CardDB.TYPES
	check(R.visual_key("Darkness", no_art) == "fire" and R.visual_key("Lightning", no_art) == "thunder", "缺美術才借舊屬性")


## 10 屬性接上對戰：匯入對應、混合費用、新能量、無相剋、遷移
func _test_attr_battle() -> void:
	check(CardImport.type_of("Darkness") == "dark" and CardImport.type_of("Colorless") == "any", "匯入保留原始屬性")
	var src := {"name": "複合", "cost": ["Lightning", "Fighting", "Colorless"], "damage": "60", "effect": ""}
	var def := CardImport.attack_def(src, "dragon")
	check(def.cost == ["thunder", "rock", "any"], "匯入保留混合費用")
	var defs := {
		"x_A_1": {"kind": "beast", "name": "龍", "type": "dragon", "hp": 100, "retreat": 1, "fx_ver": Battle.FX_VERSION, "attacks": [def]},
		"x_A_2": {"kind": "beast", "name": "惡", "type": "dark", "hp": 100, "retreat": 1, "fx_ver": Battle.FX_VERSION, "attacks": [{"name": "咬", "dmg": 20, "n_type": 1, "n_any": 0}]},
		"x_A_3": {"kind": "beast", "name": "無", "type": "any", "hp": 100, "retreat": 1, "fx_ver": Battle.FX_VERSION, "attacks": [{"name": "撞", "dmg": 20, "n_type": 1, "n_any": 0}]},
		"x_A_4": {"kind": "beast", "name": "龍二", "type": "dragon", "hp": 100, "retreat": 1, "fx_ver": Battle.FX_VERSION, "attacks": [{"name": "撞", "dmg": 20, "n_type": 2, "n_any": 0}]},
	}
	CardDB.set_custom(defs, "user://none")
	check(CardDB.BEASTS["x_A_1"].attacks[0].cost == ["thunder", "rock", "any"], "對戰資料保留混合費用")
	check(CardDB.BEASTS["x_A_2"].attacks[0].cost == ["dark"], "惡屬性要惡能量")
	check(CardDB.BEASTS["x_A_3"].attacks[0].cost == ["any"] and CardDB.BEASTS["x_A_4"].attacks[0].cost == ["any", "any"], "龍和無色沒有基本能量，改用任意能量")
	check(Battle.can_pay(["thunder", "rock", "fire"], CardDB.BEASTS["x_A_1"].attacks[0].cost), "複合費用付得起")
	check(not Battle.can_pay(["thunder", "thunder", "fire"], CardDB.BEASTS["x_A_1"].attacks[0].cost), "複合費用缺鬥付不起")
	check(CardDB.is_energy("e_dark") and CardDB.is_energy("e_psychic") and CardDB.is_energy("e_metal"), "新增三種基本能量")
	check(not CardDB.beats("dark", "fire") and CardDB.beats("fire", "leaf"), "新屬性沒有相剋、舊相剋不變")
	var deck: Array = []
	for i in 6:
		deck += ["x_A_1", "x_A_2", "x_A_3", "e_dark", "e_thunder", "e_rock"]
	var b := Battle.new()
	b.setup(321, deck, deck, "甲", "乙")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var guard := 0
	while b.winner < 0 and guard < 3000:
		guard += 1
		if not b.apply(BattleAI.choose(b, b.actor(), 2, rng)):
			break
	check(b.winner >= 0, "新屬性牌組打完（%d 個動作）" % b.history.size())
	var r := Battle.from_save(JSON.parse_string(JSON.stringify(b.to_save())))
	check(r != null and r.state_hash() == b.state_hash(), "新屬性對戰存檔重播相同")
	var db := SaveDB.new("user://test_attr")
	db.library = {"packs": [], "cards": {
		"x_B_1": {"kind": "beast", "name": "舊惡", "type": "fire", "src_type": "Darkness", "fx_ver": 1, "attacks": []},
		"x_B_2": {"kind": "trainer", "name": "舊道具", "fx_ver": 1},
		"c_1": {"kind": "beast", "name": "手做", "type": "fire", "attacks": []}}}
	check(db.old_attr_count() == 1, "遷移：算出舊卡")
	check(db.migrate_attrs() == 1 and db.library.cards.x_B_1.type == "dark" and int(db.library.cards.x_B_1.fx_ver) == Battle.FX_VERSION, "遷移：依原始屬性還原")
	check(db.library.cards.c_1.type == "fire" and db.old_attr_count() == 0, "遷移：手做卡不動、可重複執行")
	CardDB.set_custom({}, "user://none")


func _init() -> void:
	_test_attr_battle()
	_test_old_replay()
	_test_versioned_replay()
	_test_attr_rules()
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
