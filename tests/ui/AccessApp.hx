import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.graph.Graph.*;

// A window whose accessibility tree another process reads through the
// platform's API (AtspiProbe on Linux, WinAccessProbe on Windows): the
// screen named by its argument, in a window of that title:
//   fixture   AccessFixture's controls (closed once its Save is pressed)
//   todo      the todo example (examples/todo) with two items
//   mail      the mail example (examples/mail)
//   guide     the guide's widgets (GuideTest's: a card of steppers, a
//             button opening a dialog, rich text, an editor, a form)
// It runs until it is closed or 60 seconds pass; the window's tree is the
// platform's from the first frame (the adapters wait for a client).
//   AccessApp <screen>
class AccessApp implements Markup {
	static function main() {
		var which = Sys.args()[0] ?? "fixture";
		var size = switch which {
			case "mail": [860, 560];
			case "todo": [480, 560];
			case "guide": [480, 640];
			case _: [400, 640];
		}
		var w = new UiWindow(which, size[0], size[1]);
		var start = haxe.Timer.stamp();
		switch which {
			case "fixture":
				var f = new AccessFixture();
				Render.render(f.view(), w.root);
				var saved = 0;
				w.onFrame = () -> if (f.saved != saved) w.close();
			case "todo":
				var t = new Todo();
				w.ui.theme = Todo.sheet;
				Render.render(t.view(), w.root);
				// (two items typed in, as its user does)
				var typed = false;
				w.onFrame = () -> if (!typed) {
					typed = true;
					for (s in ["Write the docs", "Ship it"]) {
						w.ui.setFocus(w.root.find("draft"));
						w.ui.textInput(s);
						w.ui.keyDown(Key.ENTER, 0);
					}
					w.ui.requestFrame();
				};
			case "mail":
				helder.ui.actions.Actions.declare("mail", Mail.MailAction);
				var m = new Mail();
				w.ui.theme = Mail.sheet;
				Render.render(m.view(), w.root);
			case "guide":
				var text = signal("A draft"), subject = signal("Hi"), body = signal(""), name = signal("Ann");
				var v:View = @:privateAccess <view padding={12} row-gap={12}>
					{GuideTest.Order({})}
					{GuideTest.Confirm({onYes: () -> {}})}
					{GuideTest.Greeting({name: name, onLink: () -> {}})}
					{GuideTest.SearchButton({onClick: () -> {}})}
					{GuideTest.Editor({text: text, onSave: () -> {}})}
					{GuideTest.Compose({subject: subject, body: body})}
				</view>;
				Render.render(v, w.root);
			case _:
				Sys.println('AccessApp: no screen $which');
				Sys.exit(2);
		}
		var frame = w.onFrame;
		w.onFrame = () -> {
			if (frame != null) frame();
			if (haxe.Timer.stamp() - start > 60) w.close();
		};
		UiWindow.idleWait = 0.02;
		Clock.add(_ -> haxe.Timer.stamp() - start <= 60);
		UiWindow.run();
	}
}
