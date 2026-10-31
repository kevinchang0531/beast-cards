class_name CardDB
extends RefCounted
## 全部卡片資料：20 種靈獸、5 種能量、9 種訓練家卡，以及起始牌組與電腦對手牌組。
## 屬性相剋（箭頭左邊打右邊兩倍傷害）：火 → 草 → 岩 → 雷 → 水 → 火

const TYPES := ["fire", "water", "leaf", "thunder", "rock"]
const TYPE_NAME := {"fire": "火", "water": "水", "leaf": "草", "thunder": "雷", "rock": "岩", "any": "無"}
const TYPE_COLOR := {
	"fire": Color("e8553a"), "water": Color("3a8ee8"), "leaf": Color("4cb84a"),
	"thunder": Color("e8c22e"), "rock": Color("a0764a"), "any": Color("c8c8c8"),
}
## 剋制關係：BEATS[a] = 被 a 剋的屬性
const BEATS := {"fire": "leaf", "leaf": "rock", "rock": "thunder", "thunder": "water", "water": "fire"}

## 招式效果 fx：
## burn 灼傷、para 麻痺、para_flip 擲硬幣正面麻痺、heal 自己回復 v、bench 對手每隻後備 v 傷害、
## flip_plus 擲硬幣正面多 v、energy_plus 每多一個能量多 v（最多 2 個）、self_discard 自己丟 v 個能量、
## recoil 自己受 v 傷害、snipe 對手 HP 最低的後備 v 傷害、power_up 從牌組找 1 張同屬性能量附到後備、draw 抽 v 張
const BEASTS := {
	"embertail": {"name": "焰尾狐", "type": "fire", "stage": 0, "hp": 60, "retreat": 1, "attacks": [
		{"name": "撲咬", "cost": ["any"], "dmg": 10},
		{"name": "火花", "cost": ["fire", "any"], "dmg": 30}]},
	"blazecrown": {"name": "炎冠狐王", "type": "fire", "stage": 1, "from": "embertail", "hp": 120, "retreat": 1, "attacks": [
		{"name": "狐火", "cost": ["fire"], "dmg": 30, "fx": "burn"},
		{"name": "烈焰皇冠", "cost": ["fire", "fire", "any"], "dmg": 100, "fx": "self_discard", "v": 1}]},
	"cindrake": {"name": "火蜥寶", "type": "fire", "stage": 0, "hp": 70, "retreat": 2, "attacks": [
		{"name": "火苗", "cost": ["fire"], "dmg": 10, "fx": "burn"},
		{"name": "頭鎚", "cost": ["fire", "any"], "dmg": 30}]},
	"infernadrake": {"name": "爆炎龍", "type": "fire", "stage": 1, "from": "cindrake", "hp": 130, "retreat": 3, "attacks": [
		{"name": "熔岩噴發", "cost": ["fire", "fire", "any"], "dmg": 70, "fx": "bench", "v": 10},
		{"name": "龍之烈焰", "cost": ["fire", "fire", "any", "any"], "dmg": 130, "fx": "recoil", "v": 30}]},
	"bubbotter": {"name": "泡泡獺", "type": "water", "stage": 0, "hp": 60, "retreat": 1, "attacks": [
		{"name": "泡泡", "cost": ["water"], "dmg": 10, "fx": "para_flip"},
		{"name": "水槍", "cost": ["water", "any"], "dmg": 30}]},
	"tideblade": {"name": "浪刃獺", "type": "water", "stage": 1, "from": "bubbotter", "hp": 110, "retreat": 1, "attacks": [
		{"name": "水刃", "cost": ["water", "any"], "dmg": 50},
		{"name": "巨浪斬", "cost": ["water", "water", "any"], "dmg": 80, "fx": "energy_plus", "v": 20}]},
	"jellume": {"name": "水母靈", "type": "water", "stage": 0, "hp": 50, "retreat": 1, "attacks": [
		{"name": "觸手麻痺", "cost": ["water"], "dmg": 10, "fx": "para_flip"},
		{"name": "治癒水流", "cost": ["any", "any"], "dmg": 20, "fx": "heal", "v": 20}]},
	"abysslume": {"name": "深海燈母", "type": "water", "stage": 1, "from": "jellume", "hp": 100, "retreat": 2, "attacks": [
		{"name": "幽光", "cost": ["water"], "dmg": 20, "fx": "heal", "v": 30},
		{"name": "深淵漩渦", "cost": ["water", "water", "any"], "dmg": 70, "fx": "para_flip"}]},
	"sproutbun": {"name": "葉芽兔", "type": "leaf", "stage": 0, "hp": 60, "retreat": 1, "attacks": [
		{"name": "葉片飛鏢", "cost": ["leaf"], "dmg": 20},
		{"name": "光合作用", "cost": ["leaf", "any"], "dmg": 20, "fx": "heal", "v": 20}]},
	"bloomhare": {"name": "花冠兔", "type": "leaf", "stage": 1, "from": "sproutbun", "hp": 110, "retreat": 1, "attacks": [
		{"name": "種子催化", "cost": ["leaf"], "dmg": 20, "fx": "power_up"},
		{"name": "花瓣暴風", "cost": ["leaf", "leaf", "any"], "dmg": 90}]},
	"mushlet": {"name": "蘑菇寶", "type": "leaf", "stage": 0, "hp": 70, "retreat": 2, "attacks": [
		{"name": "催眠孢子", "cost": ["leaf"], "dmg": 10, "fx": "para_flip"},
		{"name": "蘑菇撞", "cost": ["leaf", "any"], "dmg": 30}]},
	"oakwarden": {"name": "古樹守衛", "type": "leaf", "stage": 1, "from": "mushlet", "hp": 140, "retreat": 3, "attacks": [
		{"name": "扎根", "cost": ["leaf", "any"], "dmg": 40, "fx": "heal", "v": 30},
		{"name": "古木重壓", "cost": ["leaf", "leaf", "any", "any"], "dmg": 120}]},
	"zapwing": {"name": "雷翼雀", "type": "thunder", "stage": 0, "hp": 50, "retreat": 0, "attacks": [
		{"name": "電光啄", "cost": ["thunder"], "dmg": 20},
		{"name": "雙翼閃電", "cost": ["thunder", "any"], "dmg": 20, "fx": "flip_plus", "v": 30}]},
	"stormtalon": {"name": "雷霆鷹", "type": "thunder", "stage": 1, "from": "zapwing", "hp": 100, "retreat": 0, "attacks": [
		{"name": "疾風雷擊", "cost": ["thunder", "any"], "dmg": 50, "fx": "para_flip"},
		{"name": "萬雷降臨", "cost": ["thunder", "thunder", "any"], "dmg": 110, "fx": "self_discard", "v": 2}]},
	"voltbug": {"name": "電球蟲", "type": "thunder", "stage": 0, "hp": 60, "retreat": 1, "attacks": [
		{"name": "充電", "cost": ["thunder"], "dmg": 0, "fx": "power_up"},
		{"name": "電擊", "cost": ["thunder", "any"], "dmg": 30, "fx": "para_flip"}]},
	"magbeetle": {"name": "磁暴甲", "type": "thunder", "stage": 1, "from": "voltbug", "hp": 120, "retreat": 2, "attacks": [
		{"name": "磁力衝撞", "cost": ["thunder", "any"], "dmg": 50},
		{"name": "電磁風暴", "cost": ["thunder", "thunder", "any"], "dmg": 70, "fx": "bench", "v": 20}]},
	"pebblet": {"name": "石丸", "type": "rock", "stage": 0, "hp": 70, "retreat": 2, "attacks": [
		{"name": "滾動", "cost": ["rock"], "dmg": 20},
		{"name": "硬化撞擊", "cost": ["rock", "any"], "dmg": 30, "fx": "flip_plus", "v": 20}]},
	"bouldergolem": {"name": "巨岩魔像", "type": "rock", "stage": 1, "from": "pebblet", "hp": 150, "retreat": 4, "attacks": [
		{"name": "岩石拳", "cost": ["rock", "any"], "dmg": 60},
		{"name": "山崩", "cost": ["rock", "rock", "any", "any"], "dmg": 130, "fx": "recoil", "v": 20}]},
	"crystaliz": {"name": "晶刺蜥", "type": "rock", "stage": 0, "hp": 60, "retreat": 1, "attacks": [
		{"name": "晶刺射擊", "cost": ["rock"], "dmg": 10, "fx": "snipe", "v": 10},
		{"name": "抓", "cost": ["rock", "any"], "dmg": 30}]},
	"geodrake": {"name": "晶甲龍", "type": "rock", "stage": 1, "from": "crystaliz", "hp": 130, "retreat": 3, "attacks": [
		{"name": "水晶飛彈", "cost": ["rock", "any"], "dmg": 40, "fx": "snipe", "v": 30},
		{"name": "晶甲咆哮", "cost": ["rock", "rock", "any"], "dmg": 90}]},
}

