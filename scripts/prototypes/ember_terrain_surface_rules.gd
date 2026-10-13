extends RefCounted
## Sparse source-space rules. No editor selection or derived mesh indices.
const TILE:=64
const BYTES:=TILE*TILE

static func round_code(strength: float,radius: int) -> int:
	return 1+(clampi(radius,1,3)-1)*32+roundi(clampf(strength,0,1)*31)
static func protect_code(strength: float) -> int:
	return 127+clampi(roundi(strength*128),1,128)
static func read(rules: Dictionary,cell: Vector2i) -> int:
	if cell.x<0 or cell.y<0:return 0
	var key:=cell/TILE
	if not rules.has(key):return 0
	var bytes: PackedByteArray=rules[key]
	return bytes[cell.x%TILE+(cell.y%TILE)*TILE]
static func changed(rules: Dictionary,cells: Dictionary) -> Dictionary:
	var result:=rules.duplicate();var groups: Dictionary={}
	for cell: Vector2i in cells:
		var key:=cell/TILE
		if not groups.has(key):groups[key]=[]
		groups[key].append(Vector2i(cell.x%TILE+(cell.y%TILE)*TILE,int(cells[cell])))
	for key: Vector2i in groups:
		var bytes: PackedByteArray=rules.get(key,PackedByteArray()).duplicate()
		if bytes.is_empty():bytes.resize(BYTES)
		for item: Vector2i in groups[key]:bytes[item.x]=item.y
		if bytes.count(0)==BYTES:result.erase(key)
		else:result[key]=bytes
	return result
static func window(rules: Dictionary,bounds: Rect2i) -> Dictionary:
	var cells: Dictionary={}
	for key: Vector2i in rules:
		var area:=Rect2i(key*TILE,Vector2i(TILE,TILE)).intersection(bounds)
		if not area.has_area():continue
		var bytes: PackedByteArray=rules[key]
		for z in range(area.position.y,area.end.y):
			for x in range(area.position.x,area.end.x):
				var value:=int(bytes[x%TILE+(z%TILE)*TILE])
				if value>0:cells[Vector2i(x,z)-bounds.position]=value
	return changed({},cells)
static func shifted(rules: Dictionary,offset: Vector2i) -> Dictionary:
	if offset.x%TILE==0 and offset.y%TILE==0:
		var result: Dictionary={}
		for key: Vector2i in rules:result[key+offset/TILE]=rules[key]
		return result
	var cells: Dictionary={}
	for key: Vector2i in rules:
		var bytes: PackedByteArray=rules[key]
		for i in BYTES:
			if bytes[i]>0:cells[key*TILE+Vector2i(i%TILE,i/TILE)+offset]=int(bytes[i])
	return changed({},cells)
static func validation_errors(source) -> Array[String]:
	var errors: Array[String]=[]
	var rules: Dictionary=source.surface_rules
	if rules.size()>132*132:return ["Слишком много плиток правил формы."]
	for key in rules:
		if not key is Vector2i or key.x<0 or key.y<0 or key.x*TILE>=source.width or key.y*TILE>=source.depth or not rules[key] is PackedByteArray or rules[key].size()!=BYTES:
			return ["Повреждена плитка правил формы."]
		var bytes: PackedByteArray=rules[key]
		for i in BYTES:
			if bytes[i]==0:continue
			if bytes[i]>96 and bytes[i]<128:return ["Неизвестное правило формы."]
			var cell: Vector2i=key*TILE+Vector2i(i%TILE,i/TILE)
			if not source.has_column(cell.x,cell.y):return ["Правило формы вне исходной земли."]
	return errors
