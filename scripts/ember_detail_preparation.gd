@tool
extends RefCounted
## Shared preparation budget and disposable scatter data. GrassPatch still owns
## authored settings and placement; this module never changes the map/terrain.
const DetailPolicy = preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const ROOT := "user://ember-detail-scatter-cache"
const VERSION := 1 # Bump when placement/footprint/surface sampling changes.
const FRAME_US := 5000 # Ground + active detail callbacks + queued publication/scatter.
const GAMEPLAY_FRAME_US := 3000 # After the existing world startup barrier reveals play.
const MAX_INSTANCES := 20000
const DISK_BUDGET := 128 * 1024 * 1024
const WRITE_QUEUE_BYTES := 8 * 1024 * 1024
const WRITE_QUEUE_LIMIT := 16
const READ_QUEUE_LIMIT := 2 # Includes completed payloads waiting for a budget turn.
static var cache_root := ROOT
static var _contexts: Dictionary = {}
static var _detail_shaders: Dictionary = {} # At most two private-material templates, shared shaders.

static func prepare_shader(flower: bool, host: Node, cancelled: Callable) -> bool:
	# Loading just Shader postpones its first parameter reflection until binding,
	# still blocking the main thread. The template loads those defaults as well.
	var path: String = Materials.FLOWER_MATERIAL_PATH if flower else Materials.GRASS_MATERIAL_PATH
	if not _detail_shaders.has(path):
		var error := ResourceLoader.load_threaded_request(path,"ShaderMaterial")
		if error != OK: return false
		_detail_shaders[path] = null
	while _detail_shaders.get(path) == null:
		if not _detail_shaders.has(path):return false
		if cancelled.call(): return false
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_detail_shaders[path] = ResourceLoader.load_threaded_get(path)
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await host.get_tree().process_frame
		else:
			_detail_shaders.erase(path)
			return false
	return not cancelled.call()
var projection_ref: WeakRef
var disk := Storage.new()
var hits := 0
var misses := 0
var _frame := -1
var _deadline := 0
var _fingerprints: Dictionary = {}
var _source_ref: WeakRef
var _writes := 0
var _cache_writes:Array[CacheWriteJob]=[]
var _cache_write_job:CacheWriteJob
var _cache_write_task:=-1
var _cache_write_bytes:=0
var cache_writes_skipped:=0
var _cache_reads:Array[CacheReadJob]=[]
var cache_read_jobs_started:=0
var cache_read_worker_us:=0
var _trim_task := -1
var _trim_job: CacheTrimJob
var cache_trim_us := 0
var cache_trim_runs := 0
var _material_frame := -1
var _material_patterns: Dictionary = {}
var _material_saved:Dictionary={} # Immutable saved inputs for the current batch, including evicted slots.
var _saved_material_patterns:Dictionary={}
var _role_payloads:Dictionary={} # Bounded saved CPU packing; shared PNG banks remain weak.
var _material_digest_job:MaterialDigestJob # One worker/finished result per context.
const SAVED_MATERIAL_LIMIT:=16
var _sleeping: Dictionary = {} # IDs -> weak nodes; authored patches keep their existing owner.
var _sleeping_order: Array[int] = []
var _sleeping_cursor := 0
var _sleeping_slots:Dictionary={}
var _sleeping_bins:Dictionary={}
var _sleeping_keys:Dictionary={}
var _sleeping_large:Dictionary={}
var _sleeping_candidates:Array[int]=[]
var _sleeping_candidate_cursor:=0
var _sleeping_candidate_state:Array=[]
var _sleeping_index_dirty:=true
var _sleeping_scan_epoch:=-2
var _sleeping_scan_remaining:=0
var _sleeping_scan_retry:=false
class BudgetTurn extends RefCounted:
	signal ready
	var host:WeakRef
	var band:=0
	var urgent:=false
	var sequence:=0
	var cancelled:=false
var _budget_waiters:Array[BudgetTurn]=[]
var _next_budget_waiters:Array[BudgetTurn]=[] # Requeued turns cannot displace this dispatch's original tickets.
var _queue_sequence:=0
var _priority_anchor:=Vector3.INF
var _frame_tree:WeakRef
var _released:=false
var _budget_dispatching:=false
var _foreground_frame:=-1
var _foreground_us:=0
var _ground_scope_frame:=-1
var _detail_poll_frame:=-1
var _detail_poll_state:Array=[]
var _detail_poll_epoch:=0

func invalidate_detail_poll()->void:
	_detail_poll_frame=-1

func detail_poll_epoch()->int:
	var frame:=Engine.get_process_frames()
	if _detail_poll_frame==frame:return _detail_poll_epoch
	var projection:Node3D=projection_ref.get_ref()
	if projection==null or not projection.has_method("detail_world_anchor") or not projection.has_method("column_revision"):return -1
	var policy=projection.get("detail_policy")
	if policy==null:return -1
	var document=projection.get("document")
	var state:Array=[document.get_instance_id() if is_instance_valid(document) else 0,projection.global_transform,projection.column_revision(),projection.editor_detail_active(),policy.anchor,policy.detail_prepare_m,policy.detail_release_m,policy.detail_fade_begin_m,policy.detail_fade_end_m,policy.cells_per_m,projection.get("_live_brush_active"),projection.get_parent().get("imported_tile_size")]
	if state!=_detail_poll_state:
		_detail_poll_state=state;_detail_poll_epoch+=1
	_detail_poll_frame=frame
	return _detail_poll_epoch
