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
		full = full and int(main.profile.collection.get(id, 0)) >= CardDB.MAX_COPIES
	check(full, "全部卡片補到 %d 張" % CardDB.MAX_COPIES)
	check(SaveDB.fill_collection(main.profile) == 0, "再補一次不會多加")
	reloaded = main.db.load_profile("測試小明")
	check(int(reloaded.collection.get(CardDB.BEASTS.keys()[0], 0)) == CardDB.MAX_COPIES, "補齊有存檔")
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


func _find_ui() -> BattleUI:
	for n in main.screen.get_children():
		if n is BattleUI:
			return n
	return null


func _find_button(root: Node, prefix: String) -> Button:
	for c in root.get_children():
		if c is Button and c.text.begins_with(prefix):
			return c
		var r := _find_button(c, prefix)
		if r:
			return r
	return null
