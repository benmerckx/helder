package helder.cli;

import helder.test.Test;

// helder.json's listing (Listing): its shared fields checked against the
// stores' limits, the stores' own attributes passed through whatever their
// names, "${NAME}" from the environment, the description from a file;
// what differs from what a store has
function tests() {
	function error(listing:Dynamic):String
		return Std.string(throws(() -> HelderJson.parse(haxe.Json.stringify({name: "Skies", listing: listing}))));

	test("listing: read beside the manifest, the stores' own attributes as they are", () -> {
		var h = HelderJson.parse(haxe.Json.stringify({
			name: "Skies",
			listing: {
				subtitle: "Mini golf",
				keywords: ["golf", "puzzle"],
				appStore: {ageRating: {aFieldAppleAddsLater: "NONE"}, reviewDetail: {contactPhone: "${PHONE}"}},
				play: {listing: {video: "https://youtu.be/x"}},
				locales: {"nl-NL": {subtitle: "Minigolf", appStore: {versionLocalization: {promotionalText: "Hallo"}}}}
			}
		}));
		equals([h.listing.subtitle, h.listing.appStore.ageRating.aFieldAppleAddsLater, h.listing.play.listing.video], ["Mini golf", "NONE", "https://youtu.be/x"]);
		equals(Listing.languages(h.listing), [null, "nl-NL"]);
		equals(Listing.fields(h.listing, ".", "nl-NL").subtitle, "Minigolf");
	});
	test("listing: ${NAME} from the environment, left out when it is not set", () -> {
		Sys.putEnv("HELDER_LISTING_TEST_PHONE", "+32 1 234");
		var f = Listing.fields({appStore: {reviewDetail: {contactPhone: "${HELDER_LISTING_TEST_PHONE}", contactEmail: "${HELDER_LISTING_TEST_UNSET}"}}}, ".");
		equals([f.appStore.reviewDetail.contactPhone, Std.string(Reflect.hasField(f.appStore.reviewDetail, "contactEmail"))], ["+32 1 234", "false"]);
	});
	test("listing: the description from a file beside helder.json", () -> {
		var dir = "bin/test/listing";
		TestCommand.mkdirs(dir);
		sys.io.File.saveContent('$dir/description.txt', "Line one.\r\n\r\nLine two.\r\n");
		equals(Listing.fields({description: "description.txt"}, dir).description, "Line one.\n\nLine two.");
		equals(Listing.fields({description: "Just text."}, dir).description, "Just text.");
	});
	test("listing: what differs from the store's", () -> {
		var want:haxe.DynamicAccess<Dynamic> = {title: "Skies", shortDescription: "Golf", keywords: "a,b"};
		var d = Listing.differ(want, {title: "Skies", shortDescription: "Old"});
		var keys = [for (k in d.keys()) k];
		keys.sort(Reflect.compare);
		equals(keys, ["keywords", "shortDescription"]);
	});
	test("listing: mistakes, in helder.json's names", () -> {
		equals(error("x"), "helder.json: listing: an object");
		equals(error({tagline: "x"}).indexOf("helder.json: listing.tagline: not one of"), 0);
		equals(error({subtitle: "a subtitle well over thirty characters"}), "helder.json: listing.subtitle: over 30 characters (the store's limit)");
		equals(error({keywords: "golf"}), "helder.json: listing.keywords: an array of strings");
		equals(error({privacy: "http://x"}), "helder.json: listing.privacy: an https URL");
		equals(error({appStore: {ageRating: "none"}}), "helder.json: listing.appStore.ageRating: an object of the store's attributes");
		equals(error({appStore: {screenshots: {}}}).indexOf("helder.json: listing.appStore.screenshots: not one of"), 0);
		equals(error({locales: {"nl-NL": {email: "x"}}}).indexOf("helder.json: listing.locales.nl-NL.email: not one of"), 0);
	});
}
