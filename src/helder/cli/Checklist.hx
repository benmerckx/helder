package helder.cli;

import haxe.io.Bytes;

using StringTools;

// What the stores need done by hand, before and beside helder publish: the
// steps they have no API for, each checked through their APIs where they
// can be read (done, missing, or unknown: no API reads it), with the page
// to do it on and what to answer there, from helder.json (its name, ids,
// listing: collects and ads, its age rating, category, privacy URL).
// `helder setup` prints both stores', `helder setup ios|android` its own
// after its keys.
//
//   App Store Connect: the app's record (New App), App Privacy
//   Google Play: the app (Create app), the service account's invitation,
//     App content (privacy policy, app access, ads, content rating, target
//     audience, data safety, the other declarations), Store settings (the
//     category), the first release sent for review (Play takes drafts
//     alone until an app is published)
class Checklist {
	@:coroutine public static function run(e:Entry, stores:Array<String>):Int {
		var items:Array<Item> = [];
		if (stores.contains("ios")) items = items.concat(apple(e));
		if (stores.contains("android")) items = items.concat(google(e));
		print(items);
		return Lambda.exists(items, i -> i.done == false) ? 1 : 0;
	}

	public static function print(items:Array<Item>) {
		var store = "";
		for (i in items) {
			if (i.store != store) {
				store = i.store;
				Term.out("");
				Term.out(Style.bold(store));
			}
			var tone:Style.Tone = i.done == true ? Ok : i.done == false ? Warn : Info;
			Term.out(Style.status(i.done == true ? "done" : i.done == false ? "to do" : "check", tone, i.what + (i.done == true || i.where == null ? "" : "  " + Style.path(i.where))));
			if (i.done != true) for (a in i.answers) Term.out('      $a');
		}
	}

	// ---- App Store Connect

	@:coroutine static function apple(e:Entry):Array<Item> {
		var cfg:Manifest.AppConfig = e.config, l:Dynamic = cfg?.listing ?? {};
		var i = App.ios(e.name, e.config);
		var name:String = l.title ?? cfg?.name ?? e.name;
		var k = try Publish.ascKey() catch (_:Dynamic) null;
		var app:Dynamic = null, known = false;
		if (k != null) {
			var apps:Array<Dynamic> = try Publish.json("GET", '${Publish.ascApi()}/v1/apps?filter%5BbundleId%5D=' + StringTools.urlEncode(i.id), Publish.ascToken(k)).data catch (_:Dynamic) null;
			if (apps != null) {
				known = true;
				app = apps[0];
			}
		}
		var S = "App Store Connect";
		var items:Array<Item> = [{
			store: S,
			what: "the app's record" + (k == null ? " (no API key: not checked)" : ""),
			done: known ? app != null : null,
			where: "https://appstoreconnect.apple.com/apps",
			answers: ["Apps, +, New App: iOS", 'Name: $name', 'Primary language: English (U.S.)', 'Bundle ID: ${i.id}', 'SKU: ${cfg?.run?.name ?? HelderJson.slug(name)}',
				"User access: Full access"]
		}];
		items.push({
			store: S,
			what: "App Privacy (no API reads it)",
			done: null,
			where: app == null ? "https://appstoreconnect.apple.com/apps" : 'https://appstoreconnect.apple.com/apps/${app.id}/distribution/privacy',
			answers: l.collects == false ? ["Data Types, Get Started: No, we do not collect data from this app", "Save, then Publish (top right)"] : [
				"each type of data the app collects, its use and whether it is linked to the user (helder.json listing.collects: false when none)",
				"then Publish (top right)"
			]
		});
		return items;
	}

	// ---- Google Play

