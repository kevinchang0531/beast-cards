class_name Battle
extends RefCounted
## 對戰規則引擎（純邏輯、不碰畫面）。
## 同一個種子＋同樣的牌組＋同樣的動作順序，一定得到同樣的結果：
## - 存檔只要存 {seed, decks, names, history}，讀檔時重播一遍就回到原狀態
## - 線上對戰兩邊各跑一份引擎，只互傳「動作」，畫面就會同步
##
## 規則摘要：牌組 30 或 60 張、起手 7 張（沒有基礎靈獸就重洗）；每回合抽 1 張、附加 1 個能量、支援卡 1 張、撤退 1 次；
## 先攻玩家第一回合不能攻擊；雙方第一回合都不能進化；攻擊後回合結束；擊倒一隻得 1 顆星徽，先拿 3 顆獲勝；
## 對手場上沒有靈獸、或輪到自己時牌組抽光也算輸。
## 位置編號 slot：0 = 戰鬥位置，1～4 = 後備第 1～4 隻。

var rng := RandomNumberGenerator.new()
var seed_value := 0
var decks: Array = [[], []]
var names: Array = ["玩家", "對手"]
var cards: Array = []          # uid → 卡片 id
var players: Array = []
var turn := 0                  # 第幾回合（雙方各算一回合）
var current := 0               # 輪到誰
var first := 0
var pending: Array = []        # 等待中的選擇：[{p, kind:"promote"}]
var end_after_pending := false
var winner := -1
var win_reason := ""
var history: Array = []        # 已執行的動作（存檔／重播用）
var events: Array = []         # 這次 apply 產生的事件（給畫面播動畫音效）
var log_lines: Array = []


func setup(p_seed: int, deck0: Array, deck1: Array, name0 := "玩家", name1 := "對手") -> void:
	seed_value = p_seed
	rng.seed = p_seed
	decks = [deck0.duplicate(), deck1.duplicate()]
	names = [name0, name1]
	cards.clear()
	players.clear()
	for pi in 2:
		var p := {"deck": [], "hand": [], "discard": [], "active": null, "bench": [], "stars": 0,
			"energy_used": false, "support_used": false, "retreat_used": false, "band": 0, "mulligans": 0}
		for id in decks[pi]:
			p.deck.append(cards.size())
			cards.append(str(id))
		players.append(p)
	for pi in 2:
		var p: Dictionary = players[pi]
		while true:
			_shuffle(p.deck)
			for i in 7:
				p.hand.append(p.deck.pop_back())
			if _hand_has_basic(pi):
				break
			p.mulligans += 1
			p.deck += p.hand
			p.hand.clear()
			if p.mulligans > 20:   # 牌組裡根本沒基礎靈獸（理論上 validate 會擋）
				break
		# 自動把 HP 最高的基礎靈獸放到戰鬥位置
		var best := -1
		for i in p.hand.size():
			var id: String = cards[p.hand[i]]
			if CardDB.is_beast(id) and CardDB.BEASTS[id].stage == 0:
				if best < 0 or CardDB.BEASTS[id].hp > CardDB.BEASTS[cards[p.hand[best]]].hp:
					best = i
		if best >= 0:
			p.active = _new_beast(p.hand[best])
			p.hand.remove_at(best)
		if p.mulligans > 0:
			_log("%s 起手沒有基礎靈獸，重洗了 %d 次。" % [names[pi], p.mulligans])
	first = rng.randi_range(0, 1)
	current = first
	turn = 1
	_log("擲硬幣決定：%s 先攻！" % names[first])
	_start_turn()


# ---------- 查詢 ----------

func actor() -> int:
	if not pending.is_empty():
		return pending[0].p
	return current


func card_id(uid: int) -> String:
	return cards[uid]


func beast_at(pi: int, slot: int):
	var p: Dictionary = players[pi]
	if slot == 0:
		return p.active
	if slot - 1 < p.bench.size():
		return p.bench[slot - 1]
	return null


func beast_data(b: Dictionary) -> Dictionary:
	return CardDB.BEASTS[cards[b.uid]]


func hp_left(b: Dictionary) -> int:
	return beast_data(b).hp - b.dmg


func energy_types(b: Dictionary) -> Array:
	var out: Array = []
	for u in b.energy:
		out.append(CardDB.ENERGY[cards[u]].type)
	return out


static func can_pay(have: Array, cost: Array) -> bool:
	var pool := have.duplicate()
	var anys := 0
	for c in cost:
		if c == "any":
			anys += 1
		else:
			var i := pool.find(c)
			if i < 0:
				return false
			pool.remove_at(i)
	return pool.size() >= anys


