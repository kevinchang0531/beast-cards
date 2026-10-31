class_name BattleAI
extends RefCounted
## 電腦對手：每次呼叫 choose() 回傳「下一個動作」，直到攻擊或結束回合。
## level 0 簡單（偶爾亂附能量、不撤退、不用頭帶）～ 3 冠軍（會算擊倒、相剋、撤退）。


static func choose(b: Battle, pi: int, level: int, rng: RandomNumberGenerator) -> Dictionary:
	var acts := b.legal_actions(pi)
	if acts.is_empty():
		return {}
	var p: Dictionary = b.players[pi]
	var o: Dictionary = b.players[1 - pi]
	var by := {}
	for a in acts:
		if not by.has(a.t):
			by[a.t] = []
		by[a.t].append(a)

	if by.has("promote"):
		var best = null
		var best_s := -9999.0
		for a in by.promote:
			var s := _beast_score(b, pi, p.bench[a.bench], o.active)
			if s > best_s:
				best_s = s
				best = a
		return best

	# 1. 進化（越早越好）
	if by.has("evolve"):
		var best = by.evolve[0]
		for a in by.evolve:
			if a.slot == 0:
				best = a
		return best
	# 2. 基礎靈獸上後備（留 1 格給之後抽到的）
	if by.has("basic") and (p.bench.size() < 3 or level == 0):
		return by.basic[0]
	# 3. 訓練家卡
	if by.has("trainer"):
		var t := _pick_trainer(b, pi, level, by.trainer, by.has("attack"))
		if not t.is_empty():
			return t
	# 4. 附加能量
	if by.has("attach"):
		if level == 0 and rng.randf() < 0.35:
			return by.attach[rng.randi_range(0, by.attach.size() - 1)]
		var best = null
		var best_s := -9999.0
		for a in by.attach:
			var s := _attach_score(b, pi, a)
			if s > best_s:
				best_s = s
				best = a
		if best != null and best_s > -100:
			return best
	# 5. 撤退
	if level >= 1 and by.has("retreat") and p.active != null and o.active != null:
		var cur := _beast_score(b, pi, p.active, o.active)
		for a in by.retreat:
			var s := _beast_score(b, pi, p.bench[a.bench], o.active)
			if s > cur + 40:
				return a
	# 6. 攻擊
	if by.has("attack"):
		var best = by.attack[0]
		var best_s := -1.0
		for a in by.attack:
			var dmg := b.preview_damage(pi, a.n)
			var atk: Dictionary = b.beast_data(p.active).attacks[a.n]
			var fx: String = atk.get("fx", "")
			var s := float(dmg)
			if fx == "flip_plus":
				s += atk.v * 0.5
			if fx in ["burn", "para", "para_flip", "heal", "bench", "snipe", "power_up"]:
				s += 12
			if fx == "self_discard" or fx == "recoil":
				s -= 8
			if level >= 2 and o.active != null and dmg >= b.hp_left(o.active):
				s += 200
				if fx == "self_discard" or fx == "recoil":
					s += 8
			if s > best_s:
				best_s = s
				best = a
		return best
	return by.end[0]


static func _pick_trainer(b: Battle, pi: int, level: int, list: Array, can_attack: bool) -> Dictionary:
	var p: Dictionary = b.players[pi]
	for a in list:
		var id := b.card_id(p.hand[a.hand])
		match CardDB.effect_of(id):
			"potion":
				var tgt = b.beast_at(pi, a.slot)
				if tgt.dmg >= 30:
					return a
			"bell":
				if p.active.status != "" or p.active.dmg >= 30:
					return a
			"finder":
				if not _hand_has(b, pi, "energy") and not p.energy_used:
					return a
			"scroll":
				if p.bench.size() < 2:
					return a
			"journal":
				if p.hand.size() <= 6:
					return a
			"notes":
				if p.hand.size() <= 3:
					return a
			"recycle":
				if not _hand_has(b, pi, "energy") and not p.energy_used:
					return a
			"band":
				if level >= 2 and can_attack:
					return a
			"whistle":
				if level >= 1 and b.players[1 - pi].active != null:
					var tgt = p.bench[a.slot - 1]
					var o = b.players[1 - pi].active
					if _beast_score(b, pi, tgt, o) > _beast_score(b, pi, p.active, o) + 50:
						return a
	return {}


static func _hand_has(b: Battle, pi: int, what: String) -> bool:
	for u in b.players[pi].hand:
		if what == "energy" and CardDB.is_energy(b.card_id(u)):
			return true
	return false


## 這隻靈獸現在上場有多好：能打的傷害、剩餘 HP、相剋
static func _beast_score(b: Battle, pi: int, x: Dictionary, opp) -> float:
	var s := float(b.hp_left(x)) * 0.5
	var have := b.energy_types(x)
	for atk in b.beast_data(x).attacks:
		if Battle.can_pay(have, atk.cost):
			s = maxf(s, b.hp_left(x) * 0.5 + atk.dmg)
	if x.status == "para":
		s -= 60
	if opp != null:
		if b.is_weak_to(x, opp):
			s -= 50
		if b.is_weak_to(opp, x):
			s += 40
	return s


## 能量附給誰：補到最強招式還缺的屬性，戰鬥位置優先
static func _attach_score(b: Battle, pi: int, a: Dictionary) -> float:
	var p: Dictionary = b.players[pi]
	var x: Dictionary = b.beast_at(pi, a.slot)
	var etype: String = CardDB.ENERGY[b.card_id(p.hand[a.hand])].type
	var have := b.energy_types(x)
	var bd := b.beast_data(x)
	var best := -200.0
	for atk in bd.attacks:
		var miss := Battle.missing(have, atk.cost)
		if miss.is_empty():
			continue
		if miss.has(etype) or miss.has("any"):
			var s: float = 50.0 + atk.dmg * 0.3 - miss.size() * 5
			best = maxf(best, s)
	# 進化線基礎靈獸：預先充能
	if best < -100 and bd.stage == 0 and bd.type == etype and have.size() < 3:
		best = 10.0
	if a.slot == 0:
		best += 15
	if bd.type == etype:
		best += 5
	return best
