extends Node
## 介面自動測試（要用視窗模式跑，才能截圖）：
## 建立測試玩家 → 每個畫面截圖 → 買卡包 → 自動組牌 → 透過真正的對戰畫面打完一場電腦對戰（我方也由 AI 代打）
## → 檢查戰績與金幣有存檔 → 再開一場打幾步後暫停離開、重新讀檔繼續，檢查進度一致。
## 截圖存到 art_src/_shots/。用法：godot --path . res://tests/selftest.tscn

const SHOTS := "res://art_src/_shots"
var main: Control
var fails := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 42
	Engine.time_scale = 3.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var test_dir := "user://test_saves"
	var da := DirAccess.open("user://")
	if da and da.dir_exists("test_saves"):
		for f in DirAccess.get_files_at(test_dir):
			DirAccess.remove_absolute(test_dir + "/" + f)
		for f in DirAccess.get_files_at(test_dir + "/custom"):
			DirAccess.remove_absolute(test_dir + "/custom/" + f)
	main = load("res://scenes/main.tscn").instantiate()
	main.db = SaveDB.new(test_dir)
	add_child(main)
	await _run()
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1


func shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, name]))


func _run() -> void:
	await shot("01_title_empty")
	main.show_new_profile()
	await shot("02_new_profile")
	main.profile = main.db.new_profile("測試小明", "av_girl", "water")
	check(main.db.exists("測試小明"), "建立玩家存檔")
	main.show_title()
	await shot("03_title_profile")
	main.load_and_menu("測試小明")
	check(main.profile.coins == 200, "初始金幣 200")
	check(CardDB.validate_deck(main._deck()) == "", "起始牌組合法")
	await shot("04_menu")
	main.show_ai_select()
	await shot("05_ai_select")
	main.show_shop()
	await get_tree().process_frame
	var buy := _find_button(main.screen, "購買")
	check(buy != null, "找到購買按鈕")
	buy.pressed.emit()
	await get_tree().create_timer(3.0).timeout
	await shot("06_shop_open")
	check(main.profile.coins == 100 and main.profile.stats.packs == 1, "買卡包扣金幣、記錄開包數")
	var reloaded: Dictionary = main.db.load_profile("測試小明")
	check(reloaded.coins == 100, "開包後有存檔")
	main.show_deck_editor()
	await shot("07_deck_editor")
	var auto: Array = main._auto_deck()
	check(CardDB.validate_deck(auto) == "", "自動組牌合法：" + CardDB.validate_deck(auto))
	main.show_records()
	await shot("08_records")
	main.show_rules()
	await shot("09_rules")
	main.show_lobby()
	await shot("10_lobby")

	# --- 完整打一場 ---
	main.show_menu()
	main.start_ai_match(0)
	await get_tree().process_frame
	var ui: BattleUI = _find_ui()
	check(ui != null, "進入對戰畫面")
	check(main.profile.current_match is Dictionary, "對戰開始就存進行中的對局")
	await shot("11_battle_start")
	var shots_taken := 0
	var guard := 0
	while is_instance_valid(ui) and ui.b.winner < 0 and guard < 4000:
		guard += 1
		await get_tree().process_frame
		if ui._can_input():
			var a := BattleAI.choose(ui.b, ui.me, 2, rng)
			ui._do(a)
			if ui.b.turn >= 5 and shots_taken == 0:
				shots_taken = 1
				await get_tree().create_timer(0.8).timeout
				await shot("12_battle_mid")
	check(is_instance_valid(ui) and ui.b.winner >= 0, "對戰分出勝負（第 %d 回合）" % (ui.b.turn if is_instance_valid(ui) else -1))
	await get_tree().create_timer(2.5).timeout
	await shot("13_battle_result")
	var won: bool = ui.b.winner == 0
	var coins_before: int = main.profile.coins
	ui._finish({})
	await get_tree().process_frame
	check(main.profile.current_match == null, "結束後清掉進行中的對局")
	check(main.profile.history.size() == 1 and main.profile.stats.games == 1, "戰績記錄 1 場")
	check(main.profile.coins == coins_before + (160 if won else 20), "金幣獎勵正確（%s）" % ("勝" if won else "敗"))
	reloaded = main.db.load_profile("測試小明")
	check(reloaded.history.size() == 1, "戰績有寫進存檔")

	# --- 暫停與繼續 ---
	main.start_ai_match(0)
	await get_tree().process_frame
	ui = _find_ui()
	var steps := 0
	while steps < 6 and ui.b.winner < 0:
		await get_tree().process_frame
		if ui._can_input():
			ui._do(BattleAI.choose(ui.b, ui.me, 2, rng))
			steps += 1
	await get_tree().create_timer(1.0).timeout
	while not ui._can_input() and ui.b.winner < 0:
		await get_tree().process_frame
	var hist: int = ui.b.history.size()
	var turn: int = ui.b.turn
	ui._finish({"paused": true})
	await get_tree().process_frame
	reloaded = main.db.load_profile("測試小明")
	check(reloaded.current_match is Dictionary and reloaded.current_match.save.history.size() == hist, "暫停時進度有存檔（%d 個動作）" % hist)
	main.profile = reloaded
	main.show_menu()
	await shot("14_menu_resume")
	main.resume_match()
	await get_tree().process_frame
	ui = _find_ui()
	check(ui.b.history.size() == hist and ui.b.turn == turn, "讀檔繼續對局，回合與動作數一致")
	await shot("15_battle_resumed")

	# --- 隱藏選單 ---
	main.show_menu()
	await get_tree().process_frame
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	tap.button_index = MOUSE_BUTTON_LEFT
	for i in 4:
		main._on_avatar_tap(tap)
	check(_find_button(main.screen, "補齊") == null, "連點 4 下不會開隱藏選單")
	main._on_avatar_tap(tap)
	var fill := _find_button(main.screen, "補齊")
	check(fill != null, "連點 5 下開隱藏選單")
	await shot("16_secret")
	fill.pressed.emit()
	await get_tree().process_frame
	var full := true
	for id in CardDB.BEASTS.keys() + CardDB.TRAINERS.keys():
		full = full and int(main.profile.collection.get(id, 0)) >= CardDB.max_copies(60)
	check(full, "全部卡片補到 %d 張" % CardDB.max_copies(60))
	check(SaveDB.fill_collection(main.profile) == 0, "再補一次不會多加")
	reloaded = main.db.load_profile("測試小明")
	check(int(reloaded.collection.get(CardDB.BEASTS.keys()[0], 0)) == CardDB.max_copies(60), "補齊有存檔")
	main.db.new_profile("別人", "av_boy", "fire")
	check(not main.rename_player("別人"), "不能改成別人的名字")
	check(not main.rename_player("  "), "不能改成空白")
	check(main.rename_player("新名字"), "改名成功")
	check(main.db.exists("新名字") and not main.db.exists("測試小明"), "存檔跟著改名，舊檔移除")
	reloaded = main.db.load_profile("新名字")
	check(reloaded.name == "新名字" and reloaded.current_match.save.names[0] == "新名字", "進行中的對戰也換成新名字")
	check(int(reloaded.stats.games) == int(main.profile.stats.games), "改名後戰績還在")
	main.show_menu()
	main.resume_match()
	await get_tree().process_frame
	check(_find_ui().b.names[0] == "新名字", "改名後能繼續對戰")
	await _test_new_features()
	await _test_batch_import()


