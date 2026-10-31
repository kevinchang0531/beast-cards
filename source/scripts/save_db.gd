class_name SaveDB
extends RefCounted
## 玩家進度資料庫：每位玩家一個 JSON 檔，存在 user://saves/
## （Windows：%APPDATA%\Godot\app_userdata\靈獸卡牌對戰\saves\；網頁版存在瀏覽器裡）。
## 每個檔 = {
##   name 名字、avatar 頭像、coins 金幣、collection {卡片 id: 張數}、decks [{name, cards}]、active_deck、
##   stats {games, wins, losses, kos, packs, online_wins, online_games}、beaten {電腦對手 id: 勝場}、
##   history [每場對戰：日期、模式、對手、勝負、回合數、星徽]（最多 200 筆）、
##   current_match 進行中的電腦對戰（每個動作後自動存，關掉遊戲再開可以繼續），
##   created 建立時間、updated 最後存檔時間 }

const DEFAULT_DIR := "user://saves"
const MAX_HISTORY := 200

var dir: String


func _init(d: String = DEFAULT_DIR) -> void:
	dir = d
	DirAccess.make_dir_recursive_absolute(dir)


func _path(pname: String) -> String:
	return "%s/%s.json" % [dir, pname.md5_text()]


func list_profiles() -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, f]))
			if d is Dictionary and d.has("name"):
				out.append(d)
	out.sort_custom(func(a, b): return str(a.get("updated", "")) > str(b.get("updated", "")))
	return out


func exists(pname: String) -> bool:
	return FileAccess.file_exists(_path(pname))


func new_profile(pname: String, avatar: String, starter_type: String) -> Dictionary:
	var deck := CardDB.starter(starter_type)
	var coll := {}
	for id in deck:
		coll[id] = coll.get(id, 0) + 1
	# 能量卡無限量供應
	for e in CardDB.ENERGY:
		coll[e] = 99
	var now := Time.get_datetime_string_from_system(false, true)
	var p := {
		"name": pname, "avatar": avatar, "coins": 200, "collection": coll,
		"decks": [{"name": CardDB.STARTER_NAME[starter_type], "cards": deck}], "active_deck": 0,
		"stats": {"games": 0, "wins": 0, "losses": 0, "kos": 0, "packs": 0, "online_games": 0, "online_wins": 0},
		"beaten": {}, "history": [], "current_match": null, "created": now, "updated": now,
	}
	save(p)
	return p


func load_profile(pname: String) -> Dictionary:
	var p := _path(pname)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (d is Dictionary):
		return {}
	# JSON 讀回來數字都是 float，轉回 int
	d.coins = int(d.get("coins", 0))
	d.active_deck = int(d.get("active_deck", 0))
	var coll := {}
	for k in d.get("collection", {}):
		coll[k] = int(d.collection[k])
	d.collection = coll
	for k in d.get("stats", {}):
		d.stats[k] = int(d.stats[k])
	return d


func save(p: Dictionary) -> bool:
	p.updated = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(_path(p.name), FileAccess.WRITE)
	if f == null:
		push_error("存檔失敗：%s" % _path(p.name))
		return false
	f.store_string(JSON.stringify(p, "  "))
	f.close()
	return true


func delete_profile(pname: String) -> void:
	DirAccess.remove_absolute(_path(pname))


## 改名字：存檔檔名由名字決定，所以先存新檔再刪舊檔
func rename_profile(p: Dictionary, new_name: String) -> void:
	var old: String = p.name
	p.name = new_name
	if p.get("current_match") is Dictionary:
		p.current_match.save.names[0] = new_name
	if save(p):
		delete_profile(old)


## 把靈獸和訓練家卡都補到牌組上限張數，回傳補了幾張
static func fill_collection(p: Dictionary) -> int:
	var added := 0
	for id in CardDB.BEASTS.keys() + CardDB.TRAINERS.keys():
		var have := int(p.collection.get(id, 0))
		if have < CardDB.MAX_COPIES:
			added += CardDB.MAX_COPIES - have
			p.collection[id] = CardDB.MAX_COPIES
	return added


## 記錄一場對戰結果並存檔
static func add_result(p: Dictionary, mode: String, opp: String, won: bool, turns: int, stars: int, kos: int) -> void:
	var s: Dictionary = p.stats
	s.games += 1
	s.kos += kos
	if won:
		s.wins += 1
	else:
		s.losses += 1
	if mode == "online":
		s.online_games += 1
		if won:
			s.online_wins += 1
	p.history.push_front({"date": Time.get_datetime_string_from_system(false, true), "mode": mode, "opp": opp,
		"won": won, "turns": turns, "stars": stars})
	if p.history.size() > MAX_HISTORY:
		p.history.resize(MAX_HISTORY)


## 開卡包：5 張，最後一張至少不普通，有 1/4 機會是稀有進化靈獸
static func open_pack(rng: RandomNumberGenerator) -> Array:
	var by_rarity := [[], [], []]
	for id in CardDB.BEASTS.keys() + CardDB.TRAINERS.keys():
		by_rarity[CardDB.rarity(id)].append(id)
	var out: Array = []
	for i in 3:
		out.append(by_rarity[0][rng.randi_range(0, by_rarity[0].size() - 1)])
	out.append(by_rarity[1][rng.randi_range(0, by_rarity[1].size() - 1)])
	var r := 2 if rng.randf() < 0.35 else 1
	out.append(by_rarity[r][rng.randi_range(0, by_rarity[r].size() - 1)])
	return out
