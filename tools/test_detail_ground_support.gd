extends SceneTree
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Detail=preload("res://scripts/ember_detail_scatter.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var policy:=Policy.new();policy.detail_prepare_m=30
	var missing:=0;var examples:Array=[];var within_capacity:=true
	for az in [0.1,1.9,2.45,3.8]:
		for ax in [0.1,1.9,2.45,3.8]:
			policy.anchor=Vector2(64+ax,64+az)*16
			var tiles:=policy.ground_candidates(Vector2i(2048,2048),64,384*64*64,{}, {})
			within_capacity=within_capacity and tiles.size()<=384
			var centre:=Vector2i(policy.anchor/64)
			for z in range(centre.y-10,centre.y+11):
				for x in range(centre.x-10,centre.x+11):
					var area:=Rect2(Vector2(x*64,z*64),Vector2.ONE*Detail.PATCH_M*16).grow(0.35*16)
					if not policy.detail_resident(area,false):continue
					for tz in range(floori(area.position.y/64),floori(area.end.y/64)+1):
						for tx in range(floori(area.position.x/64),floori(area.end.x/64)+1):
							if tiles.has(Vector2i(tx,tz)):continue
							missing+=1
							if examples.size()<3:examples.append({"anchor":str(policy.anchor),"patch":str(Vector2i(x,z)),"missing_tile":str(Vector2i(tx,tz))})
	var passed:=missing==0 and within_capacity
	print("DETAIL_GROUND_SUPPORT ",JSON.stringify({"pass":passed,"missing_corners":missing,"capacity_preserved":within_capacity,"examples":examples}))
	quit(0 if passed else 1)