## 還缺哪些能量才付得起（給 AI 判斷要附加什麼）
static func missing(have: Array, cost: Array) -> Array:
	var pool := have.duplicate()
	var miss: Array = []
	var anys := 0
	for c in cost:
		if c == "any":
			anys += 1
		elif pool.has(c):
			pool.erase(c)
		else:
			miss.append(c)
	for i in maxi(0, anys - pool.size()):
		miss.append("any")
	return miss


func can_attack(pi: int, n: int) -> bool:
	if winner >= 0 or not pending.is_empty() or pi != current or turn == 1:
		return false
	var b = players[pi].active
	if b == null or b.status == "para":
		return false
	var atks: Array = beast_data(b).attacks
	return n < atks.size() and can_pay(energy_types(b), atks[n].cost)


## 預估傷害（不含擲硬幣加成），給畫面顯示和 AI 用
func preview_damage(pi: int, n: int) -> int:
	var b = players[pi].active
	var d = players[1 - pi].active
	if b == null or d == null:
		return 0
	var a: Dictionary = beast_data(b).attacks[n]
	var dmg: int = a.dmg
	if a.get("fx", "") == "energy_plus":
		dmg += int(a.v) * clampi(b.energy.size() - a.cost.size(), 0, 2)
	if dmg > 0:
		dmg += players[pi].band
		if CardDB.BEATS[beast_data(b).type] == beast_data(d).type:
			dmg *= 2
	return dmg


func is_weak_to(defender: Dictionary, attacker: Dictionary) -> bool:
	return CardDB.BEATS[beast_data(attacker).type] == beast_data(defender).type


# ---------- 合法動作 ----------

func legal_actions(pi: int) -> Array:
	var out: Array = []
	if winner >= 0 or pi != actor():
		return out
	var p: Dictionary = players[pi]
	if not pending.is_empty():
		for i in p.bench.size():
			out.append({"t": "promote", "p": pi, "bench": i})
		return out
	for i in p.hand.size():
		var id: String = cards[p.hand[i]]
		if CardDB.is_beast(id):
			var bd: Dictionary = CardDB.BEASTS[id]
			if bd.stage == 0:
				if p.bench.size() < CardDB.BENCH_MAX:
					out.append({"t": "basic", "p": pi, "hand": i})
			elif turn >= 3:
				for s in 1 + p.bench.size():
					var b = beast_at(pi, s)
					if b != null and CardDB.can_evolve(cards[b.uid], id) and b.turn_played < turn:
						out.append({"t": "evolve", "p": pi, "hand": i, "slot": s})
		elif CardDB.is_energy(id):
			if not p.energy_used:
				for s in 1 + p.bench.size():
					if beast_at(pi, s) != null:
						out.append({"t": "attach", "p": pi, "hand": i, "slot": s})
		else:
			for s in _trainer_targets(pi, id):
				out.append({"t": "trainer", "p": pi, "hand": i, "slot": s})
	if p.active != null and not p.retreat_used and p.active.status != "para" \
			and p.active.energy.size() >= beast_data(p.active).retreat:
		for i in p.bench.size():
			out.append({"t": "retreat", "p": pi, "bench": i})
	if p.active != null:
		for n in beast_data(p.active).attacks.size():
			if can_attack(pi, n):
				out.append({"t": "attack", "p": pi, "n": n})
	out.append({"t": "end", "p": pi})
	return out


## 這張訓練家卡可以對哪些位置用；不能用回傳空陣列，不用選目標回傳 [-1]
func _trainer_targets(pi: int, id: String) -> Array:
	var p: Dictionary = players[pi]
	var tr: Dictionary = CardDB.TRAINERS[id]
	if tr.kind == "support" and p.support_used:
		return []
	match CardDB.effect_of(id):
		"potion":
			var out: Array = []
			for s in 1 + p.bench.size():
				var b = beast_at(pi, s)
				if b != null and b.dmg > 0:
					out.append(s)
			return out
		"whistle":
			var out: Array = []
			if p.active != null:
				for i in p.bench.size():
					out.append(i + 1)
			return out
		"finder":
			return [-1] if _deck_find(pi, "energy") >= 0 else []
		"scroll":
			return [-1] if _deck_find(pi, "basic") >= 0 else []
		"band":
			return [-1] if p.band == 0 and p.active != null else []
		"bell":
			return [-1] if p.active != null and (p.active.status != "" or p.active.dmg > 0) else []
		"recycle":
			for u in p.discard:
				if CardDB.is_energy(cards[u]):
					return [-1]
			return []
		"journal":
			return [-1] if not p.deck.is_empty() else []
		"notes":
			return [-1]
	return []