const ENERGY := {
	"e_fire": {"name": "火能量", "type": "fire"},
	"e_water": {"name": "水能量", "type": "water"},
	"e_leaf": {"name": "草能量", "type": "leaf"},
	"e_thunder": {"name": "雷能量", "type": "thunder"},
	"e_rock": {"name": "岩能量", "type": "rock"},
}

## kind：item 道具（每回合不限張）／support 支援（每回合 1 張）
## target：none 不用選、mine 選自己場上一隻、bench 選自己後備一隻
const TRAINERS := {
	"potion": {"name": "回復藥", "kind": "item", "target": "mine", "text": "自己場上一隻靈獸回復 30 HP。"},
	"finder": {"name": "能量探測器", "kind": "item", "target": "none", "text": "從牌組找 1 張能量卡加入手牌。"},
	"whistle": {"name": "換位哨", "kind": "item", "target": "bench", "text": "戰鬥位置的靈獸和一隻後備靈獸交換（不用撤退能量）。"},
	"band": {"name": "力量頭帶", "kind": "item", "target": "none", "text": "這回合戰鬥靈獸的招式傷害 +20。"},
	"scroll": {"name": "召喚卷軸", "kind": "item", "target": "none", "text": "從牌組找 1 張基礎靈獸加入手牌。"},
	"bell": {"name": "淨化鈴", "kind": "item", "target": "none", "text": "戰鬥靈獸解除灼傷與麻痺，並回復 20 HP。"},
	"recycle": {"name": "能量沙漏", "kind": "item", "target": "none", "text": "棄牌區最多 2 張能量卡回到手牌。"},
	"journal": {"name": "旅行日誌", "kind": "support", "target": "none", "text": "抽 3 張牌。（支援卡每回合限 1 張）"},
	"notes": {"name": "學者筆記", "kind": "support", "target": "none", "text": "手牌洗回牌組，再抽 5 張。（支援卡每回合限 1 張）"},
}

