package refresh;

enum Action {
	Build;
}

enum Message {
	Locked;
}

class Game {
	public final actions:Handler<Action, Message>;

	public function new()
		actions = new Handler(new Handler.Model());
}
