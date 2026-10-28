import helder.async.Async;
import helder.jobs.Jobs;
import helder.os.App;
import helder.os.Window;

// App.run turning helder.async's loop (`bun run test app`; Linux: Xvfb): a
// task awaits Async.delay, then a job, inside the frame loop, while each
// frame waits for the next event (App.wait(1), as an idle ui does). The
// timer and the job's reply (a worker's post) must end the wait: neither
// waits out its second, and the frames stay few (the loop sleeps between).
class AppLoopTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail:String) {
		Sys.println('AppLoopTest: ${ok ? "ok" : "FAIL"}: $what ($detail)');
		if (!ok) failed++;
	}

	// (a GC job: 100 ms asleep on its thread, then its time)
	static function nap(ms:Int):Float {
		Sys.sleep(ms / 1000);
		return haxe.Timer.stamp();
	}

	static function main() {
		var window = new Window("AppLoopTest", 64, 64);
		var frames = 0, t0 = haxe.Timer.stamp();
		var timerLate = -1.0, replyLate = -1.0, onWorker = false;
		Async.launch(_ -> {
			var a = haxe.Timer.stamp();
			Async.delay(0.1);
			timerLate = haxe.Timer.stamp() - a - 0.1;
			var ended = Jobs.run(nap, 100);
			replyLate = haxe.Timer.stamp() - ended;
			App.quit();
		});
		App.run(() -> {
			frames++;
			App.wait(1);
			if (haxe.Timer.stamp() - t0 > 5) App.quit();
		}, e -> switch e.kind {
			case Close: window.close();
			case _:
		});
		var ms = (v:Float) -> Std.string(Math.round(v * 10000) / 10);
		check("the timer ends App.wait", timerLate >= 0 && timerLate < 0.05, 'late by ${ms(timerLate)} ms');
		check("the job's reply ends App.wait", replyLate >= 0 && replyLate < 0.05, 'resumed ${ms(replyLate)} ms after the job');
		check("the loop sleeps between", frames < 30, '$frames frames in ${ms(haxe.Timer.stamp() - t0)} ms');
		Sys.exit(failed > 0 ? 1 : 0);
	}
}
