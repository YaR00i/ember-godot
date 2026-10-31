extends SceneTree
class ProjectionProbe extends "res://scripts/prototypes/ember_terrain_pilot_projection.gd":
	func _editor_residency_allowed()->bool:return true
class Waiter extends Node:
	var _detail_priority_pending:=false
	func work(context:RefCounted):await context.wait_for_turn(self)
func _initialize():run.call_deferred()
func run():
	var projection:=ProjectionProbe.new();projection._detail_observer_valid=true
	projection._pending_tile_columns=8;projection._pending_tile_rows=8
	projection._pending_flags.resize(64);projection._pending_flags.fill(0)
	projection.detail_policy.anchor=Vector2(256,256)
	var initial:int=projection._publication_budget_us()
	var tile:=Node3D.new()
	for z in range(2,6):
		for x in range(2,6):projection._tiles[Vector2i(x,z)]=tile
	projection._pending_flags[0]=1 # Distant work must not monopolize the frame.
	var no_grass:int=projection._publication_budget_us()
	var context=preload("res://scripts/ember_detail_preparation.gd").for_projection(projection)
	var waiter:=Waiter.new();waiter.work(context)
	var ready:int=projection._publication_budget_us()
	projection._pending_flags[3+3*8]=1
	var missing:int=projection._publication_budget_us()
	var passed:=initial==8000 and no_grass==8000 and ready==4000 and missing==8000
	print("GROUND_FOREGROUND_BUDGET ",JSON.stringify({"pass":passed,"initial":initial,"no_grass":no_grass,"foreground_ready":ready,"foreground_missing":missing}))
	preload("res://scripts/ember_detail_preparation.gd").release_projection(projection);waiter.free()
	projection.free();tile.free();quit(0 if passed else 1)
