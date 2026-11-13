package helder.cli;

import haxe.DynamicAccess;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// helder.json's "listing": the stores' pages as text, which `helder publish
// --listing` sends with the screenshots. A few fields both stores share,
// each mapped onto the stores' own attributes; and under "play" and
// "appStore" the stores' resources by their own API names, their
// attributes sent as they are, over the shared ones: a field a store adds
// later works without helder knowing it. "locales" holds other languages'
// localized fields (the default language: Play's details', App Store
// Connect's primary locale, else en-US). A string "${NAME}" is the
// environment's NAME (a phone number kept out of a public repository; not
// set: the field left out). A field not given is left as the store has it.
//
//   "listing": {
//     "title": "Little Skies",                Play's title, App Store's name (else the app's name)
//     "subtitle": "Mini golf in the sky",     App Store's (30 characters)
//     "summary": "...",                       Play's short description (80)
//     "description": "store/description.txt" both stores' (4000; a file beside helder.json, or the text)
//     "keywords": ["mini golf", "puzzle"],    App Store's (100 together)
//     "promo": "...",                         App Store's promotional text (170)
//     "notes": "...",                         what's new (App Store's whatsNew: not on an app's first version)
//     "website", "support", "privacy":        https URLs; "email"; "copyright": "2026 Codeurs"
//     "category": "GAMES_SPORTS",             App Store's (a game's: GAMES, and this its subcategory)
//     "play": {"listing": {...}, "details": {...}, "dataSafety": "store/data-safety.csv"},
//     "appStore": {"app", "info", "infoLocalization", "version", "versionLocalization", "ageRating",
//                  "reviewDetail": {...attributes}, "categories": {"secondaryCategory": "ENTERTAINMENT"},
//                  "price": 0, "availability": {"territories": "all", "availableInNewTerritories": true}},
//     "locales": {"nl-NL": {the localized fields, "play": {"listing"}, "appStore": {"infoLocalization", "versionLocalization"}}}
//   }
//
// App Store Connect's age rating questions unanswered (null there, not
// given here) are listed, so that one Apple adds shows up. The price (0:
// free; {"amount": 0.99, "territory": "FRA"}: a base territory other
// than the USA, the others priced from it by Apple) and the availability
// (the territories: "all", or their codes, USA, BEL, ...) are sent when
// they differ from App Store Connect's. Play's data safety form is its
// CSV (exported once from Play Console: App content, Data safety, Export
// to CSV), a file beside helder.json, sent each time (Play cannot read it
// back).
class Listing {
	static final LOCALIZED = ["title", "subtitle", "summary", "description", "keywords", "promo", "notes"];
	static final SHARED = LOCALIZED.concat(["website", "support", "privacy", "email", "copyright", "category", "play", "appStore", "locales"]);
	static final PLAY = ["listing", "details", "dataSafety"];
	static final APP_STORE = [
		"app", "info", "infoLocalization", "version", "versionLocalization", "ageRating", "reviewDetail", "categories", "price", "availability"
	];
	static final LIMITS = ["title" => 30, "subtitle" => 30, "summary" => 80, "promo" => 170, "notes" => 4000];

	// helder.json's listing checked (its mistakes named by its members)
	public static function check(l:Dynamic, file:String):Dynamic {
		if (!isObject(l)) throw '$file: listing: an object';
		only(l, SHARED, "listing", file);
		localized(l, "listing", file);
		for (k in ["website", "support", "privacy"]) {
			var v:Dynamic = Reflect.field(l, k);
			if (v != null && !(Std.isOfType(v, String) && ~/^https:\/\/[^\s]+$/.match(v))) throw '$file: listing.$k: an https URL';
		}
		for (k in ["email", "copyright", "category"]) {
			var v:Dynamic = Reflect.field(l, k);
			if (v != null && !Std.isOfType(v, String)) throw '$file: listing.$k: a string';
		}
		stores(l, "listing", file, false);
		if (l.locales != null) {
			if (!isObject(l.locales)) throw '$file: listing.locales: an object of languages ("nl-NL": {...})';
			for (lang in Reflect.fields(l.locales)) {
				var o:Dynamic = Reflect.field(l.locales, lang);
				var at = 'listing.locales.$lang';
				if (!~/^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.match(lang)) throw '$file: $at: a language tag (nl-NL)';
				if (!isObject(o)) throw '$file: $at: an object';
				only(o, LOCALIZED.concat(["play", "appStore"]), at, file);
				localized(o, at, file);
				stores(o, at, file, true);
			}
		}
		return l;
	}