var _terrain_jobs:Dictionary={} # At most two immutable CPU scatters per projection.
var terrain_jobs_started:=0
var terrain_jobs_us:=0

func terrain_job_available()->bool:
	return not _released and _terrain_jobs.size()<2

func start_terrain_job(host:Node,job:RefCounted)->void:
	var task:=WorkerThreadPool.add_task(job.run,false,"Ember terrain scatter")
	_terrain_jobs[task]={"job":job,"host":weakref(host)}
	terrain_jobs_started+=1

func _poll_terrain_jobs()->void:
	for task:int in _terrain_jobs.keys():
		var entry:Dictionary=_terrain_jobs[task]
		var host:Node=entry.host.get_ref()
		if host==null or not _spatial_host_current(host) or bool(host.get("_dirty")):entry.job.cancel()
		if not WorkerThreadPool.is_task_completed(task):continue
		WorkerThreadPool.wait_for_task_completion(task)
		_terrain_jobs.erase(task);terrain_jobs_us+=entry.job.elapsed_us
		entry.job.notify_ready()

func begin_ground()->void:
	_ground_scope_frame=Engine.get_process_frames()

func finish_detail(started_us:int)->void:
	# Sleeping patches are polled inside ground processing and already belong
	# to its elapsed slice. Active patch callbacks belong to this SAME allowance.
	if _ground_scope_frame==Engine.get_process_frames():return
	_charge_foreground(started_us)

func _charge_foreground(started_us:int)->void:
	var frame:=Engine.get_process_frames()
	if _foreground_frame!=frame:_foreground_frame=frame;_foreground_us=0
	_foreground_us+=maxi(0,Time.get_ticks_usec()-started_us)

func finish_ground(started_us:int)->void:
	_ground_scope_frame=-1
	_charge_foreground(started_us)

func in_budget_turn()->bool:
	return _budget_dispatching

func has_pending_work()->bool:
	return not _budget_waiters.is_empty() or not _next_budget_waiters.is_empty()

func frame_budget_us()->int:
	if Engine.is_editor_hint():return FRAME_US
	var projection:Node=projection_ref.get_ref() if projection_ref!=null else null
	if projection!=null and projection.has_method("begin_live_brush") and projection.get("_live_brush_active")==true:return FRAME_US
	var owner:Node=projection.get_parent() if projection!=null else null
	while owner!=null:
		if owner.has_method("is_world_preparation_complete"):
			return GAMEPLAY_FRAME_US if owner.is_world_preparation_complete() else FRAME_US
		owner=owner.get_parent()
	return FRAME_US

func _queue_budget_frame() -> void:
	if _released:return
	_finish_material_digest()
	_finish_cache_reads()
	_finish_cache_writes()
	_finish_cache_trim()
	_poll_terrain_jobs()
	if _budget_waiters.is_empty():return
	var tree:SceneTree=_frame_tree.get_ref() if _frame_tree!=null else null
	# call_deferred() from process_frame is flushed before node processing.
	# SceneTreeTimer is processed after the nodes: one timer for this context,
	# not one timer per blade/patch/coroutine.
	if tree!=null:tree.create_timer(0.0,true,false,true).timeout.connect(_poll_budget_waiters,CONNECT_ONE_SHOT)

func wait_for_turn(host:Node) -> bool:
	if _released:return false
	if host.has_method("_world_area") and not _spatial_host_current(host):return false
	var turn:=BudgetTurn.new();turn.host=weakref(host)
	turn.urgent=bool(host.get("_detail_priority_pending"))
	turn.band=_preparation_band(host)
	turn.sequence=_queue_sequence;_queue_sequence+=1
	_insert_budget_turn(turn)
	await turn.ready
	return not _released and not turn.cancelled and turn.host.get_ref()!=null

func _preparation_band(host:Node)->int:
	var projection:Node=projection_ref.get_ref()
	if projection!=null and projection.has_method("detail_preparation_band") and host.has_method("_world_area"):
		return projection.detail_preparation_band(host._world_area())
	return 0

func _insert_budget_turn(turn:BudgetTurn)->void:
	_insert_sorted_budget_turn(_next_budget_waiters if _budget_dispatching else _budget_waiters,turn)

func _insert_sorted_budget_turn(queue:Array[BudgetTurn],turn:BudgetTurn)->void:
	# Requeued work changes one position, not the whole queue. Sorting hundreds
	# of tickets every slice consumed a substantial part of the 4ms allowance.
	if queue.is_empty() or not _turn_before(turn,queue[-1]):queue.append(turn)
	else:queue.insert(queue.bsearch_custom(turn,_turn_before),turn)

func _spatial_host_current(host:Node)->bool:
	var projection:Node=projection_ref.get_ref()
	var owner:Node=projection.get_parent() if projection!=null else null
	return host.is_inside_tree() and host.can_process() and bool(host.get("_detail_resident")) and owner!=null and owner.is_ancestor_of(host)

static func _turn_before(a:BudgetTurn,b:BudgetTurn)->bool:
	if a.urgent!=b.urgent:return a.urgent
	if a.band!=b.band:return a.band<b.band
	return a.sequence<b.sequence

static func cancel_patch(host:Node)->void:
	for context in _contexts.values():context._cancel_patch(host)

