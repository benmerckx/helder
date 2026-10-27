package helder.async;

import haxe.io.Bytes;
import helder.async.Io;
import helder.async.Stream;

// A child process on the loop: its output read and its exit awaited without
// blocking. Natively (hxmc.NativeSys.processRun) its pipes are descriptors:
// on POSIX non-blocking ones the backend polls, and its exit a descriptor too
// on Linux (a pidfd), else a waitpid at each poll (macOS); on Windows a thread
// reads each pipe and one waits for the exit (posting to the loop). On Eval,
// sys.io.Process with the same threads.
//
//   var p = new Process("haxe", ["build.hxml"], {cwd: "app", env: env});
//   var out = new Reader(p.stdout);
//   var line; while ((line = out.readLine()) != null) Sys.println(line);
//   var code = p.wait();
//   p.stop();    // or: SIGTERM, then SIGKILL if it has not exited within 2 s
class Process {
	public final pid:Int;
	public final stdout:Source;
	public final stderr:Source;
	public final stdin:Sink;
	// (natively: readable once it exited, Linux's pidfd, else -1; Eval: the process)
	@:allow(helder.async) var exitFd = -1;
	@:allow(helder.async) var proc:Null<sys.io.Process>;
	// (a thread waits for its exit)
	@:allow(helder.async) var waited = false;
	var code:Null<Int>;
	final handles:Array<Handle>;

	// cmd found on the PATH; args each passed as they are (no shell); options:
	// cwd, the child's working directory (null: this process's; one that does
	// not exist: no process, an exception), env, its whole environment, which
	// replaces this process's (null: inherit it; Process.environment() is a
	// copy to change)
	public function new(cmd:String, args:Array<String>, ?options:ProcessOptions) {
		var cwd = options?.cwd, env = options?.env;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var fds = [0, 0, 0];
		pid = hxmc.NativeSys.processRun(cmd, args, fds, cwd, env);
		if (!Handle.WINDOWS) {
			for (fd in fds)
				hxmc.NativeSys.fileSetBlocking(fd, false);
			exitFd = hxmc.NativeSys.processExitFd(pid);
		}
		handles = [for (fd in fds) new Handle(null, fd)];
		#else
		// (Eval: the directory and the environment set around the spawn)
		var dir = Sys.getCwd(), saved = env == null ? null : Sys.environment();
		if (cwd != null) Sys.setCwd(cwd);
		if (env != null) {
			for (k in saved.keys()) if (!env.exists(k)) Sys.putEnv(k, null);
			for (k => v in env) Sys.putEnv(k, v);
		}
		var p = try new sys.io.Process(cmd, args) catch (e:Dynamic) {
			restore(dir, env, saved);
			throw e;
		}
		restore(dir, env, saved);
		pid = p.getPid();
		proc = p;
		handles = [new Handle(null, -1, null, p.stdin), new Handle(null, -1, p.stdout), new Handle(null, -1, p.stderr)];
		#end
		stdin = new Pipe(handles[0]);
		stdout = new Pipe(handles[1]);
		stderr = new Pipe(handles[2]);
	}

	#if !(target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	static function restore(dir:String, env:Null<Map<String, String>>, saved:Null<Map<String, String>>) {
		Sys.setCwd(dir);
		if (env == null) return;
		for (k in env.keys()) if (!saved.exists(k)) Sys.putEnv(k, null);
		for (k => v in saved) Sys.putEnv(k, v);
	}
	#end

	// a copy of this process's environment, to change and give to a child
	public static function environment():Map<String, String> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return hxmc.NativeSys.environment();
		#else
		return Sys.environment();
		#end
	}

	// its exit code, once it exited (killed by a signal: 128 + the signal)
	@:coroutine public function wait():Int {
		if (code == null) code = new Op(Exit, null, null, 0, 0, "", 0, this).run().result;
		return code;
	}

	// (the backend's: it exited, with this code)
	@:allow(helder.async) function reaped(c:Int) {
		code = c;
		closeExitFd();
	}

	// whether it exited (and was waited for)
	public function exited():Bool
		return code != null;

	// no more input (the child reads the end of its stdin)
	public function closeStdin()
		close1(handles[0]);

	// SIGKILL (Windows: TerminateProcess)
	public function kill()
		signal(Signal.SIGKILL);

	// a signal: SIGINT, SIGTERM or SIGKILL (Windows: any of them ends it,
	// its exit code 128 + the signal); false when it is gone already
	public function signal(sig:Signal):Bool {
		if (code != null) return false;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return hxmc.NativeSys.processSignal(pid, sig);
		#else
		// (Eval: SIGKILL alone)
		proc.kill();
		return true;
		#end
	}

	// asked to end (SIGTERM), then ended (SIGKILL) if it has not exited
	// within `grace` seconds; its exit code
	@:coroutine public function stop(grace = 2.0):Int {
		if (code != null) return code;
		var p = this;
		signal(Signal.SIGTERM);
		return try Async.timeout(grace, _ -> p.wait()) catch (_:Async.TimeoutException) {
			signal(Signal.SIGKILL);
			wait();
		}
	}

	// the pipes closed (after wait: they may still hold output)
	public function close() {
		for (h in handles)
			close1(h);
		closeExitFd();
	}

	function closeExitFd() {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (exitFd >= 0) hxmc.NativeSys.fileClose(exitFd);
		#end
		exitFd = -1;
	}

	function close1(h:Handle) {
		if (h.closed) return;
		h.closed = true;
		if (h.fd >= 0) {
			#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi") hxmc.NativeSys.fileClose(h.fd); #end
		} else if (h.output != null) h.output.close() else h.input.close();
	}

	// (the backend's: the exit code, -1 while it runs)
	@:allow(helder.async) function poll():Int {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return hxmc.NativeSys.processWait(pid, false);
		#else
		return -1;
		#end
	}
}

typedef ProcessOptions = {
	?cwd:String,
	?env:Map<String, String>
}

private class Pipe implements Source implements Sink {
	final handle:Handle;

	public function new(h)
		handle = h;

	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		if (handle.closed) return 0;
		return new Op(Read, handle, b, pos, len).run().result;
	}

	@:coroutine public function write(b:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			var n = new Op(Write, handle, b, pos, len).run().result;
			pos += n;
			len -= n;
		}
	}
}