static func action_key(a: Dictionary) -> String:
	return "%s|%d|%d|%d|%d|%d" % [a.get("t", ""), int(a.get("p", -1)), int(a.get("hand", -1)),
		int(a.get("slot", -9)), int(a.get("bench", -1)), int(a.get("n", -1))]


func is_legal(a: Dictionary) -> bool:
	var k := action_key(a)
	for la in legal_actions(int(a.get("p", -1))):
		if action_key(la) == k:
			return true
	return false


# ---------- 執行動作 ----------

## 執行一個動作；不合法就回傳 false、狀態不變
func apply(a: Dictionary) -> bool:
	events = []
	a = _normalize(a)
	# 投降：任何時候都可以
	if a.t == "surrender" and winner < 0 and (a.p == 0 or a.p == 1):
		history.append(a)
		_win(1 - a.p, "%s 投降了" % names[a.p])
		return true
	if not is_legal(a):
		return false
	history.append(a)
	var pi: int = a.p
	var p: Dictionary = players[pi]
	match a.t:
		"promote":
			var b: Dictionary = p.bench[a.bench]
			p.bench.remove_at(a.bench)
			p.active = b
			pending.pop_front()
			_log("%s 派出 %s 上場戰鬥。" % [names[pi], beast_data(b).name])
			events.append({"e": "promote", "p": pi})
			if pending.is_empty() and end_after_pending:
				end_after_pending = false
				_end_turn()
		"basic":
			var u: int = p.hand[a.hand]
			p.hand.remove_at(a.hand)
			p.bench.append(_new_beast(u))
			_log("%s 把 %s 放到後備。" % [names[pi], CardDB.card_name(cards[u])])
			events.append({"e": "play", "p": pi, "slot": p.bench.size()})
		"evolve":
			var u: int = p.hand[a.hand]
			p.hand.remove_at(a.hand)
			var b: Dictionary = beast_at(pi, a.slot)
			var old: String = beast_data(b).name
			b.stack.append(b.uid)
			b.uid = u
			b.status = ""
			b.turn_played = turn
			_log("%s 的 %s 進化成 %s！" % [names[pi], old, beast_data(b).name])
			events.append({"e": "evolve", "p": pi, "slot": a.slot})
		"attach":
			var u: int = p.hand[a.hand]
			p.hand.remove_at(a.hand)
			var b: Dictionary = beast_at(pi, a.slot)
			b.energy.append(u)
			p.energy_used = true
			_log("%s 把 %s 附加給 %s。" % [names[pi], CardDB.card_name(cards[u]), beast_data(b).name])
			events.append({"e": "energy", "p": pi, "slot": a.slot})
		"trainer":
			var u: int = p.hand[a.hand]
			p.hand.remove_at(a.hand)
			p.discard.append(u)
			_play_trainer(pi, cards[u], a.slot)
		"retreat":
			var b: Dictionary = p.active
			for i in beast_data(b).retreat:
				p.discard.append(b.energy.pop_back())
			b.status = ""
			var nb: Dictionary = p.bench[a.bench]
			p.bench[a.bench] = b
			p.active = nb
			p.retreat_used = true
			_log("%s 的 %s 撤退，換 %s 上場。" % [names[pi], beast_data(b).name, beast_data(nb).name])
			events.append({"e": "retreat", "p": pi})
		"attack":
			_attack(pi, a.n)
		"end":
			_log("%s 結束回合。" % names[pi])
			_end_turn()
	return true


func _normalize(a: Dictionary) -> Dictionary:
	var o := {"t": str(a.get("t", "")), "p": int(a.get("p", -1))}
	for k in ["hand", "slot", "bench", "n"]:
		if a.has(k):
			o[k] = int(a[k])
	return o