## 批次匯入：用假資料，真實卡片資料不放進 repo
func _test_batch_import() -> void:
	var cards := [
		{"id": "1", "name": "測試蟲", "supertype": "Pokemon", "subtype": "Basic", "setCode": "T1", "imageUrl": "image/a.png", "hp": 60,
			"pokemonType": "Grass", "retreatCost": ["Colorless"], "evolvesFrom": null, "attacks": [
			{"name": "咬", "cost": ["Grass", "Colorless"], "damage": "20", "effect": "將對手的戰鬥寶可夢【中毒】。"}]},
		{"id": "2", "name": "測試蟲", "supertype": "Pokemon", "subtype": "Basic", "setCode": "T1", "imageUrl": "image/b.png", "hp": 60,
			"pokemonType": "Grass", "attacks": [{"name": "咬", "cost": ["Grass"], "damage": "10", "effect": ""}]},
		{"id": "3", "name": "測試蛾", "supertype": "Pokemon", "subtype": "ex", "setCode": "T1", "imageUrl": "image/c.png", "hp": 330,
			"pokemonType": "Darkness", "evolvesFrom": "測試蟲", "retreatCost": null, "attacks": [
			{"name": "連擊", "cost": ["Darkness", "Fire", "Colorless", "Colorless", "Colorless"], "damage": "30×", "effect": "擲3次硬幣，造成正面出現的次數×30點傷害。"},
			{"name": "能量波", "cost": ["Colorless"], "damage": "20+", "effect": "增加這隻寶可夢身上附加的【火】能量的數量×20點傷害。"},
			{"name": "第三招", "cost": ["Colorless"], "damage": "10", "effect": ""}]},
		{"id": "4", "name": "孤兒", "supertype": "Pokemon", "subtype": "Stage1", "setCode": "T1", "imageUrl": "image/d.png", "hp": 90,
			"pokemonType": "Metal", "evolvesFrom": "不存在", "attacks": []},
		{"id": "5", "name": "測試博士", "supertype": "Trainer", "subtype": "Supporter", "setCode": "T1", "imageUrl": "image/e.png",
			"rulesText": "從牌庫抽出3張卡。"},
		{"id": "6", "name": "沒有圖", "supertype": "Trainer", "subtype": "Item", "setCode": "T1", "imageUrl": "image/x.png", "rulesText": ""},
	]
	var img := Image.create(120, 70, false, Image.FORMAT_RGBA8)
	var files := {"jsons": {"T1_cards.json": JSON.stringify(cards), "bad.json": "{}"}, "images": {}}
	for n in ["a", "b", "c", "d", "e"]:
		files.images[n + ".png"] = img
	var packs: Array = await main.import_batch(files)
	check(packs.size() == 1 and packs[0].cards.size() == 5, "批次匯入：一個 JSON 一個卡包，壞檔和沒圖的略過")
	check(FileAccess.file_exists(main.db.custom_dir() + "/x_T1_3.png"), "批次匯入：卡圖存好")
	var moth: Dictionary = CardDB.BEASTS["x_T1_3"]
	check(moth.type == "fire" and moth.stage == 1 and moth.hp == 300 and moth.retreat == 0, "批次匯入：屬性併入、進化接上、HP 上限")
	check(moth.attacks.size() == 2 and moth.attacks[0].cost.size() == CardDB.MAX_COST, "批次匯入：最多兩招、費用上限 4")
	check(moth.attacks[0].fx == "flip_plus" and moth.attacks[0].v == 60 and moth.attacks[1].fx == "energy_plus", "批次匯入：招式效果對應")
	check(CardDB.BEASTS["x_T1_1"].type == "leaf" and CardDB.BEASTS["x_T1_1"].attacks[0].fx == "burn", "批次匯入：草屬性與中毒變灼傷")
	check(CardDB.BEASTS["x_T1_4"].stage == 0 and CardDB.BEASTS["x_T1_4"].type == "rock", "批次匯入：找不到進化來源就當基礎")
	check(CardDB.effect_of("x_T1_5") == "journal", "批次匯入：訓練家對應內建效果")
	check(CardDB.can_evolve("x_T1_2", "x_T1_3"), "批次匯入：同名不同版本也能進化")
	main.show_pack_editor(packs[0], "x_T1_3")
	await shot("24_batch_editor")
	check(main.profile.collection.get("x_T1_1", 0) == CardDB.MAX_COPIES, "批次匯入：匯入者拿到卡")
	var again: Array = await main.import_batch(files)
	check(again[0].cards.size() == 5 and main.db.library.packs.filter(func(x): return x.id == "set_T1").size() == 1, "批次匯入：同系列重新匯入不會重複")
	var deck: Array = []
	for i in 20:
		deck.append(["x_T1_1", "x_T1_2", "x_T1_3", "x_T1_4"][i % 4])
	for i in 10:
		deck.append("e_leaf")
	var bt := Battle.new()
	bt.setup(5, deck, CardDB.starter("fire"), "甲", "乙")
	var guard := 0
	while bt.winner < 0 and guard < 3000:
		guard += 1
		var acts: Array = bt.legal_actions(bt.actor())
		if acts.is_empty() or not bt.apply(acts[rng.randi_range(0, acts.size() - 1)]):
			break
	check(bt.winner >= 0, "批次匯入：匯入卡能打完一場")
	main.delete_pack(again[0])
	check(not CardDB.known("x_T1_1"), "批次匯入：刪除卡包")


