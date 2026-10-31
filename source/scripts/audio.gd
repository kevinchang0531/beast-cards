extends Node
## 音效與背景音樂管理：play(名稱) 播音效（同一音效最短間隔 0.06 秒）、bgm(名稱) 換音樂、toggle_mute() 靜音。
## 音檔由 tools/make_audio.py 程式合成，放在 assets/audio/。

const SFX := ["click", "draw", "play", "energy", "evolve", "atk_fire", "atk_water", "atk_leaf", "atk_thunder", "atk_rock",
	"atk_normal", "hit", "ko", "heal", "coin", "shuffle", "pack", "rare", "turn", "burn", "paralyze", "buy", "error",
	"win", "lose", "star"]

var muted := false
var _streams := {}
var _pool: Array = []
var _last := {}
var _bgm: AudioStreamPlayer
var _bgm_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in SFX:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -8.0
	add_child(_bgm)


func play(n: String, volume_db: float = 0.0) -> void:
	if muted or not _streams.has(n):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(n, -1000)) < 60:
		return
	_last[n] = now
	for p in _pool:
		if not p.playing:
			p.stream = _streams[n]
			p.volume_db = volume_db
			p.play()
			return


func bgm(n: String) -> void:
	if n == _bgm_name:
		return
	_bgm_name = n
	_bgm.stop()
	if n == "":
		return
	var path := "res://assets/audio/%s.wav" % n
	if not ResourceLoader.exists(path):
		return
	var s: AudioStreamWAV = load(path)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_bgm.stream = s
	if not muted:
		_bgm.play()


func toggle_mute() -> bool:
	muted = not muted
	if muted:
		_bgm.stop()
	elif _bgm.stream != null:
		_bgm.play()
	return muted