func _play_trainer(pi: int, id: String, slot: int) -> void:
	var p: Dictionary = players[pi]
	var tr: Dictionary = CardDB.TRAINERS[id]
	if tr.kind == "support":
		p.support_used = true
	_log("%s 使用了 %s。" % [names[pi], tr.name])
	events.append({"e": "trainer", "p": pi, "id": id})
	match CardDB.effect_of(id):
		"potion":
			var b: Dictionary = beast_at(pi, slot)
			_heal(pi, b, 30)
		"whistle":
			var nb: Dictionary = p.bench[slot - 1]
			p.bench[slot - 1] = p.active
			p.active.status = ""
			p.active = nb
			events.append({"e": "retreat", "p": pi})
		"finder":
			var i := _deck_find(pi, "energy")
			p.hand.append(p.deck[i])
			p.deck.remove_at(i)
			_shuffle(p.deck)
		"scroll":
			var i := _deck_find(pi, "basic")
			_log("找到了 %s。" % CardDB.card_name(cards[p.deck[i]]))
			p.hand.append(p.deck[i])
			p.deck.remove_at(i)
			_shuffle(p.deck)
		"band":
			p.band = 20
		"bell":
			p.active.status = ""
			_heal(pi, p.active, 20)
		"recycle":
			var got := 0
			for i in range(p.discard.size() - 1, -1, -1):
				if got < 2 and CardDB.is_energy(cards[p.discard[i]]):
					p.hand.append(p.discard[i])
					p.discard.remove_at(i)
					got += 1
		"journal":
			_draw(pi, 3)
		"notes":
			p.deck += p.hand
			p.hand.clear()
			_shuffle(p.deck)
			events.append({"e": "shuffle", "p": pi})
			_draw(pi, 5)


func _attack(pi: int, n: int) -> void:
	var p: Dictionary = players[pi]
	var o: Dictionary = players[1 - pi]
	var b: Dictionary = p.active
	var d: Dictionary = o.active
	var bd := beast_data(b)
	var a: Dictionary = bd.attacks[n]
	var fx: String = a.get("fx", "")
	var v: int = int(a.get("v", 0))
	_log("%s 的 %s 使出「%s」！" % [names[pi], bd.name, a.name])
	var dmg: int = a.dmg
	if fx == "flip_plus":
		var heads := _flip()
		if heads:
			dmg += v
	if fx == "energy_plus":
		dmg += v * clampi(b.energy.size() - a.cost.size(), 0, 2)
	var weak := false
	if dmg > 0:
		dmg += p.band
		if is_weak_to(d, b):
			dmg *= 2
			weak = true
	events.append({"e": "attack", "p": pi, "type": bd.type, "dmg": dmg, "weak": weak})
	if dmg > 0:
		d.dmg += dmg
		_log("造成 %d 點傷害%s" % [dmg, "（屬性相剋，加倍！）" if weak else "。"])
	match fx:
		"burn":
			d.status = "burn"
			d.para_turn = -1
			_log("%s 被灼傷了！" % beast_data(d).name)
			events.append({"e": "burn", "p": 1 - pi})
		"para":
			_paralyze(1 - pi, d)
		"para_flip":
			if _flip():
				_paralyze(1 - pi, d)
		"heal":
			_heal(pi, b, v)
		"bench":
			for eb in o.bench:
				eb.dmg += v
			if not o.bench.is_empty():
				_log("對手的後備靈獸各受到 %d 點傷害。" % v)
		"snipe":
			var tgt = null
			for eb in o.bench:
				if tgt == null or hp_left(eb) < hp_left(tgt):
					tgt = eb
			if tgt != null:
				tgt.dmg += v
				_log("%s 受到 %d 點傷害。" % [beast_data(tgt).name, v])
		"recoil":
			b.dmg += v
			_log("%s 自己也受到 %d 點反作用傷害。" % [bd.name, v])
		"self_discard":
			for i in mini(v, b.energy.size()):
				p.discard.append(b.energy.pop_back())
			_log("%s 丟棄了 %d 個能量。" % [bd.name, v])
		"power_up":
			var i := _deck_find(pi, "e_" + bd.type)
			if i >= 0 and not p.bench.is_empty():
				var target: Dictionary = p.bench[0]
				for eb in p.bench:
					if beast_data(eb).type == bd.type:
						target = eb
						break
				target.energy.append(p.deck[i])
				p.deck.remove_at(i)
				_shuffle(p.deck)
				_log("從牌組找到能量，附加給 %s。" % beast_data(target).name)
				events.append({"e": "energy", "p": pi, "slot": p.bench.find(target) + 1})
		"draw":
			_draw(pi, v)
	_check_kos(pi)
	if winner >= 0:
		return
	if pending.is_empty():
		_end_turn()
	else:
		end_after_pending = true


func _paralyze(owner: int, d: Dictionary) -> void:
	d.status = "para"
	d.para_turn = turn
	_log("%s 麻痺了，下回合不能攻擊和撤退！" % beast_data(d).name)
	events.append({"e": "para", "p": owner})


func _heal(pi: int, b: Dictionary, v: int) -> void:
	var h := mini(v, b.dmg)
	b.dmg -= h
	if h > 0:
		_log("%s 回復了 %d HP。" % [beast_data(b).name, h])
		events.append({"e": "heal", "p": pi})


