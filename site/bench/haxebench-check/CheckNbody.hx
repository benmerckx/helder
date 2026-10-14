// BMNBodyCode with the energies printed (@:result(-169096))
class CheckNbody {
	static function main() {
		var nbodies = new BMNBodyCode();
		Sys.println("energy before " + Math.round(nbodies.energy() * 1e9));
		for (j in 0...20)
			for (i in 0...500000)
				nbodies.advance(0.01);
		Sys.println("energy after " + Math.round(nbodies.energy() * 1e9) + ", result " + Std.int(nbodies.energy() * 1000000));
	}
}
