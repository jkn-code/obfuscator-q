extends Node

var root_dir: String
var targets := []
var gd_files

@onready var label: Label = %"Log lbl"

# 📁 Папки и файлы, которые скрипт полностью пропускает
@onready var ignore_dirs = get_list(%"Ignore dirs edt")
@onready var ignore_files = get_list(%"Ignore files edt")
@onready var ignore_names = get_list(%"Ignode names edt")



func _ready() -> void:
	print(ignore_names)
	ignore_files.append("obfuscator_q.gd")
	label.text = ""
	_execute()


func _on_start_btn_pressed() -> void:
	go_obf()


func _execute() -> void:
	_print("🔍 Запуск обфускатора...")
	_print("⚠️ Сделайте резервную копию проекта перед запуском!")
	
	#var root_dir = "res://"
	root_dir = OS.get_executable_path().get_base_dir()
	_print("📂 "+ root_dir)
	gd_files = _scan_files(root_dir)
	
	if gd_files.is_empty():
		_print("⚠️ Файлы .gd не найдены.")
		return
	_print("📂 Найдено файлов: %d" % gd_files.size())

	# 1. Сбор @export имён (глобальный игнор)
	var export_names := _collect_exports(gd_files)
	_print("🔒 @export переменных (игнор): %d" % export_names.size())

	# 2. Сбор объявлений (var, func, аргументы)
	var all_decls := _collect_declarations(gd_files, export_names)

	# 3. Фильтрация: только имена, начинающиеся с маленькой английской буквы
	targets = []
	for name in all_decls:
		if name.length() > 0:
			var first: String = name[0]
			if first >= "a" and first <= "z" and not name.begins_with("_"):
				targets.append(name)

	_print("🎯 К обфускации: %d имён" % targets.size())
	if targets.is_empty():
		_print("✅ Нечего заменять. Завершение.")
		return



func go_obf():
	# 4. Генерация карты замен
	var mapping := _generate_mapping(targets)
	
	# 5. Сохранение карты
	var obfuscator_q_map = "obfuscator_q_map.txt"
	var map_path = root_dir.path_join(obfuscator_q_map)
	_save_mapping(map_path, mapping)
	_print("💾 Карта замен сохранена: %s" % obfuscator_q_map)
	
	# 6. Применение замен
	var changed_count := 0
	for file_path in gd_files:
		var content := _read_file(file_path)
		if content.is_empty(): continue
		
		var new_content := _replace_outside_strings(content, mapping)
		if new_content != content:
			_write_file(file_path, new_content)
			changed_count += 1
			
	_print("✅ Готово. Изменено файлов: %d" % changed_count)










