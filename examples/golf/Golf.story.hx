import helder.story.Story;
import helder.ui.Clock;
import helder.view.View;

// Floating Greens' screenshots, for the stores and helder.run alike
// (store: true: helder publish --screenshots at the stores' sizes with
// their captions, helder publish --run at a window's without): each the
// game's own screen (Golf.view) on a hole, its recorded round played
// (GolfReplay) or an aim held, the game stepped on the story's clock frame
// by frame (Controls.play) to its moment, then settled. In this order on
// helder.run's page. In the studio each runs live.
final turnstile = story({name: "Holes/Turnstile", store: true, caption: "Three islands in the sky", render: c -> round(c, 8)});

final roundabout = story({
	name: "Holes/Roundabout",
	store: true,
	caption: "See each shot's path",
	render: c -> aim(c, 12, 0.18, -1, 0.8)
});

final brittle = story({name: "Holes/Brittle Bridge", store: true, caption: "Bridges that crumble", render: c -> round(c, 16)});

final booster = story({name: "Holes/Booster Run", store: true, caption: "Boosters up the slopes", render: c -> round(c, 10)});

final moonrise = story({name: "Holes/Moonrise", store: true, caption: "Portals and switches", render: c -> round(c, 18)});

final pinball = story({name: "Holes/Pinball", store: true, caption: "Bumpers that kick back", render: c -> round(c, 4)});

final skipping = story({name: "Holes/Skipping Stone", store: true, caption: "Sink it in one", render: c -> round(c, 13)});

// (the moment: seconds into the hole)
private final MOMENT = 4.0;

// hole (1 to 18) with its recorded round playing
private function round(c:Controls, hole:Int):View {
	var g = game(c);
	for (r in GolfReplay.rounds)
		if (r.hole == hole - 1) g.demo(r.hole, r.shots);
	return Golf.view(g);
}

// hole with an aim held: its direction (dx, dz) and power (0 to 1), the path shown
private function aim(c:Controls, hole:Int, dx:Float, dz:Float, power:Float):View {
	var g = game(c);
	g.holdAim(hole - 1, dx, dz, power);
	return Golf.view(g);
}

// a game of the story's own on its clock, silent, played to the moment (let go with the story)
private function game(c:Controls):Game {
	Golf.fonts();
	Sounds.silent = true;
	var g = new Game();
	c.onDispose(g.dispose);
	Clock.add(t -> {
		g.frame(t);
		true;
	});
	c.play(MOMENT);
	return g;
}