func _cancel_patch(host:Node)->void:
	_forget_sleeping_id(host.get_instance_id())
	if _material_digest_job!=null and _material_digest_job.host.get_ref()==host:
		_material_digest_job.abandoned=true;_material_digest_job.notify_ready()
	for job:CacheReadJob in _cache_reads.duplicate():
		if job.host.get_ref()==host:
			job.abandoned=true;job.notify_ready()
	for entry:Dictionary in _terrain_jobs.values():
		if entry.host.get_ref()==host:entry.job.cancel();entry.job.notify_ready()
	var cancelled:Array[BudgetTurn]=[]
	for queue:Array[BudgetTurn] in [_budget_waiters,_next_budget_waiters]:
		var kept:Array[BudgetTurn]=[]
		for turn:BudgetTurn in queue:
			if turn.host.get_ref()==host:turn.cancelled=true;cancelled.append(turn)
			else:kept.append(turn)
		queue.assign(kept)
	for turn:BudgetTurn in cancelled:turn.ready.emit()

func _order_budget_waiters()->void:
	var projection:Node=projection_ref.get_ref()
	var anchor:Vector3=projection.detail_world_anchor() if projection!=null and projection.has_method("detail_world_anchor") else Vector3.ZERO
	var moved:=anchor!=_priority_anchor
	if not moved:return
	var kept:Array[BudgetTurn]=[];var cancelled:Array[BudgetTurn]=[]
	for turn:BudgetTurn in _budget_waiters:
		var host:Node=turn.host.get_ref()
		if host==null or (host.has_method("_world_area") and not _spatial_host_current(host)):
			turn.cancelled=true;cancelled.append(turn)
		else:
			if moved:turn.band=_preparation_band(host)
			kept.append(turn)
	_budget_waiters=kept
	_budget_waiters.sort_custom(_turn_before)
	_priority_anchor=anchor
	# Cancellation resumes only the cleanup branch, releasing old coroutine data
	# even if a moving camera keeps producing nearer work indefinitely.
	for turn:BudgetTurn in cancelled:turn.ready.emit()

func prioritize(host:Node) -> void:
	for queue:Array[BudgetTurn] in [_budget_waiters,_next_budget_waiters]:
		for index in queue.size():
			if queue[index].host.get_ref()==host:
				var turn:=queue[index];queue.remove_at(index)
				turn.urgent=true;_insert_sorted_budget_turn(queue,turn)
				return

func _poll_budget_waiters() -> void:
	# At the timer phase: ground and active detail callbacks have run first. A job
	# that uses its allowance rejoins the tail, rather than owning the first
	# SceneTree signal slot every frame until its entire patch is finished.
	# Count preparation CPU slices, not unrelated editor/UI work between nodes
	# and the timer. A wall-clock deadline opened by ground can already be past
	# before any scatter gets a turn, starving it forever on a busy editor frame.
	var frame:=Engine.get_process_frames()
	var foreground_us:int=_foreground_us if _foreground_frame==frame else 0
	_frame=frame;_deadline=Time.get_ticks_usec()+maxi(0,frame_budget_us()-foreground_us)
	_budget_dispatching=true
	_order_budget_waiters()
	var remaining:=_budget_waiters.size()
	while not _released and remaining>0 and not _budget_waiters.is_empty() and available():
		remaining-=1
		var turn:BudgetTurn=_budget_waiters.pop_front()
		var host:Node=turn.host.get_ref()
		if host==null or (host.has_method("_world_area") and not _spatial_host_current(host)):turn.cancelled=true
		turn.ready.emit()
	_budget_dispatching=false
	# Each original ticket gets at most one turn. In particular, a near job
	# waiting for a bounded slot must let its farther owner deliver/release it.
	var next:=_next_budget_waiters.duplicate();_next_budget_waiters.clear()
	for turn:BudgetTurn in next:_insert_sorted_budget_turn(_budget_waiters,turn)

func _release() -> void:
	_released=true
	if _material_digest_job!=null:
		_material_digest_job.abandoned=true;_material_digest_job.notify_ready()
	_finish_material_digest(true)
	for job:CacheReadJob in _cache_reads.duplicate():
		job.abandoned=true;job.notify_ready()
	_finish_cache_reads(true)
	# Accepted content-addressed snapshots remain valid when their patch leaves.
	# Drain on context teardown, never on a patch's ordinary release/return.
	_finish_cache_writes(true)
	_material_patterns.clear();_material_saved.clear();_saved_material_patterns.clear();_role_payloads.clear()
	if _trim_job!=null:_trim_job.cancel()
	_finish_cache_trim(true)
	var jobs:=_terrain_jobs.duplicate();_terrain_jobs.clear()
	for entry:Dictionary in jobs.values():entry.job.cancel()
	for task:int in jobs:
		WorkerThreadPool.wait_for_task_completion(task)
		jobs[task].job.notify_ready()
	var tree:SceneTree=_frame_tree.get_ref() if _frame_tree!=null else null
	if tree!=null and tree.process_frame.is_connected(_queue_budget_frame):tree.process_frame.disconnect(_queue_budget_frame)
	var waiting:=_budget_waiters.duplicate();waiting.append_array(_next_budget_waiters)
	_budget_waiters.clear();_next_budget_waiters.clear()
	for turn:BudgetTurn in waiting:turn.ready.emit()
	wake_sleeping()

