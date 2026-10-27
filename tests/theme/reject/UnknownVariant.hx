// So is a variant it does not know.
// expect: UnknownVariant.hx:6: characters 48-63
// expect: unknown variant open-sesame: in open-sesame:h-8
class UnknownVariant {
	static function main() {
		var r = helder.theme.Tw.rules("button", "h-9 open-sesame:h-8");
	}
}