# ========================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ========================================
func _scan_files(path: String) -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(path)
	if not dir: return files
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name in ignore_dirs:
				files.append_array(_scan_files(path.path_join(file_name)))
		else:
			if file_name.ends_with(".gd") and not file_name in ignore_files:
				var rel_path := path.replace("res://", "")
				var skip := false
				for ign in ignore_dirs:
					if rel_path.contains(ign): skip = true; break
				if not skip:
					files.append(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	return files

func _collect_exports(files: PackedStringArray) -> Dictionary:
	var exports := {}
	var re := RegEx.new()
	re.compile("@export(?:\\([^)]*\\))?\\s+var\\s+([a-z_][a-zA-Z0-9_]*)")
	
	for f in files:
		var content := _read_file(f)
		for match in re.search_all(content):
			exports[match.get_string(1)] = true
	return exports

func _collect_declarations(files: PackedStringArray, ignore_map: Dictionary) -> Dictionary:
	var decls := {}
	#ignore_map += ignore_names
	#_print("ignore_map="+ str(ignore_map))
	for nm in ignore_names:
		ignore_map[nm] = true
	#print(ignore_map)
	
	var re_var := RegEx.new(); re_var.compile("\\bvar\\s+([a-z_][a-zA-Z0-9_]*)")
	var re_func := RegEx.new(); re_func.compile("\\bfunc\\s+([a-z_][a-zA-Z0-9_]*)\\s*\\(")
	var re_func_args := RegEx.new(); re_func_args.compile("\\bfunc\\s+[a-zA-Z_][a-zA-Z0-9_]*\\s*\\(([^)]*)\\)")
	#var re_class_names := RegEx.new(); re_var.compile("\\bre_class_names\\s+([a-z_][a-zA-Z0-9_]*)")
	var re_class := RegEx.new(); re_class.compile("\\bclass_name\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
	
	for f in files:
		var content := _read_file(f)
		# ✅ УДАЛЯЕМ строки и комменты для безопасного парсинга объявлений
		var clean := _strip_strings_and_comments(content)
		
		for m in re_var.search_all(clean):
			var n := m.get_string(1)
			if not ignore_map.has(n): decls[n] = true
			
		for m in re_func.search_all(clean):
			var n := m.get_string(1)
			if not ignore_map.has(n): decls[n] = true
			#decls[n] = true
			
		for m in re_class.search_all(clean):
			var n := m.get_string(1)
			if not ignore_map.has(n): decls[n] = true
			
		for m in re_func_args.search_all(clean):
			var args_str := m.get_string(1)
			var parts := args_str.split(",", false)
			for p in parts:
				p = p.strip_edges()
				if p.is_empty(): continue
				var arg_name := p.split(":")[0].split("=")[0].strip_edges()
				if arg_name.length() > 0 and arg_name[0] >= 'a' and arg_name[0] <= 'z' and not arg_name.begins_with("_"):
					if not ignore_map.has(arg_name):
						decls[arg_name] = true
	return decls

# ✅ ДОБАВЛЕННАЯ ФУНКЦИЯ: убирает строки и комментарии для парсинга
func _strip_strings_and_comments(content: String) -> String:
	var out := ""
	var i := 0
	var n := content.length()
	while i < n:
		var c := content[i]
		# Комментарии
		if c == '#':
			while i < n and content[i] != '\n': i += 1
			out += " "
			continue
		# Строки
		if c == '"' or c == "'":
			var q := c
			i += 1
			while i < n:
				if content[i] == '\\': i += 2; continue
				if content[i] == q: i += 1; break
				i += 1
			out += " "
			continue
		out += c
		i += 1
	return out

func _generate_mapping(names: Array) -> Dictionary:
	var map := {}
	var used := {}
	for name in names:
		while true:
			var new_name := "_%d" % randi_range(1000, 9999)
			if not used.has(new_name):
				used[new_name] = true
				map[name] = new_name
				break
	return map

func _replace_outside_strings(content: String, mapping: Dictionary) -> String:
	if mapping.is_empty(): return content
	var out := ""
	var i := 0
	var len := content.length()
	
	while i < len:
		var c := content[i]
		
		# Комментарии
		if c == '#':
			out += c; i += 1
			while i < len and content[i] != '\n': out += content[i]; i += 1
			continue
			
		# Строки (пропускаем полностью)
		if c == '"' or c == "'":
			var quote := c
			var start := i
			i += 1
			while i < len:
				if content[i] == '\\':
					i += 2
				elif content[i] == quote:
					i += 1
					break
				else: i += 1
			out += content.substr(start, i - start)
			continue
			
		# Слова (✅ исправлено: убран несуществующий .is_digit())
		if c.is_valid_identifier() or c == '_':
			var start := i
			while i < len and content[i].is_valid_identifier():
				i += 1
			var word := content.substr(start, i - start)
			if mapping.has(word):
				out += mapping[word]
			else:
				out += word
			continue
			
		out += c
		i += 1
	return out
	
# ========================================
# ФАЙЛОВЫЕ ОПЕРАЦИИ
# ========================================
func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f: return ""
	return f.get_as_text()

func _write_file(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(content)

func _save_mapping(path: String, mapping: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: return
	
	var keys := mapping.keys()
	keys.sort()  # ✅ Сортируем массив на месте
	
	for key in keys:
		f.store_string("%s = %s\n" % [key, mapping[key]])
	f.close()


func _print(txt: String):
	label.text += txt +"\n"

func get_list(edt: TextEdit):
	var res := []
	for tx in edt.text.split(","):
		if tx.strip_edges() != "":
			res.append(tx.strip_edges())
	return res



			
