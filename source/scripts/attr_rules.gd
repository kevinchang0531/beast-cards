class_name AttrRules
extends RefCounted
## 10 屬性規則（對照表在 data/attributes.json，engine_test 會檢查兩邊一致）。
## 對戰付費用走 Battle.can_pay，這裡是匯入對應和分配能量的函式；方案見 docs/屬性擴充方案.md。

## 屬性 id → [遊戲內代號, 中文, 有無基本能量, 缺美術時借用的舊屬性]
const ATTRS := {
	"Grass": ["leaf", "草", true, "leaf"],
	"Fire": ["fire", "火", true, "fire"],
	"Water": ["water", "水", true, "water"],
	"Lightning": ["thunder", "雷", true, "thunder"],
	"Fighting": ["rock", "鬥", true, "rock"],
	"Psychic": ["psychic", "超", true, "thunder"],
	"Darkness": ["dark", "惡", true, "fire"],
	"Metal": ["metal", "鋼", true, "rock"],
	"Dragon": ["dragon", "龍", false, "water"],
	"Colorless": ["any", "無色", false, "leaf"],
}
## 主系列屬性 → 卡牌屬性
const MAIN_TYPES := {
	"草": "Grass", "蟲": "Grass", "火": "Fire", "水": "Water", "冰": "Water", "電": "Lightning",
	"格鬥": "Fighting", "岩石": "Fighting", "地面": "Fighting", "超能力": "Psychic", "幽靈": "Psychic", "妖精": "Psychic",
	"惡": "Darkness", "毒": "Darkness", "鋼": "Metal", "龍": "Dragon", "一般": "Colorless", "飛行": "Colorless",
}


static func key_of(id: String) -> String:
	return ATTRS[id][0] if ATTRS.has(id) else "any"


## 畫面用：有專屬美術就回原屬性，沒有就借舊屬性，底層資料不變
static func visual_key(id: String, has_asset: Callable) -> String:
	var key := key_of(id)
	if has_asset.call(key):
		return key
	return ATTRS[id][3] if ATTRS.has(id) else "leaf"


## 卡片 JSON 的費用陣列 → 引擎費用，混合費用（雷＋鬥）逐項保留
static func cost_keys(cost: Array) -> Array:
	var out: Array = []
	for c in cost:
		var k := key_of(str(c))
		out.append("any" if k == "dragon" else k)    # 龍沒有基本能量
	return out


## 檢查費用：先配指定屬性，再用剩下的任何能量補無色。
## 回傳 {ok, paid, left, missing}。規則上攻擊不會丟掉能量，所以這裡只分配、不改動 attached；
## 招式說明要丟能量時由呼叫端把 paid 裡的牌丟掉。
static func check_and_deduct_energy(attached: Array, cost: Array) -> Dictionary:
	var left := attached.duplicate()
	var paid: Array = []
	var missing: Array = []
	var anys := 0
	for c in cost:
		if c == "any":
			anys += 1
		elif left.has(c):
			left.erase(c)
			paid.append(c)
		else:
			missing.append(c)
	for i in anys:
		if left.is_empty():
			missing.append("any")
		else:
			paid.append(left.pop_back())
	return {"ok": missing.is_empty(), "paid": paid, "left": left, "missing": missing}