static func moved_sleeping_patch(patch:Node)->void:
	var context:RefCounted=_contexts.get(int(patch.get("_detail_poll_projection_id")))
	if context!=null and context._sleeping.has(patch.get_instance_id()):context._index_sleeping_patch(patch)

func _remove_sleeping_keys(id:int)->void:
	for key:Vector2i in _sleeping_keys.get(id,[]):
		if _sleeping_bins.has(key):
			_sleeping_bins[key].erase(id)
			if _sleeping_bins[key].is_empty():_sleeping_bins.erase(key)
	_sleeping_keys.erase(id);_sleeping_large.erase(id)

func _index_sleeping_patch(patch:Node)->void:
	var id:=patch.get_instance_id();_remove_sleeping_keys(id)
	var projection:Node3D=projection_ref.get_ref()
	if projection==null:return
	var local_area := DetailPolicy.local_area(patch._world_area(), projection.global_transform.affine_inverse(), projection.global_position.y)
	var low := local_area.position
	var high := local_area.end
	var first:=Vector2i(floori(low.x/64.0),floori(low.y/64.0))
	var last:=Vector2i(floori(high.x/64.0),floori(high.y/64.0))
	var keys:Array[Vector2i]=[]
	if (last.x-first.x+1)*(last.y-first.y+1)>16:_sleeping_large[id]=true
	else:
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,z);keys.append(key)
				if not _sleeping_bins.has(key):_sleeping_bins[key]={}
				_sleeping_bins[key][id]=true
	_sleeping_keys[id]=keys;_sleeping_index_dirty=true

func sleep_patch(patch: Node) -> void:
	var projection: Node = projection_ref.get_ref()
	if projection == null: return
	var id := patch.get_instance_id()
	if not _sleeping.has(id):
		_sleeping[id]=weakref(patch);_sleeping_slots[id]=_sleeping_order.size();_sleeping_order.append(id)
		_index_sleeping_patch(patch)
	patch._detail_poll_projection_id = projection.get_instance_id()
	patch.set_notify_transform(true)
	patch.set_process(false)

func _forget_sleeping_id(id:int)->void:
	if not _sleeping.has(id):return
	var slot:int=_sleeping_slots[id];var moved:int=_sleeping_order[-1]
	_sleeping_order[slot]=moved;_sleeping_slots[moved]=slot;_sleeping_order.pop_back()
	_sleeping.erase(id);_sleeping_slots.erase(id);_remove_sleeping_keys(id)

func _refresh_sleeping_candidates(projection:Node)->void:
	var anchor:Vector2=projection.detail_policy.anchor
	var center:=Vector2i(floori(anchor.x/64.0),floori(anchor.y/64.0))
	var radius:=ceili(maxf(projection.detail_policy.detail_prepare_m,projection.detail_policy.detail_release_m)*projection.detail_policy.cells_per_m/64.0)+1
	var active:bool=projection.editor_detail_active()
	var state:Array=[center,radius,active]
	if not _sleeping_index_dirty and state==_sleeping_candidate_state:return
	_sleeping_index_dirty=false;_sleeping_candidate_state=state;_sleeping_candidate_cursor=0
	_sleeping_scan_epoch=-2 # New/reindexed hosts must join even within the same epoch.
	_sleeping_candidates.clear()
	if not active:_sleeping_candidates.assign(_sleeping_order);return
	var wanted:Dictionary=_sleeping_large.duplicate()
	for z in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			if _sleeping_bins.has(Vector2i(x,z)):wanted.merge(_sleeping_bins[Vector2i(x,z)])
	_sleeping_candidates.assign(wanted.keys())

func poll_sleeping() -> void:
	# Disposable admission index under the existing preparation owner. Exact
	# residency is still decided by the patch/Projection, never by these bins.
	var began:=Time.get_ticks_usec();var projection:Node=projection_ref.get_ref()
	if projection==null:return
	_refresh_sleeping_candidates(projection)
	# Runtime has an authoritative policy/source epoch. Once every candidate
	# was checked, identical inputs cannot admit another patch. Editor/custom
	# projections without that contract keep the conservative periodic scan.
	var epoch:int=detail_poll_epoch() if not Engine.is_editor_hint() else -1
	if epoch<0 or epoch!=_sleeping_scan_epoch or (_sleeping_scan_remaining==0 and _sleeping_scan_retry):
		_sleeping_scan_epoch=epoch;_sleeping_scan_remaining=_sleeping_candidates.size();_sleeping_scan_retry=false
	var exact_admission:bool=not Engine.is_editor_hint() and projection.editor_detail_active()
	var inverse:Transform3D=projection.global_transform.affine_inverse()
	var remaining:=mini(512,_sleeping_scan_remaining)
	while remaining>0 and not _sleeping_candidates.is_empty() and Time.get_ticks_usec()-began<1000:
		remaining-=1;_sleeping_scan_remaining-=1
		if _sleeping_candidate_cursor>=_sleeping_candidates.size():_sleeping_candidate_cursor=0
		var id:int=_sleeping_candidates[_sleeping_candidate_cursor];_sleeping_candidate_cursor+=1
		if not _sleeping.has(id):continue
		var patch:Node=_sleeping[id].get_ref()
		if patch==null or not patch.is_inside_tree() or patch._detail_poll_projection_id!=projection.get_instance_id() or patch.is_processing():
			_forget_sleeping_id(id);continue
		if patch.can_process():
			# Bins are deliberately conservative. Reject their distant neighbours
			# before entering the full patch callback; use live cached bounds so
			# resizing a sleeping patch cannot leave it behind a stale rectangle.
			if exact_admission and not patch._detail_resident and patch._detail_preview.is_empty():
				var area:=DetailPolicy.local_area(patch._world_area(),inverse,projection.global_position.y)
				if not projection.detail_policy.detail_resident(area,false):continue
			patch._process(0.0)
			if patch._detail_resident:patch.set_process(true);_forget_sleeping_id(id)
		else:
			# A paused ancestor can resume without changing distance/source.
			# Keep retrying that incomplete admission instead of caching its skip.
			_sleeping_scan_retry=true
	# Weak-entry maintenance is independent of near admission and does no far
	# surface work. Removed nodes also unregister synchronously in cancel_patch.
	for i in mini(16,_sleeping_order.size()):
		if _sleeping_cursor>=_sleeping_order.size():_sleeping_cursor=0
		var id:int=_sleeping_order[_sleeping_cursor];var patch:Node=_sleeping[id].get_ref()
		if patch==null or not patch.is_inside_tree():_forget_sleeping_id(id)
		else:_sleeping_cursor+=1