	static function localized(o:Dynamic, at:String, file:String) {
		for (k in LOCALIZED) {
			var v:Dynamic = Reflect.field(o, k);
			if (v == null) continue;
			if (k == "keywords") {
				if (!(Std.isOfType(v, Array) && Lambda.foreach((v : Array<Dynamic>), x -> Std.isOfType(x, String))))
					throw '$file: $at.keywords: an array of strings';
				if ((v : Array<String>).join(",").length > 100) throw '$file: $at.keywords: over 100 characters together (App Store Connect\'s limit)';
				continue;
			}
			if (!Std.isOfType(v, String)) throw '$file: $at.$k: a string';
			var max = LIMITS.get(k);
			if (max != null && !(v : String).startsWith("$") && (v : String).length > max) throw '$file: $at.$k: over $max characters (the store\'s limit)';
		}
	}

	static function stores(o:Dynamic, at:String, file:String, local:Bool) {
		for (s => keys in ["play" => PLAY, "appStore" => APP_STORE]) {
			var v:Dynamic = Reflect.field(o, s);
			if (v == null) continue;
			if (!isObject(v)) throw '$file: $at.$s: an object';
			var allowed = local ? (s == "play" ? ["listing"] : ["infoLocalization", "versionLocalization"]) : keys;
			only(v, allowed, '$at.$s', file);
			for (k in Reflect.fields(v)) {
				var x:Dynamic = Reflect.field(v, k);
				switch '$s.$k' {
					case "play.dataSafety":
						if (!Std.isOfType(x, String) || !(x : String).toLowerCase().endsWith(".csv"))
							throw '$file: $at.play.dataSafety: a .csv file beside helder.json (Play Console\'s data safety export)';
					case "appStore.price":
						price(x, '$file: $at.appStore.price');
					case "appStore.availability":
						availability(x, '$file: $at.appStore.availability');
					case _:
						if (!isObject(x)) throw '$file: $at.$s.$k: an object of the store\'s attributes';
				}
			}
		}
	}

	// listing.appStore.price: a number (0: free, in the USA's), or
	// {"amount", "territory"} (the base territory, ISO 3166-1 alpha-3)
	public static function price(v:Dynamic, at = "listing.appStore.price"):{amount:Float, territory:String} {
		var amount:Dynamic = isObject(v) ? v.amount : v, territory:Dynamic = isObject(v) ? v.territory ?? "USA" : "USA";
		if (isObject(v)) only(v, ["amount", "territory"], at, "");
		if (!(Std.isOfType(amount, Float) || Std.isOfType(amount, Int)) || amount < 0)
			throw '$at: a price (0: free), or {"amount": 0.99, "territory": "USA"}';
		if (!Std.isOfType(territory, String) || !~/^[A-Z]{3}$/.match(territory)) throw '$at.territory: a territory\'s code (USA, FRA: ISO 3166-1 alpha-3)';
		return {amount: amount, territory: territory};
	}

	// listing.appStore.availability: {"territories": "all" or ["USA", ...],
	// "availableInNewTerritories"} (new ones: all's default yes, a list's no)
	public static function availability(v:Dynamic, at = "listing.appStore.availability"):{all:Bool, territories:Array<String>, newOnes:Null<Bool>} {
		if (!isObject(v)) throw '$at: an object ({"territories": "all", "availableInNewTerritories": true})';
		only(v, ["territories", "availableInNewTerritories"], at, "");
		var t:Dynamic = v.territories ?? "all", n:Dynamic = v.availableInNewTerritories;
		if (n != null && !Std.isOfType(n, Bool)) throw '$at.availableInNewTerritories: true or false';
		if (t == "all") return {all: true, territories: [], newOnes: n};
		if (!Std.isOfType(t, Array) || (t : Array<Dynamic>).length == 0
			|| !Lambda.foreach((t : Array<Dynamic>), x -> Std.isOfType(x, String) && ~/^[A-Z]{3}$/.match(x)))
			throw '$at.territories: "all", or territories\' codes (["USA", "BEL"]: ISO 3166-1 alpha-3)';
		return {all: false, territories: t, newOnes: n};
	}

