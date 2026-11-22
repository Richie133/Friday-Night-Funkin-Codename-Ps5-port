package funkin.ps5.net;

import haxe.Http;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Output;
#if sys
import sys.FileSystem;
import sys.io.File;
import sys.thread.Deque;
import sys.thread.Mutex;
import sys.thread.Thread;
#end

/**
 * Small HTTP(S) client for the mod browser.
 *
 * Every request runs on one of a few worker threads; its result is handed back
 * on the main thread (from `FlxG.signals.preUpdate`), so callbacks can touch sprites.
 * Redirects are followed, and file downloads are written straight to disk
 * with progress, so a 1 GB mod never has to fit in memory.
 */
class Net {
	public static var userAgent:String = 'CodenameEngine-PS5/${funkin.ps5.PS5.VERSION} (+${funkin.ps5.PS5.REPO_URL})';
	public static inline var MAX_REDIRECTS:Int = 8;
	public static inline var WORKERS:Int = 3;

	#if sys
	static var jobs:Deque<Void->Void>;
	static var results:Deque<Void->Void>;
	static var started:Bool = false;
	static var caLoaded:Bool = false;
	#end

	/** Set to true by the test build to answer from fixture files instead of the network. */
	public static var fixtures:Null<String> = null;

	public static function init() {
		#if sys
		if (started) return;
		started = true;
		jobs = new Deque();
		results = new Deque();
		for (i in 0...WORKERS) Thread.create(worker);
		FlxG.signals.preUpdate.add(pump);
		loadCertificates();
		#end
	}

	#if sys
	static function worker() {
		while (true) {
			var job = jobs.pop(true);
			try job() catch (e:Dynamic) {
				Logs.warn('[Net] worker error: $e');
			}
		}
	}

	static function pump() {
		var count = 0;
		var next:Void->Void;
		// a few per frame so a burst of thumbnails can't stall a frame
		while (count++ < 16 && (next = results.pop(false)) != null) {
			try next() catch (e:Dynamic) Logs.warn('[Net] callback error: $e');
		}
	}

	/**
	 * The console has no certificate store an app can read, so the Mozilla CA bundle
	 * ships in assets/ps5/cacert.pem and is used for every HTTPS connection.
	 */
	static function loadCertificates() {
		if (caLoaded) return;
		caLoaded = true;
		for (path in [funkin.ps5.PS5.appRoot + "assets/ps5/cacert.pem", "./assets/ps5/cacert.pem"]) {
			if (!FileSystem.exists(path)) continue;
			try {
				sys.ssl.Socket.DEFAULT_CA = sys.ssl.Certificate.loadFile(path);
				Logs.trace('[Net] certificates: $path');
				return;
			} catch (e:Dynamic) {
				Logs.warn('[Net] could not read $path: $e');
			}
		}
	}
	#end

	/** Runs `job` on a worker thread. */
	public static function runAsync(job:Void->Void) {
		init();
		#if sys
		jobs.add(job);
		#else
		job();
		#end
	}

	/** Runs `callback` on the main thread at the start of the next frame. */
	public static function onMain(callback:Void->Void) {
		#if sys
		if (results == null) init();
		results.add(callback);
		#else
		callback();
		#end
	}

	/** GET a text resource (JSON, HTML). */
	public static function getText(url:String, onDone:String->Void, onError:String->Void, ?headers:Map<String, String>) {
		runAsync(() -> {
			try {
				var bytes = requestBytes(url, null, headers);
				var text = bytes.toString();
				onMain(() -> onDone(text));
			} catch (e:Dynamic) {
				var msg = Std.string(e);
				onMain(() -> onError(msg));
			}
		});
	}

	/** POST a JSON body and read a text answer. */
	public static function postJson(url:String, body:String, onDone:String->Void, onError:String->Void) {
		runAsync(() -> {
			try {
				var bytes = requestBytes(url, body, ["Content-Type" => "application/json"]);
				var text = bytes.toString();
				onMain(() -> onDone(text));
			} catch (e:Dynamic) {
				var msg = Std.string(e);
				onMain(() -> onError(msg));
			}
		});
	}

	/** GET raw bytes (pictures). */
	public static function getBytes(url:String, onDone:Bytes->Void, onError:String->Void) {
		runAsync(() -> {
			try {
				var bytes = requestBytes(url);
				onMain(() -> onDone(bytes));
			} catch (e:Dynamic) {
				var msg = Std.string(e);
				onMain(() -> onError(msg));
			}
		});
	}

	/**
	 * Downloads `url` into `path`. `onProgress(received, total)` is called on the
	 * main thread; `total` is -1 when the server does not say.
	 */
	public static function download(url:String, path:String, task:DownloadTask) {
		runAsync(() -> {
			var part = path + ".part";
			try {
				#if sys
				var out = File.write(part, true);
				var counting = new CountingOutput(out, task);
				try {
					request(url, null, counting, null, task);
				} catch (e:Dynamic) {
					try out.close() catch (_) {}
					throw e;
				}
				out.close();
				if (task.cancelled) {
					try FileSystem.deleteFile(part) catch (_) {}
					onMain(() -> task.fail("Cancelled"));
					return;
				}
				if (FileSystem.exists(path)) FileSystem.deleteFile(path);
				FileSystem.rename(part, path);
				#end
				onMain(() -> task.finish(path));
			} catch (e:Dynamic) {
				#if sys
				try if (FileSystem.exists(part)) FileSystem.deleteFile(part) catch (_) {}
				#end
				var msg = Std.string(e);
				onMain(() -> task.fail(msg));
			}
		});
	}

