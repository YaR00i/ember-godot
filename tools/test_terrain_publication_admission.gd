extends SceneTree
const Creation=preload("res://addons/ember_import/ember_compact_map_creation.gd")
class Probe extends EmberTerrainPilotProjection:
	var publications:Array=[]
	var publication_us:=0
	func _editor_residency_allowed()->bool:return true
	func _publish_overview(key:Vector2i,covered:Dictionary)->void:
		publications.append({"region":key,"covered":covered.duplicate(),"present":_tiles.keys()})
		_overview_dirty.erase(key)
		var until:=Time.get_ticks_usec()+publication_us
		while Time.get_ticks_usec()<until:pass
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("TERRAIN_ADMISSION_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var creator:=Creation.new();check(creator.prepare_sections("admission",2,1,24),"fixture source")
	var projection:=Probe.new();root.add_child(projection);projection.set_process(false)
	projection.document=creator.source;projection.ground_style=1;projection.smooth_column_limit=4096
	projection._reset_pending_flags()
	projection.detail_policy.anchor=Vector2(32,32)
	var region:=Vector2i(1,0);projection._overviews[region]={}
	var leaving:Array[Vector2i]=[Vector2i(6,0),Vector2i(7,0)]
	for key in leaving:projection._tiles[key]=projection._new_tile_host("Fine_%d"%key.x)
	projection._sync_ground_residency()
	check(projection.publications.is_empty(),"observer does not publish outside admission")
	check(projection._tiles.has(leaving[0]) and projection._tiles.has(leaving[1]),"old fine retained until overview can publish")
	projection._poll_overviews(Time.get_ticks_usec()-10000,1)
	check(projection.publications.is_empty(),"expired publication budget does no work")
	check(projection._tiles.has(leaving[0]),"expired budget preserves old surface and physics host")
	# Reverse direction before the queued region is processed. Keep the newly
	# wanted/protected tile, release only the one still outside current policy.
	projection._resident_tiles[leaving[0]]=true
	projection._poll_overviews(Time.get_ticks_usec(),1000000)
	check(projection.publications.size()==1,"coalesced region publishes once")
	if projection.publications.size()==1:
		var event:Dictionary=projection.publications[0]
		check(event.covered.has(leaving[0]) and not event.covered.has(leaving[1]),"current policy determines coverage after quick reversal")
		check(leaving[0] in event.present and leaving[1] in event.present,"overview restored before any fine host is removed")
	check(projection._tiles.has(leaving[0]) and not projection._tiles.has(leaving[1]),"only current departing host removed")
	# A source edit has invalidated the available overview. Do not replace the
	# newer fine surface with old overview data while its new job is pending.
	projection.publications.clear();projection._resident_tiles.clear()
	projection._overviews[region].revision=0;projection._overview_revision[region]=1
	projection._overview_dirty[region]=true
	projection._poll_overviews(Time.get_ticks_usec(),1000000)
	check(projection._tiles.has(leaving[0]),"stale overview cannot retire newer fine surface")
	projection._overviews[region].revision=1;projection._overview_dirty[region]=true
	projection._poll_overviews(Time.get_ticks_usec(),1000000)
	check(not projection._tiles.has(leaving[0]),"current overview permits eventual release")
	# Budget is checked between transactions, not once before all regions.
	projection.publications.clear();projection.publication_us=2000
	for x in [0,6]:
		var key:=Vector2i(x,0);var section:=Vector2i(x/6,0)
		projection._tiles[key]=projection._new_tile_host("Budget_%d"%x)
		projection._overviews[section]={"revision":projection._overview_revision.get(section,0)}
		projection._overview_dirty[section]=true
	projection._poll_overviews(Time.get_ticks_usec(),1000)
	check(projection.publications.size()==1 and projection._tiles.size()==1,"only one region transaction admitted before deadline")
	projection._poll_overviews(Time.get_ticks_usec(),1000000)
	check(projection._tiles.is_empty() and projection._overview_dirty.is_empty(),"deferred release converges after budget becomes available")
	projection._overviews.clear();projection.free()
	print("TERRAIN_PUBLICATION_ADMISSION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
