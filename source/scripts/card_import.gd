class_name CardImport
extends RefCounted
## 批次匯入：把外部卡片 JSON（一個系列一個檔）轉成自製卡定義（格式見 SaveDB）。
## JSON 是卡片陣列：{id, name, supertype, subtype, setCode, imageUrl, hp, pokemonType, stage, evolvesFrom,
## retreatCost, attacks: [{name, cost, damage, effect}], rulesText}。
## 外部屬性併進遊戲的 5 屬性；招式效果從說明文字找對應的 fx，找不到就只留傷害；特性、弱點、抵抗力不匯入。

## 外部屬性 → 遊戲屬性（招式費用也照這張表，對不上卡片屬性的費用算任意能量）
const TYPE_MAP := {"Fire": "fire", "Darkness": "fire", "Water": "water", "Dragon": "water", "Grass": "leaf",
	"Colorless": "leaf", "Lightning": "thunder", "Psychic": "thunder", "Fighting": "rock", "Metal": "rock"}
const DISCARD_ALL := 4    # 「能量全部丟棄」對應的 self_discard 數值（費用上限）
const DRAW_UP_TO := 3     # 「抽到手牌滿 N 張」對應的抽牌數


## 解析一個 JSON 檔，格式不對回傳空陣列
static func parse(text: String) -> Array:
	var d = JSON.parse_string(text)
	if not (d is Array):
		return []
	return d.filter(func(c): return c is Dictionary and c.has("supertype") and c.has("name"))


static func type_of(t) -> String:
	return TYPE_MAP.get(str(t), "fire")


## JSON 裡的圖檔只取檔名，圖片用檔名配對（手機沒辦法選資料夾，只能選一堆檔案）
static func image_name(c: Dictionary) -> String:
	return str(c.get("imageUrl", "")).get_file()


static func to_def(c: Dictionary) -> Dictionary:
	var def := SaveDB.default_card(0)
	def.name = str(c.name)
	match str(c.supertype):
		"Trainer":
			def.kind = "trainer"
			def.effect = trainer_effect(c)
		"Energy":
			def.kind = "energy"
			def.type = type_of(c.get("energyType", c.get("pokemonType")))
		_:
			def.type = type_of(c.get("pokemonType"))
			def.hp = clampi(int(c.get("hp", 60) if c.get("hp") != null else 60), 10, 300)
			var retreat = c.get("retreatCost")
			def.retreat = mini(retreat.size(), CardDB.MAX_COST) if retreat is Array else 0
			def.from_name = str(c.get("evolvesFrom")) if c.get("evolvesFrom") != null else ""
			var atks: Array = []
			var src = c.get("attacks")
			for a in (src if src is Array else []):
				if atks.size() < 2:
					atks.append(attack_def(a, def.type))
			# 編輯畫面固定兩招，少的留空
			while atks.size() < 2:
				atks.append({"name": "", "dmg": 0, "n_type": 1, "n_any": 0, "fx": "", "v": 0})
			def.attacks = atks
	return def


static func attack_def(a: Dictionary, t: String) -> Dictionary:
	var n_type := 0
	var n_any := 0
	var cost = a.get("cost")
	for e in (cost if cost is Array else []):
		if str(e) != "Colorless" and type_of(e) == t:
			n_type += 1
		else:
			n_any += 1
	n_any = mini(n_any, maxi(CardDB.MAX_COST - n_type, 0))
	n_type = mini(n_type, CardDB.MAX_COST)
	var out := {"name": str(a.get("name", "")), "dmg": 0, "n_type": n_type, "n_any": n_any, "fx": "", "v": 0}
	out.merge(read_effect(str(a.get("damage", "")), str(a.get("effect", "")), n_type + n_any), true)
	return out


