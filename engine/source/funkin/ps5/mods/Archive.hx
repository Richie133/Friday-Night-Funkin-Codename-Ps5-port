package funkin.ps5.mods;

import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Unpacks the archives mods come in: .zip, .7z and .rar (RAR 4 and 5), plus .tar.gz
 * and friends, through libarchive. Blocking: call it from a worker thread.
 *
 * Entries that would land outside the destination (absolute paths, "..") are skipped,
 * so a hostile archive cannot write anywhere else on the console.
 */
#if (cpp && !NO_LIBARCHIVE)
@:buildXml('
<target id="haxe">
	<lib name="-larchive" if="linux" unless="ps5"/>
</target>
<files id="haxe">
	<!-- the console build: libarchive from PacBrew (ps5/tools/build-ps5.sh), linked with the app;
	     the generated code\'s warnings are left out of the log -->
	<compilerflag value="-I$${PS5_ARCHIVE_INCLUDE}" if="PS5_ARCHIVE_INCLUDE"/>
	<compilerflag value="-w" if="ps5"/>
</files>
')
@:cppFileCode('
#include <archive.h>
#include <archive_entry.h>
#include <stdio.h>
#include <string.h>

struct Ps5Archive {
	struct archive *a;
	struct archive_entry *entry;
	char error[512];
};

static void *ps5ar_open(const char *path) {
	Ps5Archive *h = (Ps5Archive *)calloc(1, sizeof(Ps5Archive));
	h->a = archive_read_new();
	archive_read_support_filter_all(h->a);
	archive_read_support_format_all(h->a);
	hx::EnterGCFreeZone();
	int rc = archive_read_open_filename(h->a, path, 1 << 16);
	hx::ExitGCFreeZone();
	if (rc != ARCHIVE_OK) {
		snprintf(h->error, sizeof(h->error), "%s", archive_error_string(h->a) ? archive_error_string(h->a) : "cannot open");
	}
	return h;
}

static const char *ps5ar_error(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	if (h->error[0]) return h->error;
	const char *e = archive_error_string(h->a);
	return e ? e : "";
}

/* 1: an entry, 0: the end, -1: an error */
static int ps5ar_next(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	if (h->error[0]) return -1;
	hx::EnterGCFreeZone();
	int rc = archive_read_next_header(h->a, &h->entry);
	hx::ExitGCFreeZone();
	if (rc == ARCHIVE_EOF) return 0;
	if (rc == ARCHIVE_OK || rc == ARCHIVE_WARN) return 1;
	snprintf(h->error, sizeof(h->error), "%s", archive_error_string(h->a) ? archive_error_string(h->a) : "broken archive");
	return -1;
}

static const char *ps5ar_name(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	const char *n = archive_entry_pathname_utf8(h->entry);
	if (!n) n = archive_entry_pathname(h->entry);
	return n ? n : "";
}

static int ps5ar_isdir(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	return archive_entry_filetype(h->entry) == AE_IFDIR;
}

static int ps5ar_isfile(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	return archive_entry_filetype(h->entry) == AE_IFREG;
}

static double ps5ar_size(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	return (double)archive_entry_size(h->entry);
}

static int ps5ar_extract(void *p, const char *dest) {
	Ps5Archive *h = (Ps5Archive *)p;
	int result = 0;
	hx::EnterGCFreeZone();
	FILE *out = fopen(dest, "wb");
	if (!out) {
		snprintf(h->error, sizeof(h->error), "cannot write %s", dest);
		result = -1;
	} else {
		const void *buf;
		size_t size;
		la_int64_t offset;
		for (;;) {
			int rc = archive_read_data_block(h->a, &buf, &size, &offset);
			if (rc == ARCHIVE_EOF) break;
			if (rc != ARCHIVE_OK && rc != ARCHIVE_WARN) {
				snprintf(h->error, sizeof(h->error), "%s", archive_error_string(h->a) ? archive_error_string(h->a) : "read error");
				result = -1;
				break;
			}
			if (size > 0 && fwrite(buf, 1, size, out) != size) {
				snprintf(h->error, sizeof(h->error), "disk full while writing %s", dest);
				result = -1;
				break;
			}
		}
		fclose(out);
	}
	hx::ExitGCFreeZone();
	return result;
}

static void ps5ar_close(void *p) {
	Ps5Archive *h = (Ps5Archive *)p;
	if (h->a) {
		archive_read_close(h->a);
		archive_read_free(h->a);
	}
	free(h);
}
')
#end
class Archive {
	public static var supportedExtensions:Array<String> = ["zip", "7z", "rar", "tar", "gz", "tgz", "xz", "bz2", "zst"];

	public static function isArchive(name:String):Bool {
		var ext = Path.extension(name).toLowerCase();
		return supportedExtensions.contains(ext);
	}

	/**
	 * Unpacks `archive` into the folder `dest`.
	 * @param onEntry called (on the calling thread) with the number of entries done so far and the current name
	 * @return the number of files written
	 */
	public static function extract(archive:String, dest:String, ?onEntry:Int->String->Void, ?isCancelled:Void->Bool):Int {
		#if sys
		funkin.ps5.PS5.ensureDir(dest);
		#end
		#if (cpp && !NO_LIBARCHIVE)
		var handle:cpp.RawPointer<cpp.Void> = untyped __cpp__("ps5ar_open({0}.utf8_str())", archive);
		var written = 0;
		var count = 0;
		try {
			while (true) {
				if (isCancelled != null && isCancelled()) throw "Cancelled";
				var rc:Int = untyped __cpp__("ps5ar_next({0})", handle);
				if (rc == 0) break;
				if (rc < 0) throw 'Archive error: ' + readError(handle);
				var name:String = untyped __cpp__("::String::create(ps5ar_name({0}))", handle);
				count++;
				var target = safeJoin(dest, name);
				if (target == null) continue;
				var isDir:Bool = untyped __cpp__("ps5ar_isdir({0}) != 0", handle);
				var isFile:Bool = untyped __cpp__("ps5ar_isfile({0}) != 0", handle);
				if (isDir) {
					mkdirs(target);
				} else if (isFile) {
					mkdirs(Path.directory(target));
					var res:Int = untyped __cpp__("ps5ar_extract({0}, {1}.utf8_str())", handle, target);
					if (res < 0) throw readError(handle);
					written++;
				}
				if (onEntry != null) onEntry(count, name);
			}
		} catch (e:Dynamic) {
			untyped __cpp__("ps5ar_close({0})", handle);
			throw e;
		}
		untyped __cpp__("ps5ar_close({0})", handle);
		return written;
		#elseif sys
		// Without libarchive only .zip is understood.
		if (Path.extension(archive).toLowerCase() != "zip") throw "Only .zip archives can be opened in this build";
		var input = File.read(archive, true);
		var entries = haxe.zip.Reader.readZip(input);
		input.close();
		var written = 0, count = 0;
		for (entry in entries) {
			if (isCancelled != null && isCancelled()) throw "Cancelled";
			count++;
			var target = safeJoin(dest, entry.fileName);
			if (target == null) continue;
			if (entry.fileName.endsWith("/")) {
				mkdirs(target);
			} else {
				mkdirs(Path.directory(target));
				File.saveBytes(target, haxe.zip.Reader.unzip(entry));
				written++;
			}
			if (onEntry != null) onEntry(count, entry.fileName);
		}
		return written;
		#else
		throw "Archives are not supported on this platform";
		#end
	}

	#if (cpp && !NO_LIBARCHIVE)
	static function readError(handle:cpp.RawPointer<cpp.Void>):String {
		return untyped __cpp__("::String::create(ps5ar_error({0}))", handle);
	}
	#end

	/** Joins an archive entry name onto `dest`, or returns null if it would escape it. */
	public static function safeJoin(dest:String, name:String):Null<String> {
		var n = name.replace("\\", "/");
		while (n.startsWith("./")) n = n.substr(2);
		if (n == "" || n.startsWith("/") || ~/^[A-Za-z]:/.match(n)) return null;
		var parts = [];
		for (p in n.split("/")) {
			if (p == "" || p == ".") continue;
			if (p == "..") return null;
			parts.push(p);
		}
		if (parts.length == 0) return null;
		// macOS zips carry resource forks that are of no use here
		if (parts[0] == "__MACOSX" || parts[parts.length - 1] == ".DS_Store") return null;
		return Path.join([dest].concat(parts));
	}

	public static function mkdirs(path:String) {
		#if sys
		if (path == null || path == "" || FileSystem.exists(path)) return;
		mkdirs(Path.directory(path));
		try FileSystem.createDirectory(path) catch (e:Dynamic) {}
		#end
	}
}
