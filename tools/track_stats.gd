extends Node
## Werkzeug: baut alle Strecken und gibt Kennzahlen aus (Länge, Abkürzungen, Bahnübergang, Knotenanzahl).

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")


func _ready() -> void:
	for r in Catalog.RACES:
		var t0 := Time.get_ticks_msec()
		var t := Track.build(r)
		var kinds := []
		for p in t["paths"]:
			if p["id"] != 0:
				kinds.append("%s(%.0fm, spart %.0fm)" % [p["kind"], p["length"], (p["to"] - p["from"]) - p["length"]])
		print("%s: %.0f m, Kreuzung bei %.0f, %d Knoten, %d ms" % [r["name"], t["length"], t["crossing_d"],
			_count(t["node"]), Time.get_ticks_msec() - t0])
		print("   ", ", ".join(kinds))
		var tun := []
		for x in t["tunnels"]:
			tun.append("%s %.0f-%.0f" % [x["name"], x["from"], x["to"]])
		var el := []
		for x in t["el"]:
			el.append("%.0f-%.0f" % [x["from"], x["to"]])
		print("   Viertel: ", " > ".join(t["districts"]))
		print("   Tunnel: ", tun, "  Hochbahn: ", el, "  Stadion: %.0f  Masten: %d" % [t["stadium_d"], t["posts"].size()])
		t["node"].free()
	get_tree().quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
