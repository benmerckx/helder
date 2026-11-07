import helder.story.Story;
import helder.view.*;

// The story-shared lane's preview host (SmokeStudio starts it): one story,
// 120x80 points, blue with a red square of 40 points at its top left; a
// dev build, so helder.story.Screens runs it as the studio's host
// (helder.story.NativeHost) natively.
final square = story({name: "Smoke/Square", width: 120, height: 80, render: () -> SmokeHost.view()});

class SmokeHost implements Markup {
	public static function view():View
		return <view width={120} height={80} background="#0000ff"><view width={40} height={40} background="#ff0000"/></view>;

	static function main()
		helder.story.Screens.run(helder.story.Stories.of("SmokeHost"));
}