	/** Blocking request on the calling (worker) thread. */
	public static function requestBytes(url:String, ?postBody:String, ?headers:Map<String, String>):Bytes {
		if (fixtures != null) return Fixtures.answer(url, postBody);
		var out = new BytesOutput();
		request(url, postBody, out, headers, null);
		return out.getBytes();
	}

	/**
	 * Follows redirects itself, because the mirrors GameBanana and Game Jolt send
	 * downloads to answer with 302s across hosts.
	 */
	static function request(url:String, postBody:Null<String>, output:Output, headers:Null<Map<String, String>>, task:Null<DownloadTask>) {
		if (fixtures != null) {
			output.write(Fixtures.answer(url, postBody));
			return;
		}
		var current = url;
		for (hop in 0...MAX_REDIRECTS) {
			var http = new Http(current);
			http.setHeader("User-Agent", userAgent);
			http.setHeader("Accept", "*/*");
			if (headers != null) for (k => v in headers) http.setHeader(k, v);
			if (postBody != null) http.setPostData(postBody);

			var status = 0;
			var redirectTo:String = null;
			var error:String = null;
			// the body of a redirect is thrown away
			var sink = new RedirectAwareOutput(output);
			http.onStatus = function(code) {
				status = code;
				if (code >= 300 && code < 400) {
					redirectTo = header(http, "Location");
					sink.discard = true;
				} else if (task != null) {
					var len = header(http, "Content-Length");
					var total = len == null ? -1.0 : Std.parseFloat(len);
					if (Math.isNaN(total)) total = -1;
					task.setTotal(total);
				}
			};
			http.onError = function(msg) error = msg;
			http.customRequest(postBody != null, sink, null, postBody != null ? "POST" : "GET");

			if (redirectTo != null) {
				current = resolve(current, redirectTo);
				postBody = null; // a 302 after a POST is followed with a GET
				continue;
			}
			if (error != null && (status < 200 || status >= 300))
				throw '$error (HTTP $status) for $current';
			if (status >= 400) throw 'HTTP $status for $current';
			return;
		}
		throw 'Too many redirects for $url';
	}

	static function header(http:Http, name:String):Null<String> {
		if (http.responseHeaders == null) return null;
		for (k => v in http.responseHeaders) if (k.toLowerCase() == name.toLowerCase()) return v;
		return null;
	}

	/** Resolves a relative `Location` against the address it came from. */
	public static function resolve(base:String, location:String):String {
		if (location.startsWith("http://") || location.startsWith("https://")) return location;
		var schemeEnd = base.indexOf("://") + 3;
		if (location.startsWith("//")) return base.substr(0, schemeEnd - 2) + location;
		var hostEnd = base.indexOf("/", schemeEnd);
		var origin = hostEnd < 0 ? base : base.substr(0, hostEnd);
		if (location.startsWith("/")) return origin + location;
		var dir = base.substr(0, base.lastIndexOf("/") + 1);
		return dir + location;
	}

	public static function urlEncode(s:String):String return StringTools.urlEncode(s);
}

/** A download in flight. Callbacks run on the main thread. */
class DownloadTask {
	public var received(default, null):Float = 0;
	public var total(default, null):Float = -1;
	public var done(default, null):Bool = false;
	public var failed(default, null):Bool = false;
	public var error(default, null):String = null;
	public var cancelled:Bool = false;

	public var onProgress:Float->Float->Void;
	public var onDone:String->Void;
	public var onError:String->Void;

	#if sys
	var lock = new Mutex();
	#end
	var pendingProgress = false;

	public function new() {}

	public var progress(get, never):Float;
	function get_progress():Float return total > 0 ? Math.min(1, received / total) : 0;

	@:allow(funkin.ps5.net)
	function setTotal(value:Float) total = value;

	@:allow(funkin.ps5.net)
	function addReceived(count:Int) {
		received += count;
		if (!pendingProgress && onProgress != null) {
			pendingProgress = true;
			Net.onMain(() -> {
				pendingProgress = false;
				if (onProgress != null) onProgress(received, total);
			});
		}
	}

	@:allow(funkin.ps5.net)
	function finish(path:String) {
		done = true;
		if (onDone != null) onDone(path);
	}

	@:allow(funkin.ps5.net)
	function fail(msg:String) {
		failed = true;
		error = msg;
		if (onError != null) onError(msg);
	}
}

private class CountingOutput extends Output {
	var out:Output;
	var task:DownloadTask;

	public function new(out:Output, task:DownloadTask) {
		this.out = out;
		this.task = task;
	}

	override public function writeByte(c:Int) {
		if (task.cancelled) throw "Cancelled";
		out.writeByte(c);
		task.addReceived(1);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (task.cancelled) throw "Cancelled";
		var n = out.writeBytes(s, pos, len);
		task.addReceived(n);
		return n;
	}
}

/** Passes the body through, unless the answer turned out to be a redirect. */
private class RedirectAwareOutput extends Output {
	public var discard:Bool = false;
	var out:Output;

	public function new(out:Output) this.out = out;

	override public function writeByte(c:Int) {
		if (!discard) out.writeByte(c);
	}

	override public function writeBytes(s:Bytes, pos:Int, len:Int):Int {
		if (discard) return len;
		return out.writeBytes(s, pos, len);
	}
}