const DECK_SIZE := 30
const MAX_COPIES := 3
const BENCH_MAX := 4
const STARS_TO_WIN := 3

## 每種屬性的兩條進化線（基礎, 進化）
const LINES := {
	"fire": [["embertail", "blazecrown"], ["cindrake", "infernadrake"]],
	"water": [["bubbotter", "tideblade"], ["jellume", "abysslume"]],
	"leaf": [["sproutbun", "bloomhare"], ["mushlet", "oakwarden"]],
	"thunder": [["zapwing", "stormtalon"], ["voltbug", "magbeetle"]],
	"rock": [["pebblet", "bouldergolem"], ["crystaliz", "geodrake"]],
}

const STARTER_NAME := {"fire": "烈焰起始牌組", "water": "激流起始牌組", "leaf": "森林起始牌組",
	"thunder": "雷霆起始牌組", "rock": "大地起始牌組"}

## 電腦對手：名字、頭像、介紹、難度（0 簡單～3 冠軍）、牌組、勝利獎金
const OPPONENTS := [
	{"id": "mia", "name": "花店的米亞", "avatar": "ai_mia", "level": 0, "reward": 60,
		"intro": "喜歡花草的溫柔訓練家，草屬性牌組。", "deck": "starter_leaf"},
	{"id": "rocco", "name": "登山客洛可", "avatar": "ai_rocco", "level": 1, "reward": 80,
		"intro": "爬遍每座山的硬漢，岩屬性牌組，很耐打。", "deck": "starter_rock"},
	{"id": "luna", "name": "星夜的露娜", "avatar": "ai_luna", "level": 2, "reward": 110,
		"intro": "神祕的雙屬性高手，水＋雷的麻痺戰術。", "deck": "luna"},
	{"id": "drake", "name": "冠軍德雷克", "avatar": "ai_drake", "level": 3, "reward": 160,
		"intro": "靈獸卡牌聯盟冠軍！火屬性猛攻牌組。", "deck": "drake"},
]