## 玩家資料、30／60 張牌組、匯入卡包、舊存檔相容
func _test_new_features() -> void:
	# --- 舊版存檔：沒有 title、bio、deck_size ---
	var old := {"name": "舊存檔", "avatar": "av_kid", "coins": 777, "collection": {"embertail": 2, "e_fire": 99},
		"decks": [{"name": "舊牌組", "cards": CardDB.starter("fire")}], "active_deck": 0,
		"stats": {"games": 9, "wins": 5, "losses": 4, "kos": 12, "packs": 3, "online_games": 0, "online_wins": 0},
		"beaten": {"mia": 2}, "history": [{"date": "2026-10-30", "mode": "ai", "opp": "米亞", "won": true, "turns": 9, "stars": 3}],
		"current_match": null, "created": "2026-10-30", "updated": "2026-10-30"}
	var f := FileAccess.open(main.db._path("舊存檔"), FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	main.load_and_menu("舊存檔")
	var p: Dictionary = main.profile
	check(p.coins == 777 and p.stats.wins == 5 and p.beaten.mia == 2 and p.history.size() == 1, "舊存檔資料全部保留")
	check(p.decks[0].deck_size == 30 and p.decks[0].cards.size() == 30 and p.title == "", "舊存檔補上新欄位，牌組還是 30 張")
	await shot("17_menu_new")

	# --- 玩家資料 ---
	main.show_profile()
	await shot("18_profile")
	var img := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var av: String = main.db.save_avatar(img)
	check(av != "" and CardView.tex(av) != null and CardView.tex(av).get_width() == SaveDB.AVATAR_SIZE, "上傳頭像裁成正方形")
	check(not main.save_profile_info("別人", "x", "y", av), "玩家資料不能改成別人的名字")
	check(main.profile.title == "", "名字失敗時其他欄位不變")
	check(main.save_profile_info("舊存檔", "冠軍", "你好", av), "儲存玩家資料")
	var r: Dictionary = main.db.load_profile("舊存檔")
	check(r.title == "冠軍" and r.bio == "你好" and r.avatar == av, "玩家資料有存檔")
	main.show_menu()
	await shot("19_menu_avatar")

	# --- 60 張牌組 ---
	SaveDB.fill_collection(main.profile)
	var d60: Array = main._auto_deck(60)
	check(d60.size() == 60 and CardDB.validate_deck(d60, 60) == "", "自動組 60 張合法：" + CardDB.validate_deck(d60, 60))
	check(CardDB.validate_deck(d60, 30) != "", "60 張不能當 30 張用")
	main.show_deck_editor()
	await get_tree().process_frame
	_find_button(main.screen, "60 張").pressed.emit()
	await get_tree().process_frame
	check(main.edit_size == 60, "牌組編輯切到 60 張")
	main.edit_deck = d60.duplicate()
	_find_button(main.screen, "儲存並使用").pressed.emit()
	r = main.db.load_profile("舊存檔")
	check(r.decks[0].deck_size == 60 and r.decks[0].cards.size() == 60, "60 張牌組有存檔")
	main.start_ai_match(0)
	await get_tree().process_frame
	var ui := _find_ui()
	check(ui != null and ui.b.decks[0].size() == 60 and ui.b.decks[1].size() == 60, "60 張對戰：電腦牌組也是 60 張")
	check(ui.b.players[0].deck.size() + ui.b.players[0].hand.size() >= 52, "60 張對戰發牌正常")
	await shot("20_battle_60")
	ui._finish({"paused": true})
	await get_tree().process_frame

	# --- 牌組編輯：滑過放大、點了才加入 ---
	main.show_deck_editor()
	await get_tree().process_frame
	main.edit_deck = []
	main._draw_editor_lists(main.screen)
	await get_tree().process_frame
	var cv := _find_card(main.screen.get_node("coll"))
	cv.hovered.emit(cv)
	check(main.preview.visible and main.preview.id == cv.id and main.edit_deck.is_empty(), "滑過卡片會放大、不會加入")
	await shot("21_deck_preview")
	cv.unhovered.emit(cv)
	check(not main.preview.visible, "移開就關掉放大")
	cv.pressed.emit(cv)
	check(main.edit_deck == [cv.id], "點一下才加入")

	# --- 匯入卡包 ---
	main.show_import()
	await shot("22_import_empty")
	var pack: Dictionary = main.import_example()
	await shot("23_pack_edit")
	var ids: Array = pack.cards
	check(ids.size() == 5 and CardDB.is_beast(ids[0]) and CardDB.is_trainer(ids[3]) and CardDB.is_energy(ids[4]), "範例卡包有靈獸、訓練家、能量")
	check(CardDB.BEASTS[ids[1]].stage == 1 and CardDB.BEASTS[ids[1]].from == ids[0], "自製進化線")
	check(CardView.tex(CardDB.art_path(ids[0])) != null, "自製卡圖讀得到")
	check(int(main.profile.collection[ids[0]]) == 3, "匯入者拿到 3 張")
	main.edit_card = ids[2]
	main.set_card("hp", 200)
	main.set_card("type", "thunder")
	main.set_card("attacks", [{"name": "雷擊", "dmg": 70, "n_type": 2, "n_any": 1, "fx": "para_flip", "v": 0}, {"name": "", "dmg": 0, "n_type": 0, "n_any": 0, "fx": "", "v": 0}])
	var bd: Dictionary = CardDB.BEASTS[ids[2]]
	check(bd.hp == 200 and bd.type == "thunder" and bd.attacks.size() == 1 and bd.attacks[0].cost == ["thunder", "thunder", "any"], "設定卡片屬性")
	main.show_pack_editor(pack, ids[3])
	await shot("24_pack_trainer")
	main.show_pack_editor(pack, ids[4])
	await shot("25_pack_energy")
	main.show_pack_editor(pack, ids[1])
	await get_tree().process_frame
	main.db.load_library()
	check(CardDB.BEASTS[ids[2]].hp == 200, "卡片設定有寫進檔案，重新讀檔還在")
	check(CardDB.BEASTS[ids[1]].attacks[1].fx == "burn" and typeof(CardDB.BEASTS[ids[1]].hp) == TYPE_INT, "讀檔後數字是整數")
	main.show_shop()
	await shot("26_shop_packs")
	check(SaveDB.open_custom_pack(pack, rng).size() == 5, "自製卡包抽 5 張")
	var std := true
	for i in 30:
		for id in SaveDB.open_pack(rng):
			std = std and not CardDB.is_custom(id)
	check(std, "標準卡包不會抽到自製卡")

	# --- 自製卡實戰：雙方 AI 打完一場 ---
	var deck: Array = []
	for id in [ids[0], ids[1], ids[2], ids[3]]:
		for i in 3:
			deck.append(id)
	for i in 6:
		deck.append(ids[4])
		deck.append("e_thunder")
	for i in 3:
		deck += ["embertail", "e_fire"]
	check(CardDB.validate_deck(deck) == "", "自製牌組合法：" + CardDB.validate_deck(deck))
	var games := 0
	for g in 20:
		var b := Battle.new()
		b.setup(1000 + g, deck, CardDB.starter("rock"), "我", "電腦")
		var guard := 0
		while b.winner < 0 and guard < 3000:
			guard += 1
			var who := b.actor()
			var a := BattleAI.choose(b, who, 2, rng)
			if a.is_empty() or not b.apply(a):
				break
		games += 1 if b.winner >= 0 else 0
	check(games == 20, "自製卡對戰 20 場都打完（%d）" % games)

	main.profile.decks[0].cards = deck
	main.profile.decks[0].deck_size = 30
	check(main._online_error() != "", "線上對戰擋自製卡")
	main.start_ai_match(0)
	await get_tree().process_frame
	await shot("27_battle_custom")
	check(main.profile.current_match is Dictionary, "自製牌組可以開打")
	# --- 二階進化 ---
	var chain := ["embertail", "blazecrown", "solarfox"]
	check(CardDB.BEASTS.solarfox.stage == 2 and CardDB.BEASTS.solarfox.from == "blazecrown", "內建二階靈獸")
	var dk2: Array = []
	for i in 3:
		dk2 += chain
	for i in 21:
		dk2.append("e_fire")
	var bt := Battle.new()
	bt.setup(7, dk2, CardDB.starter("rock"), "我", "電腦")
	var pl: Dictionary = bt.players[0]
	bt.turn = 5
	bt.current = 0
	pl.hand = []
	for id in chain:
		pl.hand.append(dk2.find(id))
	pl.active = bt._new_beast(dk2.find("embertail") + 3)
	pl.active.turn_played = 1
	pl.hand.erase(dk2.find("embertail"))
	var evolves := func() -> Array:
		return bt.legal_actions(0).filter(func(a): return a.t == "evolve")
	check(evolves.call().size() == 1 and bt.card_id(pl.hand[evolves.call()[0].hand]) == "blazecrown", "基礎只能進化成一階，不能跳到二階")
	check(bt.apply(evolves.call()[0]) and bt.beast_data(pl.active).stage == 1, "進化成一階")
	check(evolves.call().is_empty(), "剛進化的那回合不能再進化")
	bt.turn = 7
	check(evolves.call().size() == 1 and bt.apply(evolves.call()[0]) and bt.beast_data(pl.active).stage == 2, "下個回合進化成二階")
	check(pl.active.stack.size() == 2, "二階疊了兩張進化前的卡")
	var reached := 0
	var replay_ok := true
	for g in 30:
		var ab := Battle.new()
		ab.setup(500 + g, dk2, CardDB.deck_by_name("drake"), "我", "電腦")
		var guard2 := 0
		while ab.winner < 0 and guard2 < 3000:
			guard2 += 1
			var a2 := BattleAI.choose(ab, ab.actor(), 3, rng)
			if a2.is_empty() or not ab.apply(a2):
				break
			if ab.players[0].active != null and ab.beast_data(ab.players[0].active).stage == 2:
				reached += 1
				var rp := Battle.from_save(ab.to_save())
				replay_ok = replay_ok and rp.beast_data(rp.players[0].active).stage == 2
				break
	check(reached > 0, "電腦會打出二階進化（30 場有 %d 場）" % reached)
	check(replay_ok, "二階進化存檔重播後狀態一致")
	var ko := Battle.new()
	ko.setup(9, dk2, CardDB.starter("rock"), "我", "電腦")
	var ko_p: Dictionary = ko.players[0]
	ko_p.active = ko._new_beast(2)
	ko_p.active.stack = [0, 1]
	ko_p.active.dmg = 999
	ko_p.discard = []
	ko_p.bench = [ko._new_beast(3)]
	ko._check_kos(1)
	check(ko_p.discard.size() >= 3 and ko_p.discard.has(0) and ko_p.discard.has(1) and ko_p.discard.has(2), "二階被擊倒時三張卡都進棄牌區")
	# 自製卡：可以接在一階後面；繞圈、三階都會變回基礎
	var saved_cards: Dictionary = main.db.library.cards.duplicate(true)
	var cc := {"x2": {"kind": "beast", "name": "接二階", "type": "fire", "hp": 100, "retreat": 1, "from": "blazecrown", "attacks": []},
		"x3": {"kind": "beast", "name": "三階", "type": "fire", "hp": 100, "retreat": 1, "from": "solarfox", "attacks": []},
		"a1": {"kind": "beast", "name": "甲", "type": "fire", "hp": 100, "retreat": 1, "from": "a2", "attacks": []},
		"a2": {"kind": "beast", "name": "乙", "type": "fire", "hp": 100, "retreat": 1, "from": "a1", "attacks": []},
		"m1": {"kind": "beast", "name": "一階", "type": "fire", "hp": 100, "retreat": 1, "from": "embertail", "attacks": []},
		"m2": {"kind": "beast", "name": "二階", "type": "fire", "hp": 100, "retreat": 1, "from": "m1", "attacks": []}}
	CardDB.set_custom(cc, main.db.custom_dir())
	check(CardDB.BEASTS.x2.stage == 2 and CardDB.BEASTS.m2.stage == 2 and CardDB.BEASTS.m1.stage == 1, "自製卡二階進化")
	check(CardDB.BEASTS.x3.stage == 0 and CardDB.BEASTS.x3.from == "", "超過二階變回基礎")
	check(CardDB.BEASTS.a1.stage + CardDB.BEASTS.a2.stage <= 1, "進化繞圈不會當掉")
	CardDB.set_custom(saved_cards, main.db.custom_dir())
	# --- 刪除卡包 ---
	main.delete_pack(pack)
	check(not CardDB.known(ids[0]) and main.profile.decks[0].cards.size() == 30 - 18, "刪除卡包後牌組移除自製卡")
	check(main.profile.current_match == null, "用到被刪卡片的對戰會放棄、不會當掉")
	check(not main.profile.collection.has(ids[0]), "收藏也清掉")
	main.show_menu()
	main.show_deck_editor()
	await shot("28_deck_after_delete")


func _find_ui() -> BattleUI:
	for n in main.screen.get_children():
		if n is BattleUI:
			return n
	return null


func _find_card(root: Node) -> CardView:
	for c in root.get_children():
		if c is CardView:
			return c
		var r := _find_card(c)
		if r:
			return r
	return null


func _find_button(root: Node, prefix: String) -> Button:
	for c in root.get_children():
		if c is Button and c.text.begins_with(prefix):
			return c
		var r := _find_button(c, prefix)
		if r:
			return r
	return null
