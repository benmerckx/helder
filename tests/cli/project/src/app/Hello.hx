package app;

// a main in a package: `helder build tests/cli/project/src/app/Hello.hx`
// takes src/ as its class path (one up from app/)
class Hello {
	static function main()
		Sys.println("hello from app.Hello, " + Greeting.text());
}