func _flip() -> bool:
	var heads := rng.randi_range(0, 1) == 1
	_log("擲硬幣……%s！" % ("正面" if heads else "反面"))
	events.append({"e": "coin", "heads": heads})
	return heads


## 檢查雙方被擊倒的靈獸；attacker 是這次行動的玩家（同時達成條件時算他贏）
func _check_kos(attacker: int) -> void:
	for pi in [1 - attacker, attacker]:
		var p: Dictionary = players[pi]
		var dead: Array = []
		if p.active != null and hp_left(p.active) <= 0:
			dead.append(p.active)
			p.active = null
		for b in p.bench.duplicate():
			if hp_left(b) <= 0:
				dead.append(b)
				p.bench.erase(b)
		for b in dead:
			_log("%s 的 %s 被擊倒了！" % [names[pi], beast_data(b).name])
			events.append({"e": "ko", "p": pi})
			p.discard.append(b.uid)
			p.discard += b.stack
			p.discard += b.energy
			players[1 - pi].stars += 1
			events.append({"e": "star", "p": 1 - pi})
	for pi in [attacker, 1 - attacker]:
		if players[pi].stars >= CardDB.STARS_TO_WIN:
			_win(pi, "拿到 %d 顆星徽" % CardDB.STARS_TO_WIN)
			return
	for pi in [1 - attacker, attacker]:
		var p: Dictionary = players[pi]
		if p.active == null and p.bench.is_empty():
			_win(1 - pi, "%s 場上沒有靈獸了" % names[pi])
			return
	for pi in [1 - attacker, attacker]:
		if players[pi].active == null:
			pending.append({"p": pi, "kind": "promote"})


func _win(pi: int, why: String) -> void:
	winner = pi
	win_reason = why
	pending.clear()
	_log("★ %s 獲勝！（%s）" % [names[pi], why])
	events.append({"e": "win", "p": pi})


func _start_turn() -> void:
	var p: Dictionary = players[current]
	p.energy_used = false
	p.support_used = false
	p.retreat_used = false
	p.band = 0
	events.append({"e": "turn", "p": current})
	_log("—— 第 %d 回合：%s ——" % [turn, names[current]])
	if p.deck.is_empty():
		_win(1 - current, "%s 的牌組抽光了" % names[current])
		return
	_draw(current, 1)
	var b = p.active
	if b != null and b.status == "burn":
		b.dmg += 10
		_log("%s 因灼傷受到 10 點傷害。" % beast_data(b).name)
		events.append({"e": "burn", "p": current})
		_check_kos(1 - current)


func _end_turn() -> void:
	# 麻痺只持續到「被麻痺那方」的下一個回合結束
	var p: Dictionary = players[current]
	for b in [p.active] + p.bench:
		if b != null and b.status == "para" and b.para_turn < turn:
			b.status = ""
	current = 1 - current
	turn += 1
	_start_turn()


func _draw(pi: int, n: int) -> void:
	var p: Dictionary = players[pi]
	for i in n:
		if p.deck.is_empty():
			return
		p.hand.append(p.deck.pop_back())
	events.append({"e": "draw", "p": pi, "n": n})


func _deck_find(pi: int, what: String) -> int:
	var deck: Array = players[pi].deck
	for i in range(deck.size() - 1, -1, -1):
		var id: String = cards[deck[i]]
		if what == "energy" and CardDB.is_energy(id):
			return i
		if what == "basic" and CardDB.is_beast(id) and CardDB.BEASTS[id].stage == 0:
			return i
		if id == what:
			return i
	return -1


func _hand_has_basic(pi: int) -> bool:
	for u in players[pi].hand:
		if CardDB.is_beast(cards[u]) and CardDB.BEASTS[cards[u]].stage == 0:
			return true
	return false


func _new_beast(uid: int) -> Dictionary:
	return {"uid": uid, "stack": [], "energy": [], "dmg": 0, "status": "", "para_turn": -1, "turn_played": turn}


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _log(s: String) -> void:
	log_lines.append(s)


# ---------- 存檔／重播 ----------

func to_save() -> Dictionary:
	return {"seed": seed_value, "decks": decks, "names": names, "history": history}


static func from_save(d: Dictionary) -> Battle:
	var b := Battle.new()
	b.setup(int(d.seed), d.decks[0], d.decks[1], str(d.names[0]), str(d.names[1]))
	for a in d.history:
		if not b.apply(a):
			push_warning("重播動作失敗：%s" % str(a))
			break
	b.events = []
	return b