	// ---- the values to send

	// a language's fields: the default's (null) or one of locales', the
	// description read when it names a file, "${NAME}"s replaced
	public static function fields(l:Dynamic, root:String, ?lang:String):Dynamic {
		var o:Dynamic = lang == null ? l : Reflect.field(l.locales, lang);
		var out:Dynamic = {};
		for (k in Reflect.fields(o)) if (k != "locales") Reflect.setField(out, k, env(Reflect.field(o, k)));
		var d:Dynamic = out.description;
		if (Std.isOfType(d, String) && (d : String).indexOf("\n") < 0 && ~/\.(txt|md)$/.match(d)) {
			var p = root == "." || root == "" ? d : '$root/$d';
			if (FileSystem.exists(p)) out.description = File.getContent(p).replace("\r\n", "\n").trim();
		}
		if (Std.isOfType(out.description, String) && (out.description : String).length > 4000) throw 'listing.description: over 4000 characters (the stores\' limit)';
		return out;
	}

	// (a value with its "${NAME}" strings the environment's: unset, null)
	static function env(v:Dynamic):Dynamic {
		if (Std.isOfType(v, String)) {
			var r = ~/^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$/;
			if (!r.match(v)) return v;
			var e = Sys.getEnv(r.matched(1));
			return e == null || e.trim() == "" ? null : e.trim();
		}
		if (Std.isOfType(v, Array)) return [for (x in (v : Array<Dynamic>)) env(x)];
		if (isObject(v)) {
			var o:Dynamic = {};
			for (k in Reflect.fields(v)) {
				var x = env(Reflect.field(v, k));
				if (x != null) Reflect.setField(o, k, x);
			}
			return o;
		}
		return v;
	}

	// (the store's own attributes over the mapped ones, nulls left out)
	static function merged(mapped:Map<String, Dynamic>, own:Dynamic):DynamicAccess<Dynamic> {
		var out = new DynamicAccess<Dynamic>();
		for (k => v in mapped) if (v != null) out.set(k, v);
		if (own != null) for (k in Reflect.fields(own)) if (Reflect.field(own, k) != null) out.set(k, Reflect.field(own, k));
		return out;
	}

	// (the attributes of want that differ from have's)
	public static function differ(want:DynamicAccess<Dynamic>, have:Dynamic):DynamicAccess<Dynamic> {
		var out = new DynamicAccess<Dynamic>();
		for (k => v in want) {
			var h:Dynamic = have == null ? null : Reflect.field(have, k);
			if (haxe.Json.stringify(v) != haxe.Json.stringify(h)) out.set(k, v);
		}
		return out;
	}

	static function names(d:DynamicAccess<Dynamic>):String
		return [for (k in d.keys()) k].join(", ");

	public static function languages(l:Dynamic):Array<Null<String>> {
		var out:Array<Null<String>> = [null];
		if (l.locales != null) for (k in Reflect.fields(l.locales)) out.push(k);
		return out;
	}

	// ---- Google Play (in an edit Publish opened, committed there)