func wake_sleeping() -> void:
	for reference: WeakRef in _sleeping.values():
		var patch: Node = reference.get_ref()
		if patch == null: continue
		patch._detail_poll_projection_id = 0
		patch._dirty = true
		patch.set_process(true)
	_sleeping.clear(); _sleeping_order.clear(); _sleeping_cursor = 0
	_sleeping_slots.clear();_sleeping_bins.clear();_sleeping_keys.clear();_sleeping_large.clear()
	_sleeping_candidates.clear();_sleeping_candidate_state.clear();_sleeping_index_dirty=true

static func release_projection(projection: Node) -> void:
	var id := projection.get_instance_id()
	if not _contexts.has(id): return
	_contexts[id]._release()
	_contexts.erase(id)

func material_patterns(roles: PackedStringArray, ids: PackedStringArray) -> Dictionary:
	# A batch gets private copies of saved presets. Reparse only changed files;
	# checking bytes also catches same-second saves, unlike modification times.
	# Bindings still own their lookup images/textures and editable previews.
	var frame := Engine.get_process_frames()
	if frame != _material_frame:
		_material_frame = frame
		_material_patterns.clear();_material_saved.clear()
	var result: Dictionary = {}
	for slot in roles.size():
		if roles[slot].is_empty(): continue
		var id: String = ids[slot] if slot < ids.size() and not ids[slot].is_empty() else roles[slot]
		if not _material_patterns.has(id):
			var path:=Materials.variant_path(id)
			_material_patterns[id] = _saved_material_pattern(path)
			_material_saved[id]=_saved_material_patterns.get(path,{}) if _material_patterns[id]!=null else {}
		result[id] = _material_patterns[id]
	return result

func bind_saved_material_roles(material:ShaderMaterial,roles:PackedStringArray,ids:PackedStringArray,palette:PackedColorArray)->void:
	var patterns:=material_patterns(roles,ids)
	var revisions:Array=[];var saved:Dictionary={}
	for id:String in patterns:
		var entry:Dictionary=_material_saved.get(id,{})
		revisions.append([id,entry.get("digest","")])
		if not entry.is_empty():saved[id]=entry.source
	_bind_saved_role_payload(material,roles,ids,palette,saved,revisions)

func _bind_saved_role_payload(material:ShaderMaterial,roles:PackedStringArray,ids:PackedStringArray,palette:PackedColorArray,saved:Dictionary,revisions:Array)->void:
	# Frame-local caller copies may be edited. Pack only the private saved
	# templates and include their file contents plus palette/layout in the key.
	var key:=var_to_bytes([roles,ids,palette,revisions,Materials.terrain_role_texture_revisions(saved)]).hex_encode()
	if not _role_payloads.has(key):
		var prepared:=Materials.prepare_terrain_roles(roles,ids,palette,saved)
		if _role_payloads.size()>=SAVED_MATERIAL_LIMIT:_role_payloads.erase(_role_payloads.keys()[0])
		_role_payloads[key]=prepared
	Materials.apply_prepared_terrain_roles(material,_role_payloads[key])

func _material_role_paths(roles:PackedStringArray,ids:PackedStringArray)->Dictionary:
	var paths:Dictionary={}
	for slot in roles.size():
		if roles[slot].is_empty():continue
		var id:String=ids[slot] if slot<ids.size() and not ids[slot].is_empty() else roles[slot]
		paths[id]=Materials.variant_path(id)
	return paths

func _new_material_digest_job()->MaterialDigestJob:
	return MaterialDigestJob.new()

