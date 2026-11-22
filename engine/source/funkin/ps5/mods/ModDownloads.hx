package funkin.ps5.mods;

import funkin.ps5.PS5;
import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.Net;
import funkin.ps5.net.Net.DownloadTask;
import haxe.io.Path;
#if sys
import sys.FileSystem;
#end

enum DownloadState {
	QUEUED;
	RESOLVING;
	DOWNLOADING;
	EXTRACTING;
	INSTALLING;
	DONE;
	FAILED;
	CANCELLED;
}

/** One mod being fetched and installed. */
class ModJob {
	public var mod:OnlineMod;
	public var file:OnlineModFile;
	public var state:DownloadState = QUEUED;
	public var progress:Float = 0;
	public var received:Float = 0;
	public var total:Float = -1;
	public var message:String = "Waiting...";
	public var log:Array<String> = [];
	public var installed:Array<String> = [];
	public var error:String = null;
	public var task:DownloadTask;
	public var cancelled:Bool = false;
	public var onChange:ModJob->Void;

	public function new(mod:OnlineMod, file:OnlineModFile) {
		this.mod = mod;
		this.file = file;
	}

	public var finished(get, never):Bool;
	function get_finished() return state == DONE || state == FAILED || state == CANCELLED;

	public function cancel() {
		if (finished) return;
		cancelled = true;
		if (task != null) task.cancelled = true;
	}

	@:allow(funkin.ps5.mods.ModDownloads)
	function set(state:DownloadState, message:String) {
		this.state = state;
		this.message = message;
		if (onChange != null) onChange(this);
	}

	@:allow(funkin.ps5.mods.ModDownloads)
	function addLog(line:String) {
		log.push(line);
		Logs.trace('[Mods] $line');
	}
}

/**
 * The queue behind the mod browser: one download at a time, each one
 * resolved (Game Jolt), downloaded with progress, unpacked and installed.
 * Jobs keep running while the player moves between menus.
 */
class ModDownloads {
	public static var jobs:Array<ModJob> = [];
	public static var onAnyChange:ModJob->Void;
	static var running:ModJob = null;

	public static function enqueue(mod:OnlineMod, file:OnlineModFile):ModJob {
		var job = new ModJob(mod, file);
		job.onChange = j -> if (onAnyChange != null) onAnyChange(j);
		jobs.push(job);
		next();
		return job;
	}

	public static var active(get, never):Int;
	static function get_active() return [for (j in jobs) if (!j.finished) j].length;

	public static function clearFinished() {
		jobs = [for (j in jobs) if (!j.finished) j];
	}

	static function next() {
		if (running != null && !running.finished) return;
		running = null;
		for (j in jobs) if (j.state == QUEUED && !j.cancelled) {
			running = j;
			start(j);
			return;
		}
	}

	static function start(job:ModJob) {
		if (job.file.needsResolve && job.mod.source == GAMEJOLT) {
			job.set(RESOLVING, "Asking Game Jolt for the download...");
			GameJolt.resolveDownload(job.file, url -> {
				job.file.url = url;
				download(job);
			}, err -> fail(job, err));
		} else download(job);
	}

	static function download(job:ModJob) {
		if (job.cancelled) {
			finishCancelled(job);
			return;
		}
		PS5.ensureDir(PS5.downloadsPath);
		var safeName = PS5.safeFolderName(job.file.name);
		if (Path.extension(safeName) == "") safeName += ".zip";
		var archive = PS5.downloadsPath + '${job.mod.source}-${job.mod.id}-${job.file.id}-$safeName';
		job.set(DOWNLOADING, 'Downloading ${job.file.name}...');
		var task = new DownloadTask();
		job.task = task;
		task.onProgress = (got, total) -> {
			job.received = got;
			job.total = total > 0 ? total : job.file.size;
			job.progress = job.total > 0 ? Math.min(1, got / job.total) : 0;
			job.message = 'Downloading: ${PS5.formatBytes(got)}' + (job.total > 0 ? ' of ${PS5.formatBytes(job.total)}' : "");
			if (job.onChange != null) job.onChange(job);
		};
		task.onError = err -> {
			if (job.cancelled) finishCancelled(job) else fail(job, 'Download failed: $err');
		};
		task.onDone = path -> extract(job, path);
		Net.download(job.file.url, archive, task);
	}

	static function extract(job:ModJob, archive:String) {
		if (job.cancelled) {
			finishCancelled(job);
			return;
		}
		job.progress = 0;
		job.set(EXTRACTING, "Unpacking...");
		var unpackDir = PS5.downloadsPath + 'unpack-${job.mod.source}-${job.mod.id}-${Std.int(Date.now().getTime() / 1000)}';
		Net.runAsync(() -> {
			try {
				var lower = archive.toLowerCase();
				var count = 0;
				if (Archive.isArchive(lower)) {
					count = Archive.extract(archive, unpackDir, (n, name) -> {
						if (n % 25 == 0) Net.onMain(() -> {
							job.message = 'Unpacking: $n files';
							if (job.onChange != null) job.onChange(job);
						});
					}, () -> job.cancelled);
				} else {
					throw 'The file "${job.file.name}" is not an archive the port can open (.zip, .7z or .rar).';
				}
				Net.onMain(() -> job.addLog('Unpacked $count files'));
				Net.onMain(() -> job.set(INSTALLING, "Installing..."));
				var installed = ModInstaller.install(unpackDir, job.mod, line -> Net.onMain(() -> job.addLog(line)));
				PS5.deleteDir(unpackDir);
				#if sys
				try FileSystem.deleteFile(archive) catch (e:Dynamic) {}
				#end
				Net.onMain(() -> {
					job.installed = installed;
					job.progress = 1;
					job.set(DONE, installed.length == 1 ? 'Installed as "${installed[0]}"' : 'Installed ${installed.length} mods');
					next();
				});
			} catch (e:Dynamic) {
				PS5.deleteDir(unpackDir);
				var msg = Std.string(e);
				Net.onMain(() -> if (job.cancelled) finishCancelled(job) else fail(job, msg));
			}
		});
	}

	static function fail(job:ModJob, err:String) {
		job.error = err;
		job.addLog(err);
		job.set(FAILED, err);
		next();
	}

	static function finishCancelled(job:ModJob) {
		job.set(CANCELLED, "Cancelled");
		next();
	}
}