	@:coroutine public static function play(l:Dynamic, name:String, root:String, base:String, edit:String, token:String, lang:String, dry:Bool):Array<String> {
		var changes = [];
		var top = fields(l, root);
		// (the details: the app's contact)
		var details:Dynamic = Publish.json("GET", '$base/edits/$edit/details', token);
		var want = merged(["contactEmail" => top.email, "contactWebsite" => top.website], top.play?.details);
		var d = differ(want, details);
		if (d.keys().length > 0) {
			changes.push('Google Play details: ${names(d)}');
			if (!dry) Publish.json("PATCH", '$base/edits/$edit/details', token, d);
		}
		var deflt:String = details.defaultLanguage ?? lang;
		for (code in languages(l)) {
			var f = code == null ? top : fields(l, root, code), language = code ?? deflt;
			var have:Dynamic = try Publish.json("GET", '$base/edits/$edit/listings/$language', token) catch (_:Dynamic) null;
			var want = merged([
				"title" => f.title ?? (code == null ? name : null),
				"shortDescription" => f.summary,
				"fullDescription" => f.description
			], f.play?.listing);
			var d = differ(want, have);
			if (d.keys().length == 0) continue;
			changes.push('Google Play $language listing: ${names(d)}');
			if (dry) continue;
			// (a listing is sent whole: what it has, ours over it)
			var all:Dynamic = {language: language};
			if (have != null) for (k in Reflect.fields(have)) Reflect.setField(all, k, Reflect.field(have, k));
			for (k => v in want) Reflect.setField(all, k, v);
			Publish.json("PUT", '$base/edits/$edit/listings/$language', token, all);
		}
		return changes;
	}

	// ---- App Store Connect

