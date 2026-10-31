extends Node
## 線上對戰連線：用 Firestore REST API 當「動作信箱」（不需登入，網頁版和電腦版都能用）。
## 設定在 res://config/online.cfg（project_id、api_key），讀寫限制由 firebase/firestore.rules 把關。
##
## 流程：房主 create_room() 拿到 6 碼房號 → 對手 join_room() → 雙方用同一個種子各自開一份 Battle 引擎。
## 輪到誰行動，誰就把動作寫進 tcg_rooms/<房號>/actions/<0000 流水號>；另一方每秒讀下一號，讀到就照做。
## 引擎是確定性的，所以兩邊畫面一定同步。
## 全部 async 函式都用 await 呼叫；連不上時回傳空值。

const CFG := "res://config/online.cfg"
const TIMEOUT := 8.0
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var project := ""
var api_key := ""
var collection := "tcg_rooms"
var last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		project = str(cfg.get_value("firebase", "project_id", ""))
		api_key = str(cfg.get_value("firebase", "api_key", ""))


func enabled() -> bool:
	return project != "" and api_key != ""


func _base() -> String:
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % project


## 回傳 [狀態碼, 解析後的 JSON]；連不上時狀態碼為 0
func _call(method: int, url: String, body = null) -> Array:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	# 網頁版的回應已被瀏覽器解壓，Godot 再解一次會失敗
	req.accept_gzip = not OS.has_feature("web")
	add_child(req)
	var data := "" if body == null else JSON.stringify(body)
	var err := req.request(url, PackedStringArray(["Content-Type: application/json"]), method, data)
	if err != OK:
		req.queue_free()
		return [0, null]
	var res: Array = await req.request_completed
	req.queue_free()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null
	if res[1] != 200 and parsed is Dictionary and parsed.has("error"):
		last_error = str(parsed.error.get("message", ""))
	if res[1] != 200 and res[1] != 404:
		print("[連線] 方法 %d 結果 %d 狀態 %d %s" % [method, res[0], res[1], text.left(200)])
	return [res[1], parsed]


static func _s(v: String) -> Dictionary:
	return {"stringValue": v}


static func _i(v: int) -> Dictionary:
	return {"integerValue": str(v)}


static func _now() -> Dictionary:
	return {"timestampValue": Time.get_datetime_string_from_system(true) + "Z"}


static func _plain(fields: Dictionary) -> Dictionary:
	var out := {}
	for k in fields:
		var f: Dictionary = fields[k]
		if f.has("stringValue"):
			out[k] = f.stringValue
		elif f.has("integerValue"):
			out[k] = int(f.integerValue)
		else:
			out[k] = f.values()[0]
	return out


func new_code() -> String:
	var s := ""
	for i in 6:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


## 開房間；成功回傳 {code, seed}，失敗回傳空 Dictionary
func create_room(pname: String, deck: Array) -> Dictionary:
	if not enabled():
		return {}
	for attempt in 4:
		var code := new_code()
		var seed_v := randi() % 2000000000
		var fields := {"host": _s(pname), "host_deck": _s(",".join(deck)), "guest": _s(""), "guest_deck": _s(""),
			"seed": _i(seed_v), "status": _s("wait"), "created": _now()}
		var r: Array = await _call(HTTPClient.METHOD_POST, "%s/%s?documentId=%s&key=%s" % [_base(), collection, code, api_key],
			{"fields": fields})
		if r[0] == 200:
			return {"code": code, "seed": seed_v}
		if r[0] != 409:   # 409 = 房號撞到，換一個再試
			return {}
	return {}


## 讀房間資料：{host, host_deck, guest, guest_deck, seed, status}；找不到回傳空 Dictionary
func get_room(code: String) -> Dictionary:
	if not enabled():
		return {}
	var r: Array = await _call(HTTPClient.METHOD_GET, "%s/%s/%s?key=%s" % [_base(), collection, code, api_key])
	if r[0] != 200 or not (r[1] is Dictionary):
		return {}
	return _plain(r[1].get("fields", {}))


## 加入房間；成功回傳房間資料，失敗回傳 {error: 原因}
func join_room(code: String, pname: String, deck: Array) -> Dictionary:
	if not enabled():
		return {"error": "沒有線上設定"}
	var room := await get_room(code)
	if room.is_empty():
		return {"error": "找不到這個房號"}
	if str(room.get("guest", "")) != "":
		return {"error": "這個房間已經有人了"}
	var url := "%s/%s/%s?key=%s&updateMask.fieldPaths=guest&updateMask.fieldPaths=guest_deck&updateMask.fieldPaths=status" % [
		_base(), collection, code, api_key]
	var fields := {"guest": _s(pname), "guest_deck": _s(",".join(deck)), "status": _s("play")}
	var r: Array = await _call(HTTPClient.METHOD_PATCH, url, {"fields": fields})
	if r[0] != 200:
		return {"error": "加入失敗（%d）" % r[0]}
	room.guest = pname
	room.guest_deck = ",".join(deck)
	room.status = "play"
	return room


## 寫入第 idx 個動作
func send_action(code: String, idx: int, by: int, a: Dictionary) -> bool:
	if not enabled():
		return false
	var fields := {"by": _i(by), "a": _s(JSON.stringify(a))}
	var url := "%s/%s/%s/actions?documentId=%04d&key=%s" % [_base(), collection, code, idx, api_key]
	for attempt in 3:
		var r: Array = await _call(HTTPClient.METHOD_POST, url, {"fields": fields})
		if r[0] == 200 or r[0] == 409:
			return true
	return false


## 讀第 idx 個動作；還沒有回傳空 Dictionary，有的話回傳 {by, a}
func get_action(code: String, idx: int) -> Dictionary:
	if not enabled():
		return {}
	var r: Array = await _call(HTTPClient.METHOD_GET, "%s/%s/%s/actions/%04d?key=%s" % [_base(), collection, code, idx, api_key])
	if r[0] != 200 or not (r[1] is Dictionary):
		return {}
	var f := _plain(r[1].get("fields", {}))
	var a = JSON.parse_string(str(f.get("a", "")))
	if not (a is Dictionary):
		return {}
	return {"by": int(f.get("by", -1)), "a": a}
