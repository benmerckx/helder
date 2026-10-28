import helder.jobs.Channel;

// a Channel of functions is rejected at compile time (the jobs lane expects
// "helder.jobs: a Channel's value cannot be sent: Int -> Void is a function")
class NotSendableChannel {
	static function main() {
		var ch = new Channel<Int->Void>();
	}
}