	// the app's editable version of versionString (made, or the editable one
	// renamed, when there is none: App Store Connect holds one at a time),
	// its listing, the app info's (name, subtitle, privacy, categories, age
	// rating), the app's own attributes and the review's contact; the
	// version's id (null: a dry run that would make it)
	@:coroutine public static function appStore(l:Null<Dynamic>, name:String, root:String, api:String, token:String, app:Dynamic, versionString:String, dry:Bool,
			changes:Array<String>):Null<String> {
		var id:String = app.id;
		var top:Dynamic = l == null ? {} : fields(l, root);
		var primary:String = app.attributes?.primaryLocale ?? "en-US";
		var c:Asc = {api: api, token: token, dry: dry, changes: changes};
		inline function rel(type:String, rid:String):Dynamic
			return {data: {type: type, id: rid}};

		// (the version: the editable one)
		var editable = "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY";
		var versions:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/$id/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BappStoreState%5D=$editable', token).data ?? [];
		var version:Dynamic = Lambda.find(versions, v -> v.attributes?.versionString == versionString) ?? versions[0];
		if (version == null) version = create(c, "appStoreVersions", merged(["platform" => "IOS", "versionString" => versionString], null), {app: rel("apps", id)}, 'version $versionString');
		else if (version.attributes?.versionString != null && version.attributes.versionString != versionString)
			patch(c, "appStoreVersions", version.id, merged(["versionString" => versionString], null), 'version ${version.attributes.versionString}');
		if (l == null) return version?.id;
		var all:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/$id/appStoreVersions?filter%5Bplatform%5D=IOS&limit=2', token).data ?? [];
		var first = all.length <= 1;
		if (version != null) patch(c, "appStoreVersions", version.id, differ(merged(["copyright" => top.copyright], top.appStore?.version), version.attributes), 'version $versionString');

		// (the app's own attributes: contentRightsDeclaration, ...)
		if (top.appStore?.app != null) patch(c, "apps", id, differ(merged(new Map(), top.appStore.app), app.attributes), "app");
		// (the price and the territories)
		if (top.appStore?.price != null) setPrice(c, id, price(top.appStore.price));
		if (top.appStore?.availability != null) setAvailability(c, id, availability(top.appStore.availability));

		// (the app info being edited: the one not yet live)
		var infos:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/$id/appInfos', token).data ?? [];
		var info:Dynamic = Lambda.find(infos, i -> i.attributes.state != "READY_FOR_DISTRIBUTION" && i.attributes.appStoreState != "READY_FOR_SALE") ?? infos[0];
		if (info != null) {
			if (top.appStore?.info != null) patch(c, "appInfos", info.id, differ(merged(new Map(), top.appStore.info), info.attributes), "app info");
			// (categories: relationships, by the category's id)
			var cats = new DynamicAccess<Dynamic>();
			var category:Null<String> = top.category;
			if (category != null) {
				if (category.startsWith("GAMES_")) {
					cats.set("primaryCategory", "GAMES");
					cats.set("primarySubcategoryOne", category);
				} else cats.set("primaryCategory", category);
			}
			if (top.appStore?.categories != null) for (k in Reflect.fields(top.appStore.categories)) cats.set(k, Reflect.field(top.appStore.categories, k));
			var changed = new DynamicAccess<Dynamic>();
			for (k => v in cats) {
				var have:Dynamic = try Publish.json("GET", '$api/v1/appInfos/${info.id}/relationships/$k', token).data catch (_:Dynamic) null;
				if (have?.id != v) changed.set(k, v == null ? {data: null} : rel("appCategories", v));
			}
			if (changed.keys().length > 0) {
				changes.push('App Store categories: ${[for (k => v in cats) if (changed.exists(k)) '$k $v'].join(", ")}');
				if (!dry) Publish.json("PATCH", '$api/v1/appInfos/${info.id}', token, {data: {type: "appInfos", id: info.id, relationships: changed}});
			}
			// (the age rating's answers; those still unanswered named)
			var age:Dynamic = Publish.json("GET", '$api/v1/appInfos/${info.id}/ageRatingDeclaration', token).data;
			if (age != null) {
				var want = merged(new Map(), top.appStore?.ageRating);
				patch(c, "ageRatingDeclarations", age.id, differ(want, age.attributes), "age rating");
				var open = [for (k in Reflect.fields(age.attributes)) if (Reflect.field(age.attributes, k) == null && !want.exists(k)) k];
				if (open.length > 0) Term.out(Style.status("unanswered", Warn, 'App Store age rating: ${open.join(", ")} (listing.appStore.ageRating)'));
			}
			var locs:Array<Dynamic> = Publish.json("GET", '$api/v1/appInfos/${info.id}/appInfoLocalizations', token).data ?? [];
			for (code in languages(l)) {
				var f = code == null ? top : fields(l, root, code), locale = code ?? primary;
				var want = merged([
					"name" => f.title ?? (code == null ? name : null),
					"subtitle" => f.subtitle,
					"privacyPolicyUrl" => code == null ? top.privacy : f.privacy ?? top.privacy
				], f.appStore?.infoLocalization);
				var have:Dynamic = Lambda.find(locs, x -> x.attributes.locale == locale);
				if (have == null) {
					want.set("locale", locale);
					create(c, "appInfoLocalizations", want, {appInfo: rel("appInfos", info.id)}, '$locale app info');
				} else patch(c, "appInfoLocalizations", have.id, differ(want, have.attributes), '$locale app info');
			}
		}

		if (version == null) return null;
		// (the version's listing, per language)
		var vlocs:Array<Dynamic> = Publish.json("GET", '$api/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations', token).data ?? [];
		for (code in languages(l)) {
			var f = code == null ? top : fields(l, root, code), locale = code ?? primary;
			var keywords:Null<Array<String>> = f.keywords;
			var want = merged([
				"description" => f.description,
				"keywords" => keywords == null ? null : keywords.join(","),
				"promotionalText" => f.promo,
				"whatsNew" => first ? null : f.notes,
				"supportUrl" => top.support,
				"marketingUrl" => top.website
			], f.appStore?.versionLocalization);
			var have:Dynamic = Lambda.find(vlocs, x -> x.attributes.locale == locale);
			if (have == null) {
				want.set("locale", locale);
				create(c, "appStoreVersionLocalizations", want, {appStoreVersion: rel("appStoreVersions", version.id)}, '$locale listing');
			} else patch(c, "appStoreVersionLocalizations", have.id, differ(want, have.attributes), '$locale listing');
		}
		// (the review's contact and notes)
		if (top.appStore?.reviewDetail != null) {
			var want = merged(new Map(), top.appStore.reviewDetail);
			var have:Dynamic = try Publish.json("GET", '$api/v1/appStoreVersions/${version.id}/appStoreReviewDetail', token).data catch (_:Dynamic) null;
			if (have == null) create(c, "appStoreReviewDetails", want, {appStoreVersion: rel("appStoreVersions", version.id)}, "review details");
			else patch(c, "appStoreReviewDetails", have.id, differ(want, have.attributes), "review details");
		}
		return version.id;
	}

