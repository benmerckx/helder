// A console program for the cli lane's exit policy (tests/cli/dev.mjs
// exit): it prints a few lines, then ends by itself with CODE as its exit
// code: not 0, a crash (helder dev stays and waits for a change); 0, the
// program closed (helder dev ends, exit code 0).
class Closer {
	static inline var CODE = 3;

	static function main() {
		for (i in 1...4) {
			Sys.println('closer $i');
			#if hxmc.dev
			helder.dev.Hot.framed();
			helder.dev.Hot.poll();
			#end
			Sys.sleep(0.05);
		}
		if (CODE != 0) Sys.exit(CODE);
	}
}
