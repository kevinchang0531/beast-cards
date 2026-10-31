class_name SaveDB
extends RefCounted
## 玩家進度資料庫：每位玩家一個 JSON 檔，存在 user://saves/
## （Windows：%APPDATA%\Godot\app_userdata\靈獸卡牌對戰\saves\；網頁版存在瀏覽器裡）。
## 每個檔 = {
##   name 名字、avatar 頭像、coins 金幣、collection {卡片 id: 張數}、decks [{name, cards}]、active_deck、
##   stats {games, wins, losses, kos, packs, online_wins, online_games}、beaten {電腦對手 id: 勝場}、
##   history [每場對戰：日期、模式、對手、勝負、回合數、星徽]（最多 200 筆）、
##   current_match 進行中的電腦對戰（每個動作後自動存，關掉遊戲再開可以繼續），
##   created 建立時間、updated 最後存檔時間，title 稱號、bio 自我介紹 }
## 牌組 decks[i] = {name, cards, deck_size（30 或 60；舊存檔沒有這欄，讀檔時補 30）}
## 自製卡包存在 <dir>/custom/（同一台裝置的玩家共用）：cards.json = {packs: [{id, name, cards: [卡片 id]}], cards: {id: 定義}}，
## 每張卡一個 <id>.png（256×256）；上傳的頭像是 avatar_*.png。
## 定義 = {kind: beast/trainer/energy, name, type, hp, retreat, from, attacks: [{name, dmg, n_type, n_any, fx, v}], effect}

const DEFAULT_DIR := "user://saves"
const MAX_HISTORY := 200
const ART_SIZE := 256
const AVATAR_SIZE := 192
const MAX_PACK_CARDS := 40

var dir: String
var library := {"packs": [], "cards": {}}


func _init(d: String = DEFAULT_DIR) -> void:
	dir = d
	DirAccess.make_dir_recursive_absolute(custom_dir())
	load_library()


func _path(pname: String) -> String:
	return "%s/%s.json" % [dir, pname.md5_text()]


func custom_dir() -> String:
	return dir + "/custom"


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
		"decks": [{"name": CardDB.STARTER_NAME[starter_type], "cards": deck, "deck_size": CardDB.DECK_SIZE}], "active_deck": 0,
		"stats": {"games": 0, "wins": 0, "losses": 0, "kos": 0, "packs": 0, "online_games": 0, "online_wins": 0},
		"beaten": {}, "history": [], "current_match": null, "created": now, "updated": now, "title": "", "bio": "",
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
	# 舊版存檔補上新欄位，原有資料一律保留
	if not d.has("title"):
		d.title = ""
	if not d.has("bio"):
		d.bio = ""
	for deck in d.decks:
		deck.deck_size = int(deck.get("deck_size", CardDB.DECK_SIZE))
	purge_missing(d)
	return d


## 卡包被刪掉後，把這位玩家身上找不到的卡清掉；進行中的對戰用到就只能放棄
static func purge_missing(p: Dictionary) -> void:
	for deck in p.decks:
		deck.cards = deck.cards.filter(func(id): return CardDB.known(str(id)))
	for id in p.collection.keys():
		if not CardDB.known(id):
			p.collection.erase(id)
	if p.get("current_match") is Dictionary:
		for dk in p.current_match.save.decks:
			for id in dk:
				if not CardDB.known(str(id)):
					p.current_match = null
					return


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


## 把靈獸和訓練家卡都補到 60 張牌組的上限張數，回傳補了幾張
static func fill_collection(p: Dictionary) -> int:
	var added := 0
	for id in CardDB.BEASTS.keys() + CardDB.TRAINERS.keys():
		var have := int(p.collection.get(id, 0))
		var want := CardDB.max_copies(60)
		if have < want:
			added += want - have
			p.collection[id] = want
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
	for id in CardDB.BASE_BEASTS.keys() + CardDB.BASE_TRAINERS.keys():
		by_rarity[CardDB.rarity(id)].append(id)
	var out: Array = []
	for i in 3:
		out.append(by_rarity[0][rng.randi_range(0, by_rarity[0].size() - 1)])
	out.append(by_rarity[1][rng.randi_range(0, by_rarity[1].size() - 1)])
	var r := 2 if rng.randf() < 0.35 else 1
	out.append(by_rarity[r][rng.randi_range(0, by_rarity[r].size() - 1)])
	return out


# ---------- 自製卡包 ----------

