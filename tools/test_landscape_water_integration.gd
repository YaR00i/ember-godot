extends SceneTree
## Legacy analytic-contact compatibility: real startup discovery, no manual repair.
## The existing fixture/session writes stay in user://; authored scene/Source are read-only.
var errors:Array[String]=[]
func check(value:bool,message:String)->void:
    if not value:errors.append(message);printerr("FAIL ",message)
func _initialize()->void:
    preload("res://tools/fixtures/ember_exploration_test_fixture.gd").prepare(self,"user://ember-tests/water-integration-"+str(OS.get_process_id()))
    run.call_deferred()
func run()->void:
    var scene=load("res://scenes/landscape_compact.tscn").instantiate()
    scene.sandbox_storage_root="user://ember-tests/water-integration-"+str(OS.get_process_id())
    scene.get_node("Map/WorldAnomaly").enabled=false
    # The live shared-field main-map path has its own focused evidence. Keep
    # exercising the retained analytic fallback and its lifecycle here.
    scene.get_node("PlanarReflection").obstacle_wave_mode=0
    scene.get_node("Map/Props/WaterInteractionRock").water_contact_enabled=false
    root.add_child(scene);current_scene=scene
    var deadline=Time.get_ticks_msec()+60000
    var water=scene.get_node("PlanarReflection")
    while (not scene._startup_complete or not water._prepared) and Time.get_ticks_msec()<deadline:await process_frame
    check(scene._startup_complete,"map starts")
    var map=scene.get_node("Map")
    var environment=map.get_node("Look/WorldEnvironment").environment
    check(environment.sky!=null,"main map has authored reflection sky")
    check(environment.reflected_light_source==2,"water uses sky reflections")
    var player=scene._player
    var followers=scene._party_followers
    player.set_physics_process(false);followers.set_physics_process(false)
    var actors:Array[Node3D]=[player]
    actors.append_array(followers._followers)
    for frame in 3:await process_frame
    for actor in actors:check(water._surface_contacts.has(actor.get_node("WaterContact")),"ordinary startup discovers "+str(actor.name))
    var projection=map._visual_surface_projection
    var wet=Vector3.ZERO
    var found=false
    for z in range(24,360,4):
        if found:break
        for x in range(24,340,4):
            var point=Vector3(x,0,z)
            var sample=projection.water_surface_sample(point)
            if not sample.get("wet",false):continue
            var good=true
            for offset in [Vector3(0,0,20),Vector3(20,0,0),Vector3(20,0,20)]:
                var next:Dictionary=projection.water_surface_sample(point+offset)
                var floor_sample:Dictionary=projection.floor_surface_sample(point+offset)
                if not next.get("wet",false) or not floor_sample.get("solid",false):good=false;continue
                if next.position.y-floor_sample.position.y<0 or next.position.y-floor_sample.position.y>12:good=false
            if good:wet=sample.position;found=true;break
    check(found,"wet movement route exists")
    for index in actors.size():
        actors[index].global_position=projection.floor_surface_sample(wet+Vector3(index*8,0,0)).position
        var contact=actors[index].get_node_or_null("WaterContact")
        check(contact!=null,"actor %d has shared contact"%index)
        if contact==null:continue
        contact.set_process(false);contact.reset_motion_tracking();contact.sample_motion(0.1);contact.refresh_now()
    var fields_before:int=water._fields_build_count
    for step in 12:
        for actor in actors:
            actor.position.z+=0.8
            var contact=actor.get_node_or_null("WaterContact")
            if contact!=null:contact.sample_motion(1.0/30.0);contact.refresh_now();contact._advance_wake(1.0/30.0)
        await process_frame
    water._upload_surface_contacts()
    check(water._fields_build_count==fields_before,"party movement does not rebuild terrain water fields")
    for index in actors.size():
        var contact=actors[index].get_node_or_null("WaterContact")
        if contact==null:continue
        check(contact.is_contact_visible(),"actor %d is wet"%index)
        check(contact.surface_wake_samples().size()>0,"actor %d generates arcs"%index)
        check(water._surface_contacts.has(contact),"actor %d is bound to moving water"%index)
    check(int(water._material.get_shader_parameter("reaction_count"))>=actors.size(),"water receives party arcs")
    var packed_wakes:PackedVector4Array=water._material.get_shader_parameter("reaction_samples")
    for index in actors.size():
        var contributed=false
        for sample_index in int(water._material.get_shader_parameter("reaction_count")):
            if absf(packed_wakes[sample_index].x*16.0-actors[index].position.x)<1.0:contributed=true
        check(contributed,"actor %d has its own shader arc"%index)
    if actors.size()>1:
        actors[1].hide()
        actors[1].get_node("WaterContact").refresh_now()
        for frame in 3:await process_frame
        water._upload_surface_contacts()
        var hidden_wakes:PackedVector4Array=water._material.get_shader_parameter("reaction_samples")
        var hidden_count:int=water._material.get_shader_parameter("reaction_count")
        for index in hidden_count:check(absf(hidden_wakes[index].x*16.0-actors[1].position.x)>1.0,"hidden follower does not leave ghost arcs")
        actors[1].show()
        var returned=actors[1].get_node("WaterContact")
        for step in 12:
            actors[1].position.z+=0.8
            returned.sample_motion(1.0/30.0);returned.refresh_now();returned._advance_wake(1.0/30.0)
            await process_frame
        check(not returned.surface_wake_samples().is_empty() and water._surface_contacts.has(returned),"shown follower returns without manual rediscovery")
    for actor in actors:
        var contact=actor.get_node_or_null("WaterContact")
        if contact==null:continue
        for tick in 30:
            contact.sample_motion(0.1);contact.refresh_now();contact._advance_wake(0.1)
        check(contact.surface_wake_samples().is_empty(),"stopped actor trail expires")
        actor.global_position=Vector3(72,-1,200)
        contact.reset_motion_tracking();contact.refresh_now()
        check(not contact.is_contact_visible(),"dry ground disables water contact")
    water._upload_surface_contacts()
    check(int(water._material.get_shader_parameter("reaction_count"))==0,"expired party arcs leave the water shader")
    var prop:=Node3D.new();map.get_node("Props").add_child(prop)
    prop.global_position=wet
    var visual:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(8,12,8);visual.mesh=box;prop.add_child(visual)
    var prop_contact:=EmberWaterContact3D.new();prop_contact.static_surface_foam_footprint=true;prop.add_child(prop_contact)
    for frame in 3:await process_frame
    check(int(water._material.get_shader_parameter("object_shape_count"))==1,"static prop footprint remains supported")
    prop.free()
    for frame in 3:await process_frame
    check(int(water._material.get_shader_parameter("object_shape_count"))==0,"removed contact leaves the shader automatically")
    check(water._fields_build_count==fields_before,"contact addition/removal does not rebuild water terrain fields")
    print("LANDSCAPE_WATER_INTEGRATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"actors":actors.size(),"reaction_count":water._material.get_shader_parameter("reaction_count")}))
    quit(0 if errors.is_empty() else 1)
