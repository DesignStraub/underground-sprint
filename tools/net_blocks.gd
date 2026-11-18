extends Node
## Werkzeug zu tools/osm_net.py: Sperrflächen für das Straßennetz einer Stadt als JSON (Streckenkoordinaten x, z):
## Korridore der Ausfahrten (dort führt die Auffahrt weiter), Wahrzeichen, Hügel, Gleise; dazu die Mittellinie.
## godot --headless --path . res://tools/net_blocks.tscn -- --race=15 --out=/pfad/aachen_blocks.json

const Track := preload("res://scripts/track_builder.gd")
const Layout := preload("res://scripts/world_layout.gd")
const Streets := preload("res://scripts/street_net.gd")


func _ready() -> void:
	var ri := 0
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			ri = int(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
	var race := Layout.world_race(ri)
	var job := Track.begin(race)
	var tr: Dictionary = job["track"]
	(job["root"] as Node).free()
	var ctx := Streets._ctx(tr, race)
	var res := {"caps": [], "circles": [], "main": []}
	for cp in ctx["caps"]:
		res["caps"].append([cp[0].x, cp[0].y, cp[1].x, cp[1].y, cp[2]])
	for c in ctx["circles"]:
		res["circles"].append([c[0].x, c[0].y, c[1], c[2]])
	var mp: PackedVector2Array = ctx["mp"]
	for q in mp:
		res["main"].append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("SPERR %d Korridore, %d Kreise, %d Punkte -> %s" % [res["caps"].size(), res["circles"].size(), res["main"].size(), out])
	get_tree().quit()