static func is_beast(id: String) -> bool:
	return BEASTS.has(id)


static func is_energy(id: String) -> bool:
	return ENERGY.has(id)


static func is_trainer(id: String) -> bool:
	return TRAINERS.has(id)


static func card_name(id: String) -> String:
	if BEASTS.has(id):
		return BEASTS[id].name
	if ENERGY.has(id):
		return ENERGY[id].name
	if TRAINERS.has(id):
		return TRAINERS[id].name
	return id


static func all_ids() -> Array:
	return BEASTS.keys() + ENERGY.keys() + TRAINERS.keys()


## 卡圖路徑（對應 assets/images/cards/）
static func art_path(id: String) -> String:
	if BEASTS.has(id):
		return "res://assets/images/cards/b_%s.png" % id
	if ENERGY.has(id):
		return "res://assets/images/cards/%s.png" % id
	return "res://assets/images/cards/t_%s.png" % id


## 稀有度：0 普通、1 不普通、2 稀有（卡包抽卡用）
static func rarity(id: String) -> int:
	if BEASTS.has(id):
		return 2 if BEASTS[id].stage == 1 else 0
	if TRAINERS.has(id):
		return 1
	return 0


static func starter(t: String) -> Array:
	var d: Array = []
	for line in LINES[t]:
		for i in 3:
			d.append(line[0])
		for i in 2:
			d.append(line[1])
	for i in 12:
		d.append("e_" + t)
	d += ["potion", "potion", "finder", "finder", "journal", "journal", "whistle", "scroll"]
	return d


static func deck_by_name(n: String) -> Array:
	if n.begins_with("starter_"):
		return starter(n.substr(8))
	match n:
		"luna":
			var d: Array = []
			for i in 3:
				d += ["bubbotter", "zapwing"]
			d += ["tideblade", "tideblade", "stormtalon", "stormtalon"]
			for i in 6:
				d += ["e_water", "e_thunder"]
			return d + ["potion", "finder", "finder", "journal", "notes", "whistle", "bell", "scroll"]
		"drake":
			var d: Array = []
			for i in 3:
				d += ["embertail", "cindrake"]
			d += ["blazecrown", "blazecrown", "infernadrake", "infernadrake"]
			for i in 12:
				d.append("e_fire")
			return d + ["potion", "finder", "finder", "notes", "band", "band", "journal", "recycle"]
	return starter("fire")


## 檢查牌組是否合法；回傳錯誤訊息，空字串代表合法
static func validate_deck(d: Array) -> String:
	if d.size() != DECK_SIZE:
		return "牌組要剛好 %d 張（目前 %d 張）" % [DECK_SIZE, d.size()]
	var counts := {}
	var basics := 0
	for id in d:
		counts[id] = counts.get(id, 0) + 1
		if is_beast(id) and BEASTS[id].stage == 0:
			basics += 1
	for id in counts:
		if not is_energy(id) and counts[id] > MAX_COPIES:
			return "「%s」最多放 %d 張" % [card_name(id), MAX_COPIES]
	if basics < 4:
		return "至少要放 4 張基礎靈獸"
	return ""
