package helder.cli;

import helder.cli.ExitPolicy;
import helder.test.Test;

// what helder dev does when its program ends (ExitPolicy): closed ends the
// session, a crash waits for a change, a reload or ctrl-c decides nothing
function tests() {
	test("this machine: exit code 0 is closed, the session ends", () -> {
		equals(ExitPolicy.decide(Desktop, 0, false, false), EndSession);
	});
	test("this machine: another exit code, or a signal's, is a crash", () -> {
		equals(ExitPolicy.decide(Desktop, 1, false, false), WaitForChange);
		equals(ExitPolicy.decide(Desktop, 3, false, false), WaitForChange);
		equals(ExitPolicy.decide(Desktop, 128 + 11, false, false), WaitForChange);
		equals(ExitPolicy.decide(Desktop, -1, false, false), WaitForChange);
	});
	test("a reload's exit (helder dev replaced it) is not a close", () -> {
		equals(ExitPolicy.decide(Desktop, 0, true, false), Ignore);
		equals(ExitPolicy.decide(Desktop, 1, true, false), Ignore);
	});
	test("ctrl-c: helder dev is ending already", () -> {
		equals(ExitPolicy.decide(Desktop, 0, false, true), Ignore);
		equals(ExitPolicy.decide(Desktop, 130, false, true), Ignore);
	});
	test("web: a page closed ends nothing", () -> {
		equals(ExitPolicy.decide(Web, 0, false, false), Ignore);
	});
	test("a phone (not wired yet): the app closed there does not end the session", () -> {
		equals(ExitPolicy.decide(Mobile, 0, false, false), WaitForChange);
		equals(ExitPolicy.decide(Mobile, 1, false, false), WaitForChange);
		equals(ExitPolicy.decide(Mobile, 0, true, false), Ignore);
	});
}
