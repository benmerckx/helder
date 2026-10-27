// A class Tailwind.hx does not know is an error at the class.
// expect: UnknownClass.hx:6: characters 53-64
// expect: unknown class bg-blue-500
class UnknownClass {
	static function main() {
		var r = helder.theme.Tw.rules("button", "h-9 px-4 bg-blue-500 rounded-md");
	}
}