	// (every page of a list: data and included, links.next followed)
	@:coroutine static function pages(c:Asc, url:String):{data:Array<Dynamic>, included:Array<Dynamic>} {
		var data = [], included = [], next:Null<String> = url, n = 0;
		while (next != null && n++ < 50) {
			var j:Dynamic = Publish.json("GET", next, c.token);
			data = data.concat(j.data ?? []);
			included = included.concat(j.included ?? []);
			next = j.links?.next;
		}
		return {data: data, included: included};
	}

	// the price: the schedule's base territory and its manual price now,
	// against ours; else a new schedule (POST /v1/appPriceSchedules) of the
	// price point of that amount in that territory
	@:coroutine static function setPrice(c:Asc, app:String, want:{amount:Float, territory:String}) {
		var api = c.api;
		var schedule:Dynamic = try Publish.json("GET", '$api/v1/apps/$app/appPriceSchedule', c.token).data catch (_:Dynamic) null;
		var base:Null<String> = null, now:Null<Float> = null;
		if (schedule != null) {
			base = try Publish.json("GET", '$api/v1/appPriceSchedules/${schedule.id}/baseTerritory', c.token).data?.id catch (_:Dynamic) null;
			if (base != null) {
				var p = pages(c, '$api/v1/appPriceSchedules/${schedule.id}/manualPrices?include=appPricePoint&filter%5Bterritory%5D=$base&limit=200');
				var today = DateTools.format(Date.now(), "%Y-%m-%d");
				for (m in p.data) {
					var a:Dynamic = m.attributes ?? {};
					var from:Null<String> = a.startDate, until:Null<String> = a.endDate;
					if ((from == null || from <= today) && (until == null || until > today)) {
						var pp:Dynamic = Lambda.find(p.included, x -> x.type == "appPricePoints" && x.id == m.relationships?.appPricePoint?.data?.id);
						if (pp != null) now = Std.parseFloat(pp.attributes.customerPrice);
					}
				}
			}
		}
		if (base == want.territory && now != null && Math.abs(now - want.amount) < 0.001) return;
		inline function shown(v:Float):String
			return v == 0 ? "free" : Std.string(v);
		c.changes.push('App Store price: ${shown(want.amount)} (${want.territory}${base == null ? "" : ", was " + (now == null ? "?" : shown(now)) + " in " + base})');
		if (c.dry) return;
		var found:Dynamic = null, next:Null<String> = '$api/v1/apps/$app/appPricePoints?filter%5Bterritory%5D=${want.territory}&limit=200', n = 0;
		while (found == null && next != null && n++ < 50) {
			var j:Dynamic = Publish.json("GET", next, c.token);
			found = Lambda.find((j.data ?? [] : Array<Dynamic>), x -> Math.abs(Std.parseFloat(x.attributes?.customerPrice) - want.amount) < 0.001);
			next = j.links?.next;
		}
		if (found == null) throw 'App Store Connect: no price point of ${want.amount} in ${want.territory} (listing.appStore.price: one of Apple\'s prices)';
		Publish.json("POST", '$api/v1/appPriceSchedules', c.token, {
			data: {
				type: "appPriceSchedules",
				relationships: {
					app: {data: {type: "apps", id: app}},
					baseTerritory: {data: {type: "territories", id: want.territory}},
					manualPrices: {data: [{type: "appPrices", id: "${price}"}]}
				}
			},
			included: [
				{
					type: "appPrices",
					id: "${price}",
					attributes: {startDate: null},
					relationships: {appPricePoint: {data: {type: "appPricePoints", id: found.id}}}
				}
			]
		}, 201);
	}