func bind_saved_material_roles_async(material:ShaderMaterial,roles:PackedStringArray,ids:PackedStringArray,palette:PackedColorArray,host:Node,cancelled:Callable)->bool:
	if _released or not is_instance_valid(host) or not cancelled.is_valid() or cancelled.call():return false
	# Immutable layout while the worker checks saved bytes. Only private saved
	# templates enter the payload; live profile images remain binding-owned.
	roles=roles.duplicate();ids=ids.duplicate();palette=palette.duplicate()
	while _material_digest_job!=null:
		if not await wait_for_turn(host):return false
		if _released or not is_instance_valid(host) or not cancelled.is_valid() or cancelled.call():return false
	var paths:=_material_role_paths(roles,ids)
	var job:=_new_material_digest_job();job.host=weakref(host)
	for path:String in paths.values():
		if not path.is_empty() and not path in job.paths:job.paths.append(path)
	job.task=WorkerThreadPool.add_task(job.run,false,"Ember saved material digests")
	if job.task<0:return false
	_material_digest_job=job
	await job.ready
	if _released or job.abandoned or not is_instance_valid(host) or not cancelled.is_valid():
		_abandon_material_digest(job);return false
	while not in_budget_turn() or not available():
		if not await wait_for_turn(host):
			_abandon_material_digest(job);return false
		if _released or job.abandoned or not is_instance_valid(host) or not cancelled.is_valid():
			_abandon_material_digest(job);return false
	if cancelled.call():
		_abandon_material_digest(job);return false
	_material_digest_job=null
	var saved:Dictionary={};var revisions:Array=[]
	for id:String in paths:
		var path:String=paths[id];var digest:String=job.digests.get(path,"")
		var entry:Dictionary=_saved_material_patterns.get(path,{})
		if digest.is_empty():entry={}
		elif entry.get("digest","")!=digest:
			# A changed/new file is rare. Recheck synchronously only here, so a
			# save between worker observation and delivery cannot label new bytes
			# with an old digest or poison a previously prepared payload key.
			var source:=_saved_material_pattern(path)
			entry=_saved_material_patterns.get(path,{}) if source!=null else {}
		revisions.append([id,entry.get("digest","")])
		if not entry.is_empty():saved[id]=entry.source
	_bind_saved_role_payload(material,roles,ids,palette,saved,revisions)
	return true

func _abandon_material_digest(job:MaterialDigestJob)->void:
	job.abandoned=true
	if job.finished and _material_digest_job==job:_material_digest_job=null

func _finish_material_digest(wait:=false)->void:
	var job:=_material_digest_job
	if job==null:return
	if not job.finished:
		if not wait and not WorkerThreadPool.is_task_completed(job.task):return
		WorkerThreadPool.wait_for_task_completion(job.task);job.finished=true
	if job.abandoned or _released:_material_digest_job=null
	job.notify_ready()

class MaterialDigestJob extends RefCounted:
	signal ready
	var paths:=PackedStringArray()
	var host:WeakRef # Main-thread tracking; run() reads only paths and file bytes.
	var digests:Dictionary={}
	var task:=-1
	var finished:=false
	var abandoned:=false
	var _notified:=false
	func notify_ready()->void:
		if _notified:return
		_notified=true;ready.emit()
	func run()->void:
		for path in paths:digests[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _saved_material_pattern(path:String)->EmberCompactTerrainPattern:
	if path.is_empty() or not ResourceLoader.exists(path):return null
	var digest:=FileAccess.get_sha256(path)
	if digest.is_empty():return null
	var saved:Dictionary=_saved_material_patterns.get(path,{})
	if saved.get("digest","")!=digest:
		var source:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REPLACE) as EmberCompactTerrainPattern
		if source==null:return null
		# The template never escapes; caller edits cannot poison later batches.
		saved={"digest":digest,"source":_copy_material_pattern(source)}
		if not _saved_material_patterns.has(path) and _saved_material_patterns.size()>=SAVED_MATERIAL_LIMIT:
			_saved_material_patterns.erase(_saved_material_patterns.keys()[0])
		_saved_material_patterns[path]=saved
	return _copy_material_pattern(saved.source)

static func _copy_material_pattern(source:EmberCompactTerrainPattern)->EmberCompactTerrainPattern:
	var copy:=source.duplicate() as EmberCompactTerrainPattern
	# Resource.duplicate() retains packed-array aliases. Copy authored channels,
	# keeping imported texture resources shared instead of duplicating GPU data.
	for field in ["pixels","side_pixels","relief_pixels","side_relief_pixels","roughness_pixels","side_roughness_pixels"]:
		copy.set(field,(source.get(field) as PackedByteArray).duplicate())
	return copy

static func for_projection(projection: Node3D) -> RefCounted:
	for id in _contexts.keys():
		if _contexts[id].projection_ref.get_ref() == null:
			_contexts[id]._release()
			_contexts.erase(id)
	var id := projection.get_instance_id()
	if not _contexts.has(id):
		var context := new()
		context.projection_ref = weakref(projection)
		context.disk.directory = cache_root
		context.disk.magic = "EDSCATR1"
		context.disk.max_bytes = 4 * 1024 * 1024
		if projection.is_inside_tree():
			context._frame_tree=weakref(projection.get_tree())
			projection.get_tree().process_frame.connect(context._queue_budget_frame)
		_contexts[id] = context
	return _contexts[id]

func available() -> bool:
	if _released:return false
	var frame := Engine.get_process_frames()
	var now := Time.get_ticks_usec()
	if frame != _frame:
		_frame = frame
		var foreground_us:int=_foreground_us if _foreground_frame==frame else 0
		_deadline = now + maxi(0,frame_budget_us()-foreground_us)
	return now < _deadline

func remaining_us() -> int:
	available()
	return maxi(0,_deadline-Time.get_ticks_usec())

