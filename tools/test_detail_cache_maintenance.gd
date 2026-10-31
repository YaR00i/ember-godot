extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="user://ember-tests/cache-maintenance-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 1000:
		var file:=FileAccess.open(folder.path_join("%04d.edc"%i),FileAccess.WRITE)
		file.store_buffer(PackedByteArray([1,2,3,4]));file.close()
	var prep:=Preparation.new();prep.disk.directory=folder
	var started:=Time.get_ticks_usec();prep._trim();var elapsed:=Time.get_ticks_usec()-started
	check(elapsed<8333,"cache maintenance admission must not block an interactive frame")
	var task:int=prep._trim_task;prep._trim()
	check(prep._trim_task==task,"pending maintenance coalesces repeated writes")
	prep._release()
	check(prep._trim_task<0 and prep._trim_job==null,"release joins maintenance without a late callback")
	var source_path:=folder.path_join("authoring.tres")
	var source_file:=FileAccess.open(source_path,FileAccess.WRITE);source_file.store_string("source");source_file.close()
	var job:=Preparation.CacheTrimJob.new();job.directory=folder;job.budget=1000
	task=WorkerThreadPool.add_task(job.run)
	while not WorkerThreadPool.is_task_completed(task):await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var bytes:=0
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".edc"):
			var cached:=FileAccess.open(folder.path_join(file),FileAccess.READ);bytes+=cached.get_length();cached.close()
	check(bytes<=1000,"completed maintenance enforces the same disk budget")
	var cancelled:=Preparation.CacheTrimJob.new();cancelled.directory=folder;cancelled.budget=0;cancelled.cancel()
	task=WorkerThreadPool.add_task(cancelled.run)
	while not WorkerThreadPool.is_task_completed(task):await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	check(FileAccess.get_file_as_string(source_path)=="source","maintenance never removes files outside the derived cache extension")
	var after:=0
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".edc"):after+=1
	check(after*4==bytes,"cancelled maintenance deletes no further entries")
	print("DETAIL_CACHE_MAINTENANCE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"main_us":elapsed}))
	quit(0 if errors.is_empty() else 1)