## 看傷害欄（10、20+、30×）和說明文字，回傳 {dmg, fx, v}
static func read_effect(damage: String, e: String, n_cost: int) -> Dictionary:
	var base := int(_num(damage, "(\\d+)"))
	var mark := damage.right(1)
	if mark == "×":
		var coins := _num(e, "擲(\\d+)次硬幣")
		if coins != "":
			return {"dmg": base, "fx": "flip_plus", "v": base * (int(coins) - 1)}
		if e.contains("能量的數量×"):
			return {"dmg": base * maxi(n_cost, 1), "fx": "energy_plus", "v": base}
		return {"dmg": base * 2}    # 其他「數量×傷害」抓常見的 2
	if mark == "+":
		if e.contains("硬幣"):
			return {"dmg": base, "fx": "flip_plus", "v": int(_num(e, "增加(\\d+)點"))}
		var per := _num(e, "能量的數量×(\\d+)")
		if per != "":
			return {"dmg": base, "fx": "energy_plus", "v": int(per)}
		return {"dmg": base}
	var out := {"dmg": base}
	var hit := _num(e, "受到(\\d+)點傷害")
	if base == 0 and hit != "" and not e.contains("也受到"):
		out.dmg = int(hit)
		if e.contains("各受到"):
			out.merge({"fx": "bench", "v": int(hit)}, true)
		return out
	var heads := e.contains("硬幣")
	if e.contains("對手的戰鬥寶可夢【麻痺"):
		out.fx = "para_flip" if heads else "para"
	elif e.contains("對手的戰鬥寶可夢【灼傷") or e.contains("對手的戰鬥寶可夢【中毒"):
		out.fx = "burn"    # 遊戲沒有中毒，同樣是回合結束扣血的灼傷
	elif e.contains("對手的戰鬥寶可夢【混亂") or e.contains("對手的戰鬥寶可夢【睡眠"):
		out.fx = "para_flip"
	elif e.contains("也受到"):
		out.merge({"fx": "recoil", "v": int(_num(e, "也受到(\\d+)點"))}, true)
	elif e.contains("恢復"):
		var heal := _num(e, "恢復「(\\d+)」")
		out.merge({"fx": "heal", "v": int(heal) if heal != "" else base}, true)
	elif e.contains("附加的能量卡全部丟棄"):
		out.merge({"fx": "self_discard", "v": DISCARD_ALL}, true)
	elif e.contains("這隻寶可夢身上附加的能量"):
		var n := _num(e, "選擇(\\d+)個")
		if n != "" and e.contains("丟棄"):
			out.merge({"fx": "self_discard", "v": int(n)}, true)
	elif e.contains("抽出") or e.contains("抽卡直到"):
		var n := _num(e, "抽出(\\d+)張")
		out.merge({"fx": "draw", "v": int(n) if n != "" else DRAW_UP_TO}, true)
	elif e.contains("能量") and e.contains("附於") and e.contains("牌庫"):
		out.fx = "power_up"
	return out


## 訓練家卡沿用一張內建卡的效果，看規則文字挑最接近的；看不出來就依種類給預設
static func trainer_effect(c: Dictionary) -> String:
	var t := str(c.get("rulesText")) if c.get("rulesText") != null else ""
	if t.contains("手牌") and t.contains("放回牌庫") and t.contains("抽"):
		return "notes"
	if t.contains("恢復"):
		return "potion"
	if t.contains("抽"):
		return "journal"
	if t.contains("棄牌區") and t.contains("能量"):
		return "recycle"
	if t.contains("牌庫") and t.contains("能量"):
		return "finder"
	if t.contains("牌庫") and t.contains("寶可夢"):
		return "scroll"
	if t.contains("互換"):
		return "whistle"
	if t.contains("傷害"):
		return "band"
	match str(c.get("subtype")):
		"Supporter", "Stadium":
			return "journal"
		"PokemonTool":
			return "band"
	return "potion"


static func _num(s: String, pattern: String) -> String:
	var m := RegEx.create_from_string(pattern).search(s)
	return m.get_string(1) if m else ""
