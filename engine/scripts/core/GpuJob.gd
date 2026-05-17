## W5 GpuJob — extends Job but runs _execute() on the render thread.
##
## Per spec 08a rule 1: RenderingDevice calls must happen on the render
## thread. Plain Job._execute runs on a WorkerThreadPool worker which
## would corrupt the GPU pipeline if it touched RenderingDevice.
##
## GpuJob's _execute is dispatched via
## RenderingServer.call_on_render_thread so RenderingDevice calls
## inside it are safe.
##
## Usage:
##   class MyGpuJob extends GpuJob:
##       func _execute() -> Variant:
##           if is_cancelled() or JobScheduler.is_shutting_down():
##               return null
##           var rid := RenderingDevice.texture_create(...)
##           GpuResourceTracker.register(rid, "my_system", "texture")
##           # ... compute ...
##           return result
##
## Submit just like a regular Job: JobScheduler.submit(MyGpuJob.new()).
## JobScheduler detects the GpuJob subclass + routes appropriately
## (Phase 2.5 lesson: scheduler-side routing lives in JobScheduler.gd,
## not here; this class is just a marker + the bridge method).

class_name GpuJob extends Job


## Internal bridge method that the scheduler invokes via
## RenderingServer.call_on_render_thread. Marks status RUNNING +
## delegates to _execute on the render thread.
##
## DO NOT call directly. JobScheduler routes here.
func _run_on_render_thread() -> void:
	started_at_ms = Time.get_ticks_msec()
	status = Status.RUNNING
	if is_cancelled():
		status = Status.CANCELLED
		completed_at_ms = Time.get_ticks_msec()
		return
	var r: Variant = _execute()
	completed_at_ms = Time.get_ticks_msec()
	if is_cancelled():
		status = Status.CANCELLED
		return
	if error != "":
		status = Status.FAILED
		return
	result = r
	status = Status.COMPLETED
