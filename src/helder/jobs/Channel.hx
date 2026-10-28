package helder.jobs;

// Values between threads, in order (Go's channels, one way): sent from
// any thread or job, received by a coroutine on the loop of the thread that
// made it; T sendable (Sendable: checked here, its codec made for each T).
// A GC job that is given one sends its progress, or a stream of results.
//
//   var ch = new Channel<Int>();
//   task.async(_ -> Jobs.run(Primes.below, {limit: 100000, out: ch}));
//   var p; while ((p = ch.receive()) != null) trace(p);   // until the job's ch.close()
//
// send(v) copies v (a JobError once closed), receive() is the next value
// or null once closed and drained, close() from either side. Natively a
// queue under a lock; from a browser's worker the page delivers them.
@:genericBuild(helder.jobs.Sendable.channel())
class Channel<T> {}