	// the territories: none yet, an availability made (POST
	// /v2/appAvailabilities); else each territory's that differs patched
	// (availableInNewTerritories is kept as made: App Store Connect's
	// Pricing and Availability)
	@:coroutine static function setAvailability(c:Asc, app:String, want:{all:Bool, territories:Array<String>, newOnes:Null<Bool>}) {
		var api = c.api;
		var wanted:Array<String> = want.all ? [for (t in pages(c, '$api/v1/territories?limit=200').data) t.id] : want.territories;
		var newOnes = want.newOnes ?? want.all;
		var have:Dynamic = try Publish.json("GET", '$api/v1/apps/$app/appAvailabilityV2', c.token).data catch (_:Dynamic) null;
		if (have == null) {
			c.changes.push('App Store availability: ${wanted.length} territories${newOnes ? ", new ones too" : ""}');
			if (c.dry) return;
			var ref = (t:String) -> "${" + t + "}";
			Publish.json("POST", '$api/v2/appAvailabilities', c.token, {
				data: {
					type: "appAvailabilities",
					attributes: {availableInNewTerritories: newOnes},
					relationships: {
						app: {data: {type: "apps", id: app}},
						territoryAvailabilities: {data: [for (t in wanted) {type: "territoryAvailabilities", id: ref(t)}]}
					}
				},
				included: [for (t in wanted) {
					type: "territoryAvailabilities",
					id: ref(t),
					attributes: {available: true},
					relationships: {territory: {data: {type: "territories", id: t}}}
				}]
			}, 201);
			return;
		}
		var had:Null<Bool> = have.attributes?.availableInNewTerritories;
		if (want.newOnes != null && had != null && had != want.newOnes)
			Term.out(Style.status("by hand", Warn,
				'App Store availability in new territories: ${want.newOnes} (App Store Connect\'s API keeps it as made: Pricing and Availability)'));
		var list = pages(c, '$api/v2/appAvailabilities/${have.id}/territoryAvailabilities?include=territory&limit=200');
		var change:Array<{id:String, territory:String, available:Bool}> = [];
		for (ta in list.data) {
			var t:Null<String> = ta.relationships?.territory?.data?.id;
			if (t == null) continue;
			var should = wanted.contains(t), is:Bool = ta.attributes?.available == true;
			if (is != should) change.push({id: ta.id, territory: t, available: should});
		}
		if (change.length == 0) return;
		c.changes.push('App Store availability: ${[for (x in change) (x.available ? "" : "not ") + x.territory].join(", ")}');
		if (c.dry) return;
		for (x in change)
			Publish.json("PATCH", '$api/v1/territoryAvailabilities/${x.id}', c.token, {
				data: {type: "territoryAvailabilities", id: x.id, attributes: {available: x.available}}
			});
	}

	// ---- Google Play's data safety (no edit: sent whole, its CSV's text)

	@:coroutine public static function dataSafety(l:Null<Dynamic>, root:String, base:String, token:String, dry:Bool):Array<String> {
		var f:Null<String> = l?.play?.dataSafety;
		if (f == null) return [];
		var p = root == "." || root == "" || haxe.io.Path.isAbsolute(f) ? f : '$root/$f';
		if (!FileSystem.exists(p)) throw 'listing.play.dataSafety: $p: no such file (Play Console: App content, Data safety, Export to CSV)';
		if (!dry) Publish.json("POST", '$base/dataSafety', token, {safetyLabels: File.getContent(p)});
		return ['Google Play data safety: $f'];
	}

	@:coroutine static function patch(c:Asc, type:String, rid:String, d:DynamicAccess<Dynamic>, what:String) {
		if (d.keys().length == 0) return;
		c.changes.push('App Store $what: ${names(d)}');
		if (!c.dry) Publish.json("PATCH", '${c.api}/v1/$type/$rid', c.token, {data: {type: type, id: rid, attributes: d}});
	}

	@:coroutine static function create(c:Asc, type:String, attributes:DynamicAccess<Dynamic>, relationships:Dynamic, what:String):Null<Dynamic> {
		c.changes.push('App Store $what: made${attributes.keys().length > 0 ? " (" + names(attributes) + ")" : ""}');
		return c.dry ? null : Publish.json("POST", '${c.api}/v1/$type', c.token, {data: {type: type, attributes: attributes, relationships: relationships}}, 201).data;
	}