func load_library() -> void:
	var path := custom_dir() + "/cards.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	library = d if d is Dictionary and d.has("packs") else {"packs": [], "cards": {}}
	CardDB.set_custom(library.cards, custom_dir())


func save_library() -> void:
	var f := FileAccess.open(custom_dir() + "/cards.json", FileAccess.WRITE)
	if f == null:
		push_error("卡包存檔失敗")
		return
	f.store_string(JSON.stringify(library, "  "))
	f.close()
	CardDB.set_custom(library.cards, custom_dir())


## 裁成正中央的正方形再縮放，和內建卡圖一樣
static func square_image(src: Image, side: int) -> Image:
	var img: Image = src.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var m := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - m) / 2, (img.get_height() - m) / 2, m, m))
	img.resize(side, side, Image.INTERPOLATE_LANCZOS)
	return img


static func default_card(i: int) -> Dictionary:
	return {"kind": "beast", "name": "自製靈獸%d" % i, "type": "fire", "hp": 60, "retreat": 1, "from": "", "effect": "potion",
		"attacks": [{"name": "撞擊", "dmg": 20, "n_type": 1, "n_any": 0, "fx": "", "v": 0},
			{"name": "", "dmg": 40, "n_type": 1, "n_any": 1, "fx": "", "v": 0}]}


## 每張圖變成一張預設自製卡，回傳新卡包；defs 可以指定每張卡的定義
func add_pack(pname: String, images: Array, defs: Array = []) -> Dictionary:
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var pack := {"id": "p%d" % stamp, "name": pname, "cards": []}
	for i in mini(images.size(), MAX_PACK_CARDS):
		var id := "c%d_%d" % [stamp, i]
		if square_image(images[i], ART_SIZE).save_png("%s/%s.png" % [custom_dir(), id]) != OK:
			continue
		library.cards[id] = defs[i] if i < defs.size() else default_card(i + 1)
		pack.cards.append(id)
	library.packs.append(pack)
	save_library()
	return pack


func delete_pack(pack: Dictionary) -> void:
	for id in pack.cards:
		library.cards.erase(id)
		DirAccess.remove_absolute("%s/%s.png" % [custom_dir(), id])
	library.packs.erase(pack)
	save_library()


## 批次匯入：一個系列一個卡包，id 由系列代號決定，重新匯入同系列會覆蓋原卡，牌組和收藏不受影響
func set_pack(code: String, pname: String) -> Dictionary:
	var id := "set_" + code
	for pack in library.packs:
		if pack.id == id:
			return pack
	var pack := {"id": id, "name": pname, "cards": []}
	library.packs.append(pack)
	return pack


func add_set_card(pack: Dictionary, id: String, def: Dictionary, img: Image) -> bool:
	if square_image(img, ART_SIZE).save_png("%s/%s.png" % [custom_dir(), id]) != OK:
		return false
	library.cards[id] = def
	if not pack.cards.has(id):
		pack.cards.append(id)
	return true


## 把 from_name 接到自製卡庫裡同名的卡（跨系列也算）；找不到進化來源就當基礎靈獸，回傳接上幾張
func link_evolutions() -> int:
	var by_name := {}
	for id in library.cards:
		if str(library.cards[id].get("kind")) == "beast" and not by_name.has(library.cards[id].name):
			by_name[library.cards[id].name] = id
	var linked := 0
	for id in library.cards:
		var c: Dictionary = library.cards[id]
		if str(c.get("from_name", "")) != "":
			c.from = by_name.get(c.from_name, "")
			linked += 1 if c.from != "" else 0
	return linked


## 匯入的人直接拿到 3 張（能量卡和內建能量一樣無限量）
static func grant_pack(p: Dictionary, pack: Dictionary) -> void:
	for id in pack.cards:
		p.collection[id] = 99 if CardDB.is_energy(id) else maxi(int(p.collection.get(id, 0)), CardDB.MAX_COPIES)


## 開自製卡包：從這包隨機抽 5 張
static func open_custom_pack(pack: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in 5:
		out.append(pack.cards[rng.randi_range(0, pack.cards.size() - 1)])
	return out


## 存上傳的頭像，回傳可以放進 profile.avatar 的路徑
func save_avatar(src: Image) -> String:
	var path := "%s/avatar_%d.png" % [custom_dir(), int(Time.get_unix_time_from_system() * 1000.0)]
	return path if square_image(src, AVATAR_SIZE).save_png(path) == OK else ""