	@:coroutine static function google(e:Entry):Array<Item> {
		var cfg:Manifest.AppConfig = e.config, l:Dynamic = cfg?.listing ?? {};
		var a = App.android(e.name, e.config);
		var name:String = l.title ?? cfg?.name ?? e.name, pkg = a.id;
		var game = cfg?.run?.kind == "game" || Std.string(l.category ?? "").startsWith("GAMES");
		var sa:Dynamic = try Publish.serviceAccount(e) catch (_:Dynamic) null;
		var status = 0, tracks:Array<Dynamic> = null, who:String = sa?.client_email ?? "the service account";
		if (sa != null) {
			var token = try Publish.googleToken(sa) catch (_:Dynamic) null;
			if (token != null) {
				var base = '${Publish.playApi()}/androidpublisher/v3/applications/$pkg';
				var r = Publish.http("POST", '$base/edits', ["Authorization: Bearer " + token, "Content-Type: application/json"], Bytes.ofString("{}"));
				status = r.code;
				if (r.code == 200) {
					var edit:String = haxe.Json.parse(r.body).id;
					tracks = try Publish.json("GET", '$base/edits/$edit/tracks', token).tracks catch (_:Dynamic) null;
					try Publish.json("DELETE", '$base/edits/$edit', token) catch (_:Dynamic) {};
				}
			}
		}
		var G = "Google Play", console = "https://play.google.com/console";
		var exists:Null<Bool> = status == 200 ? true : status == 404 ? false : null;
		var items:Array<Item> = [{
			store: G,
			what: "the app" + (sa == null ? " (no service account: not checked)" : ""),
			done: exists,
			where: console,
			answers: ['Create app: App name: $name', 'Default language: English (United States), en-US', 'App or game: ${game ? "Game" : "App"}', "Free or paid: Free", "the declarations ticked",
				'its package is the first bundle\'s: $pkg (helder publish --play --draft)']
		}];
		items.push({
			store: G,
			what: "the service account invited",
			done: status == 200 ? true : status == 401 || status == 403 ? false : null,
			where: '$console (Users and permissions)',
			answers: ['Invite new users: $who', 'App permissions: $name: release to production and testing tracks, manage store presence', "Invite user"]
		});
		var ages:Dynamic = l.appStore?.ageRating;
		var mild = ages == null ? false : Lambda.exists(Reflect.fields(ages), f -> {
			var v:Dynamic = Reflect.field(ages, f);
			v != null && v != false && v != "NONE";
		});
		items.push({
			store: G,
			what: "App content (no API reads it)",
			done: null,
			where: '$console ($name, Policy and programs, App content)',
			answers: [
				'Privacy policy: ${l.privacy ?? "its URL (helder.json listing.privacy)"}',
				"App access: all functionality is available without special access (else the steps and an account for review)",
				'Ads: ${l.ads == false ? "No, my app does not contain ads" : l.ads == true ? "Yes" : "whether it shows ads (helder.json listing.ads)"}',
				'Content rating: questionnaire, category ${game ? "Game" : "the app\'s"}; ' + (ages == null ? "answer as listing.appStore.ageRating says" : mild ? "answer as listing.appStore.ageRating says (some not none)" : "every question: No"),
				"Target audience: 13 and over (an age under 13 brings the Families policy)",
				'Data safety: ' + (l.play?.dataSafety != null ? 'sent by helder publish --listing (${l.play.dataSafety})' : l.collects == false ? "Does your app collect or share any of the required user data types? No" : "each data type (or listing.play.dataSafety: Play Console's CSV)"),
				"Government apps, Financial features, Health, News: not one"
			]
		});
		items.push({
			store: G,
			what: "Store settings (no API reads them)",
			done: null,
			where: '$console ($name, Grow users, Store presence, Store settings)',
			answers: ['App category: ${playCategory(l.category, game)}', 'Contact email: ${l.email != null && !Std.string(l.email).startsWith("$") ? l.email : "sent by helder publish --listing (listing.email)"}']
		});
		var published = false, draft = false;
		for (t in (tracks ?? []))
			for (r in (t.releases ?? [] : Array<Dynamic>))
				if (r.status == "draft") draft = true else published = true;
		items.push({
			store: G,
			what: "the first release sent for review",
			done: tracks == null ? null : published ? true : draft ? false : null,
			where: '$console ($name, Publishing overview)',
			answers: draft ? ["Send for review (Play takes drafts alone until an app is published; after it helder publish --play releases directly)"] : [
				"helder publish --play makes it (a draft, an app never published), then Send for review"
			]
		});
		items.push({
			store: G,
			what: "a personal developer account: production after a closed test",
			done: null,
			where: null,
			answers: ["accounts made since November 2023 for a person, not an organisation: 12 testers for 14 days on a closed track first (helder publish --play --track alpha)"]
		});
		return items;
	}

	// App Store Connect's category as Play's (its name for a game's subcategory)
	public static function playCategory(c:Null<String>, game:Bool):String {
		if (c == null) return game ? "Game, the closest (helder.json listing.category)" : "the closest (helder.json listing.category)";
		var words = c.startsWith("GAMES_") ? c.substr(6) : c;
		var pretty = [for (w in words.split("_")) w.charAt(0) + w.substr(1).toLowerCase()].join(" ");
		return c.startsWith("GAMES_") ? 'Game, $pretty' : c == "GAMES" ? "Game" : 'App, $pretty (or the closest)';
	}
}

typedef Item = {
	store:String,
	what:String,
	// true done, false to do, null not known (no API reads it)
	done:Null<Bool>,
	where:Null<String>,
	answers:Array<String>
}
