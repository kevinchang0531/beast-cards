class_name FilePick
extends Node
## 選圖片檔：網頁版用瀏覽器的檔案選擇器（手機可選相簿），電腦版用 FileDialog。
## 用法：FilePick.pick(host, multiple, func(images: Array): ...)；images 是 Image 陣列，取消就不會回呼。
## 網頁版先用 canvas 把圖縮到短邊 512 再傳進來，瀏覽器能開的格式（含 iPhone 的 HEIC）都能匯入。
## 批次匯入：FilePick.pick_folder(host, func(files: Dictionary): ...)；files = {jsons: {檔名: 內容}, images: {檔名: 路徑或 Image}}。

const JS := """
window.__bcB64 = async function (f) {
  var bmp = await createImageBitmap(f);
  var k = Math.min(1, 512 / Math.min(bmp.width, bmp.height));
  var c = document.createElement('canvas');
  c.width = Math.round(bmp.width * k);
  c.height = Math.round(bmp.height * k);
  c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
  return c.toDataURL('image/png').split(',')[1];
};
window.__bcPick = function (multiple, cb) {
  var input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/*';
  input.multiple = multiple;
  window.__bcOpen(input, '點這裡選擇圖片', async function () {
    for (var f of input.files) {
      try {
        cb(await window.__bcB64(f));
      } catch (e) { console.warn('無法讀取圖片', f.name, e); }
    }
    cb('');
  });
};
// 電腦選資料夾；手機不支援，改成一次選 JSON 和圖片檔。只讀 JSON 有提到的圖片
window.__bcPickFolder = function (cb) {
  var input = document.createElement('input');
  input.type = 'file';
  input.multiple = true;
  if (!/Android|iPad|iPhone|iPod/.test(navigator.userAgent) && navigator.maxTouchPoints <= 1) input.webkitdirectory = true;
  window.__bcOpen(input, '點這裡選擇 JSON 和圖片', async function () {
    var want = new Set();
    for (var f of input.files) {
      if (!f.name.toLowerCase().endsWith('.json')) continue;
      var text = await f.text();
      cb('json', f.name, text);
      try {
        for (var c of JSON.parse(text)) want.add(String(c.imageUrl).split('/').pop());
      } catch (e) { console.warn('JSON 格式不對', f.name, e); }
    }
    for (var f of input.files) {
      if (!want.has(f.name)) continue;
      try {
        cb('image', f.name, await window.__bcB64(f));
      } catch (e) { console.warn('無法讀取圖片', f.name, e); }
    }
    cb('done', '', '');
  });
};
window.__bcOpen = function (input, text, onchange) {
  input.style.display = 'none';
  document.body.appendChild(input);
  var shade = null;
  input.addEventListener('change', async function () {
    if (shade) shade.remove();
    await onchange();
    input.remove();
  });
  // iPhone／iPad 只接受使用者直接點到的檔案按鈕，所以多顯示一層網頁按鈕
  if (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) {
    shade = document.createElement('div');
    shade.style.cssText = 'position:fixed;inset:0;z-index:99;background:rgba(0,0,0,.7);display:flex;gap:20px;align-items:center;justify-content:center';
    var label = document.createElement('label');
    label.textContent = text;
    label.style.cssText = 'padding:18px 30px;border-radius:12px;background:#ffd84a;color:#1a1a1a;font:bold 22px sans-serif';
    label.appendChild(input);
    var close = document.createElement('button');
    close.textContent = '取消';
    close.style.cssText = 'padding:18px 30px;border-radius:12px;border:0;font:22px sans-serif';
    close.onclick = function () { shade.remove(); };
    shade.append(label, close);
    document.body.appendChild(shade);
  } else {
    input.click();
  }
};
"""

var done: Callable
var images: Array = []
var files := {"jsons": {}, "images": {}}
var js_cb


static func pick_folder(host: Node, cb: Callable) -> void:
	var p := FilePick.new()
	p.done = cb
	host.add_child(p)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS, true)
		p.js_cb = JavaScriptBridge.create_callback(p._on_web_folder)
		JavaScriptBridge.get_interface("window").__bcPickFolder(p.js_cb)
	else:
		var fd := FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.use_native_dialog = true
		p.add_child(fd)
		fd.dir_selected.connect(func(path):
			p.done.call(scan_dir(path))
			p.queue_free())
		fd.canceled.connect(p.queue_free)
		fd.popup_centered(Vector2i(900, 600))


## 掃整個資料夾（含子資料夾）的 JSON 和圖片；圖片先只記路徑，用到才讀
static func scan_dir(path: String, out := {"jsons": {}, "images": {}}) -> Dictionary:
	for f in DirAccess.get_files_at(path):
		if f.get_extension().to_lower() == "json":
			out.jsons[f] = FileAccess.get_file_as_string("%s/%s" % [path, f])
		elif f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			out.images[f] = "%s/%s" % [path, f]
	for d in DirAccess.get_directories_at(path):
		scan_dir("%s/%s" % [path, d], out)
	return out


func _on_web_folder(args: Array) -> void:
	match str(args[0]):
		"json":
			files.jsons[str(args[1])] = str(args[2])
		"image":
			var img := Image.new()
			if img.load_png_from_buffer(Marshalls.base64_to_raw(str(args[2]))) == OK:
				files.images[str(args[1])] = img
		"done":
			done.call(files)
			queue_free()


static func pick(host: Node, multiple: bool, cb: Callable) -> void:
	var p := FilePick.new()
	p.done = cb
	host.add_child(p)
	if OS.has_feature("web"):
		p._pick_web(multiple)
	else:
		p._pick_desktop(multiple)


func _pick_web(multiple: bool) -> void:
	JavaScriptBridge.eval(JS, true)
	js_cb = JavaScriptBridge.create_callback(_on_web_file)
	JavaScriptBridge.get_interface("window").__bcPick(multiple, js_cb)


func _on_web_file(args: Array) -> void:
	var b64 := str(args[0])
	if b64 != "":
		var img := Image.new()
		if img.load_png_from_buffer(Marshalls.base64_to_raw(b64)) == OK:
			images.append(img)
		return
	_finish()


func _pick_desktop(multiple: bool) -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES if multiple else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;圖片"])
	fd.use_native_dialog = true
	add_child(fd)
	var load_paths := func(paths: PackedStringArray):
		for path in paths:
			var img := Image.load_from_file(path)
			if img:
				images.append(img)
		_finish()
	fd.files_selected.connect(load_paths)
	fd.file_selected.connect(func(path): load_paths.call(PackedStringArray([path])))
	fd.canceled.connect(queue_free)
	fd.popup_centered(Vector2i(900, 600))


func _finish() -> void:
	if not images.is_empty():
		done.call(images)
	queue_free()