func content_key(projection: Node3D, stamp: Array, inputs: Array, host: Node, cancelled: Callable) -> String:
	if disk.directory.is_empty(): return ""
	var source = projection.document
	if _source_ref == null or _source_ref.get_ref() != source:
		_source_ref = weakref(source)
		_fingerprints.clear()
	var tiles: Dictionary = {}
	# Every sampled surface tile includes its neighbours: the exact detailed
	# field has an eleven-column halo, beyond the footprint/material halo.
	for entry: Array in stamp.slice(9):
		for z in range(entry[0].y - 1, entry[0].y + 2):
			for x in range(entry[0].x - 1, entry[0].x + 2):
				tiles[Vector2i(x,z)] = true
	var ordered := tiles.keys(); ordered.sort()
	var dependencies: Array = []
	for tile: Vector2i in ordered:
		if cancelled.call(): return ""
		var revision: int = projection.surface_tile_revision(tile)
		if not _fingerprints.has(tile) or _fingerprints[tile].revision != revision:
			while not available():
				if not await wait_for_turn(host):return ""
				if cancelled.call(): return ""
			if projection.document != source: return ""
			var bounds := Rect2i(tile * 64, Vector2i(64,64)).intersection(Rect2i(0,0,source.width,source.depth))
			var digest := "outside"
			if bounds.has_area():
				var part = source.dense_window(bounds)
				digest = Storage.digest([part.heights, part.top_materials, part.water_levels, part.surface_rules])
			_fingerprints[tile] = {"revision":revision,"digest":digest}
		dependencies.append([tile,_fingerprints[tile].digest])
	return Storage.digest([VERSION,Engine.get_version_info().hex,stamp.slice(1,9),inputs,dependencies])

func read(key: String) -> Dictionary:
	if key.is_empty(): return {}
	var looks:=CacheReadJob.validate(disk.read(key))
	if looks.is_empty():misses+=1
	else:hits+=1
	return looks

func read_async(key:String,host:Node,cancelled:Callable)->Dictionary:
	if key.is_empty() or _released or not is_instance_valid(host) or not cancelled.is_valid() or cancelled.call():return {}
	while _cache_reads.size()>=READ_QUEUE_LIMIT:
		if not await wait_for_turn(host):return {}
		if _released or not is_instance_valid(host) or not cancelled.is_valid() or cancelled.call():return {}
	var job:=CacheReadJob.new();job.key=key;job.host=weakref(host);job.cache_script=disk.get_script()
	for field:String in ["directory","magic","format_version","extension","max_bytes","packaged_directory","packaged_for_directory"]:job.settings[field]=disk.get(field)
	job.task=WorkerThreadPool.add_task(job.run,false,"Ember scatter cache read")
	if job.task<0:
		disk.failures+=1;misses+=1;return {} # Optional cache miss, never synchronous fallback.
	_cache_reads.append(job);cache_read_jobs_started+=1
	await job.ready
	if _released or job.abandoned or not is_instance_valid(host) or not cancelled.is_valid():
		_abandon_cache_read(job);return {}
	# Keep the slot while the result waits. Otherwise each completion could
	# retain another large payload in a suspended caller outside this bound.
	while not in_budget_turn() or not available():
		if not await wait_for_turn(host):
			_abandon_cache_read(job);return {}
		if _released or job.abandoned or not is_instance_valid(host) or not cancelled.is_valid():
			_abandon_cache_read(job);return {}
	if cancelled.call():
		_abandon_cache_read(job);return {}
	var looks:Dictionary=job.result.get("looks",{})
	_cache_reads.erase(job)
	if looks.is_empty():misses+=1
	else:hits+=1
	return looks

func _abandon_cache_read(job:CacheReadJob)->void:
	job.abandoned=true
	# Running IO retains its slot until the main-thread poll joins it. Patch
	# release never waits; context teardown joins every owned task.
	if job.finished:_cache_reads.erase(job)

func _finish_cache_reads(wait:=false)->void:
	for job:CacheReadJob in _cache_reads.duplicate():
		if not job.finished:
			if not wait and not WorkerThreadPool.is_task_completed(job.task):continue
			WorkerThreadPool.wait_for_task_completion(job.task);job.finished=true
			cache_read_worker_us+=int(job.result.get("elapsed_us",0))
			for field:String in ["read_us","read_bytes","invalid","failures","packaged_hits"]:disk.set(field,int(disk.get(field))+int(job.result.get(field,0)))
		if job.abandoned or _released:_cache_reads.erase(job)
		job.notify_ready()

class CacheReadJob extends RefCounted:
	signal ready
	var key:String
	var host:WeakRef # Main-thread tracking only; run() never accesses the Node.
	var cache_script:Script
	var settings:Dictionary={}
	var result:Dictionary={}
	var task:=-1
	var finished:=false # Main-thread state, read only after joining the worker.
	var abandoned:=false
	var _notified:=false
	func notify_ready()->void:
		if _notified:return
		_notified=true;ready.emit()
	func run()->void:
		# Only private storage and decoded value data. No Node access or caller
		# callback on the worker; object decoding stays disabled in Storage.
		var began:=Time.get_ticks_usec();var target=cache_script.new()
		for field:String in settings:target.set(field,settings[field])
		var looks:=validate(target.read(key))
		result={"looks":looks,"elapsed_us":Time.get_ticks_usec()-began}
		for field:String in ["read_us","read_bytes","invalid","failures","packaged_hits"]:result[field]=target.get(field)
	static func validate(data:Dictionary)->Dictionary:
		var looks:Variant=data.get("looks")
		if not looks is Dictionary or looks.is_empty() or looks.size()>3:return {}
		for look in looks:
			if not look is int or look<0 or look>2 or not looks[look] is Array or looks[look].size()>MAX_INSTANCES:return {}
			for transform in looks[look]:
				if not transform is Transform3D or not transform.is_finite():return {}
		return looks

