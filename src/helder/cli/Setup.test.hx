package helder.cli;

import helder.cli.Options.Usage;
import helder.cli.Setup.Advice;
import helder.test.Test;

// helder setup's pure parts: its command line (the platform, then the
// entry), where its keys go (never in the project), what to fix when
// Google refuses the service account. (Its calls: tests/pack/publish.mjs.)
function tests() {
	final usage = (f:() -> Void) -> {
		var e = throws(f);
		return e is Usage ? (e : Usage).message : 'not a Usage: $e';
	};
	final parse = (args:Array<String>) -> Options.parse("setup", args, _ -> true);

	test("the platform, then the entry; -o, --github", () -> {
		var o = parse(["ios", "examples/todo", "-o", "/keys", "--github"]);
		equals([o.positionals[0], o.positionals[1], o.out], ["ios", "examples/todo", "/keys"]);
		assert(o.has("github"), "--github");
		equals(parse(["android"]).positionals, ["android"]);
		equals(usage(() -> parse([])), "helder setup: ios or android: helder setup ios (helder setup --help)");
		equals(usage(() -> parse(["web"])), "helder setup: web: ios or android (helder setup --help)");
		equals(usage(() -> parse(["ios", "a", "b"])), "helder setup: one entry, not a and b");
	});

	test("the keys' directory: never the project or under it", () -> {
		assert(Setup.inside("bin/keys", "."), "under .");
		assert(Setup.inside(".", "."), "the project itself");
		assert(!Setup.inside("../keys", "."), "beside it");
		assert(!Setup.inside("/elsewhere/keys", "/project"), "elsewhere");
		assert(!Setup.inside("/project-keys", "/project"), "a name that starts the same");
		equals(Setup.slug("Little Skies!"), "little-skies");
	});

	test("Google's refusals: what to fix", () -> {
		var who = "publisher@x.iam.gserviceaccount.com";
		assert(Advice.play(403, '{"error": {"status": "PERMISSION_DENIED", "message": "The caller does not have permission"}}', who, "org.x").indexOf('invite $who in Play Console') == 0, "invite");
		equals(Advice.play(403, '{"error": {"message": "Google Play Android Developer API has not been used in project 12 before or it is disabled."}}', who, "org.x", "proj"),
			"enable the Google Play Android Developer API for proj: https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com?project=proj");
		assert(Advice.play(404, "{}", who, "org.x").indexOf("Play Console has no app org.x") == 0, "no app");
		assert(Advice.play(401, "{}", who, "org.x").indexOf('$who: the token is refused') == 0, "token");
	});
}