	// the build of version (build) put on the app's editable version and
	// that version sent for review: the build waited for while App Store
	// Connect processes it (minutes), an open review submission reused
	@:coroutine public static function submit(api:String, token:() -> String, app:String, versionString:String, build:String, dry:Bool) {
		if (dry) {
			Term.out(Style.status("would", Info, 'put build $versionString ($build) on version $versionString once processed, and send it for App Review'));
			return;
		}
		var editable = "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY";
		var versions:Array<Dynamic> = Publish.json("GET", '$api/v1/apps/$app/appStoreVersions?filter%5Bplatform%5D=IOS&filter%5BappStoreState%5D=$editable', token()).data ?? [];
		var version:Dynamic = Lambda.find(versions, v -> v.attributes?.versionString == versionString);
		if (version == null) throw 'App Store Connect: no editable version $versionString (helder publish --listing makes it)';
		var q = '$api/v1/builds?filter%5Bapp%5D=$app&filter%5Bversion%5D=' + StringTools.urlEncode(build) + '&filter%5BpreReleaseVersion.version%5D='
			+ StringTools.urlEncode(versionString);
		Term.spin('App Store Connect processing $versionString ($build)');
		var found:Dynamic = null, waited = 0.0, limit = Std.parseFloat(Sys.getEnv("HELDER_ASC_WAIT") ?? "") ?? 3600;
		if (Math.isNaN(limit)) limit = 3600;
		while (true) {
			var b:Array<Dynamic> = Publish.json("GET", q, token()).data ?? [];
			if (b.length > 0) {
				var s:String = b[0].attributes.processingState;
				if (s == "VALID") {
					found = b[0];
					break;
				}
				if (s == "FAILED" || s == "INVALID") {
					Term.done();
					throw 'App Store Connect: build $versionString ($build) is $s';
				}
			}
			if (waited >= limit) {
				Term.done();
				throw 'App Store Connect: build $versionString ($build) not processed after ${Std.int(limit / 60)} minutes';
			}
			helder.async.Async.delay(30);
			waited += 30;
		}
		Term.done();
		Publish.json("PATCH", '$api/v1/appStoreVersions/${version.id}/relationships/build', token(), {data: {type: "builds", id: found.id}});
		Term.out(Style.status("build", Ok, '$versionString ($build) on version $versionString'));
		var open:Array<Dynamic> = Publish.json("GET", '$api/v1/reviewSubmissions?filter%5Bapp%5D=$app&filter%5Bplatform%5D=IOS&filter%5Bstate%5D=READY_FOR_REVIEW', token()).data ?? [];
		var sub:Dynamic = open[0];
		if (sub == null)
			sub = Publish.json("POST", '$api/v1/reviewSubmissions', token(), {
				data: {type: "reviewSubmissions", attributes: {platform: "IOS"}, relationships: {app: {data: {type: "apps", id: app}}}}
			}, 201).data;
		var items:Array<Dynamic> = Publish.json("GET", '$api/v1/reviewSubmissions/${sub.id}/items', token()).data ?? [];
		if (items.length == 0)
			Publish.json("POST", '$api/v1/reviewSubmissionItems', token(), {
				data: {
					type: "reviewSubmissionItems",
					relationships: {
						reviewSubmission: {data: {type: "reviewSubmissions", id: sub.id}},
						appStoreVersion: {data: {type: "appStoreVersions", id: version.id}}
					}
				}
			}, 201);
		Publish.json("PATCH", '$api/v1/reviewSubmissions/${sub.id}', token(), {data: {type: "reviewSubmissions", id: sub.id, attributes: {submitted: true}}});
		Term.out(Style.status("submitted", Ok, 'version $versionString for App Review'));
	}

	static function only(o:Dynamic, allowed:Array<String>, at:String, file:String)
		for (k in Reflect.fields(o))
			if (!allowed.contains(k)) throw (file == "" ? "" : '$file: ') + '$at.$k: not one of ${allowed.join(", ")}';

	static function isObject(v:Dynamic):Bool
		return v != null && Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);
}

typedef Asc = {api:String, token:String, dry:Bool, changes:Array<String>};