func write(key: String, looks: Dictionary, cancelled: Callable) -> void:
	if _released or key.is_empty() or disk.directory.is_empty() or not cancelled.is_valid() or cancelled.call(): return
	# Bound the immutable in-flight copies before allocating them. A dropped
	# optional cache write changes neither publication nor authored placement.
	var weight:=1024
	for look in looks:
		if not look is int or look<0 or look>2:cache_writes_skipped+=1;return
		var value:Variant=looks[look]
		if not value is Array:cache_writes_skipped+=1;return
		if value.is_typed():
			if value.get_typed_builtin()!=TYPE_TRANSFORM3D:cache_writes_skipped+=1;return
		else:
			for transform in value:
				if not transform is Transform3D:cache_writes_skipped+=1;return
		weight+=value.size()*128
	if _cache_writes.size()+int(_cache_write_job!=null)>=WRITE_QUEUE_LIMIT or _cache_write_bytes+weight>WRITE_QUEUE_BYTES:
		cache_writes_skipped+=1;return
	var job:=CacheWriteJob.new()
	job.key=key;job.looks=looks.duplicate(true);job.weight=weight
	job.cache_script=disk.get_script()
	for field:String in ["directory","magic","format_version","extension","max_bytes"]:job.settings[field]=disk.get(field)
	_cache_write_bytes+=weight;_cache_writes.append(job)
	_finish_cache_writes()

func _finish_cache_writes(wait:=false)->void:
	while true:
		if _cache_write_task>=0:
			if not wait and not WorkerThreadPool.is_task_completed(_cache_write_task):return
			WorkerThreadPool.wait_for_task_completion(_cache_write_task)
			disk.write_us+=int(_cache_write_job.result.get("write_us",0))
			disk.written_bytes+=int(_cache_write_job.result.get("written_bytes",0))
			disk.failures+=int(_cache_write_job.result.get("failures",1))
			_cache_write_bytes-=_cache_write_job.weight
			_cache_write_job=null;_cache_write_task=-1;_writes+=1
			if _writes==1 or _writes%16==0:_trim()
		if _cache_writes.is_empty():return
		_cache_write_job=_cache_writes.pop_front()
		_cache_write_task=WorkerThreadPool.add_task(_cache_write_job.run,false,"Ember scatter cache write")
		if _cache_write_task<0:
			_cache_write_bytes-=_cache_write_job.weight;_cache_write_job=null
			disk.failures+=1;continue
		if not wait:return

class CacheWriteJob extends RefCounted:
	var key:String
	var looks:Dictionary
	var weight:=0
	var cache_script:Script
	var settings:Dictionary={}
	var result:Dictionary={}
	func run()->void:
		# Private transport/counters; no Node, live resource or caller callback
		# crosses the worker boundary. Storage retains atomic rename/checksums.
		var target=cache_script.new()
		for field:String in settings:target.set(field,settings[field])
		target.write(key,{"looks":looks},func():return false)
		result={"write_us":target.write_us,"written_bytes":target.written_bytes,"failures":target.failures}

func _trim() -> void:
	if _released:return
	_finish_cache_trim()
	if _trim_task>=0:return # Coalesce writes while the same directory is being scanned.
	_trim_job=CacheTrimJob.new()
	_trim_job.directory=disk.directory;_trim_job.extension=disk.extension
	_trim_task=WorkerThreadPool.add_task(_trim_job.run,false,"Ember scatter cache maintenance")

func _finish_cache_trim(wait:=false)->void:
	if _trim_task<0:return
	if not wait and not WorkerThreadPool.is_task_completed(_trim_task):return
	WorkerThreadPool.wait_for_task_completion(_trim_task)
	cache_trim_us+=_trim_job.elapsed_us;cache_trim_runs+=1
	_trim_task=-1;_trim_job=null

class CacheTrimJob extends RefCounted:
	# Only disposable cache paths cross this boundary. No Nodes, Resources or
	# gameplay callbacks run on the worker; completed files are still atomic.
	var directory:String
	var extension:=".edc"
	var budget:=DISK_BUDGET
	var elapsed_us:=0
	var _cancelled:=false
	var _mutex:=Mutex.new()
	func cancel()->void:
		_mutex.lock();_cancelled=true;_mutex.unlock()
	func cancelled()->bool:
		_mutex.lock();var value:=_cancelled;_mutex.unlock();return value
	func run()->void:
		var started:=Time.get_ticks_usec();_scan();elapsed_us=Time.get_ticks_usec()-started
	func _scan()->void:
		if cancelled():return
		var folder:=DirAccess.open(directory)
		if folder==null:return
		var entries:Array=[];var total:=0
		for file in folder.get_files():
			if cancelled():return
			if not file.ends_with(extension):continue
			var path:=directory.path_join(file)
			var handle:=FileAccess.open(path,FileAccess.READ)
			if handle==null:continue
			var size:=handle.get_length();handle.close()
			total+=size;entries.append([FileAccess.get_modified_time(path),path,size])
		entries.sort_custom(func(a,b):return a[0]<b[0])
		for entry in entries:
			if cancelled() or total<=budget:return
			if DirAccess.remove_absolute(entry[1])==OK:total-=entry[2]
