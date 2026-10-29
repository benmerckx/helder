// helder.web from TypeScript: TSX rendered to HTML by the static renderer
// (Static.render), a component of the program's, a list, and a WebAssembly
// island whose load is a string literal (helder.web's Load).
import { Static, Island } from "helder/web";

function Card(props: { title: string; tags: string[] }) {
	return <article class="card">
		<h2>{props.title}</h2>
		<ul>{props.tags.map(t => <li>{t}</li>)}</ul>
	</article>;
}

const w = 320;
console.log(Static.render(<main>
	<Card title="Counter" tags={["ui", "view"]} />
	<Island.Wasm src="counter.wasm" id="play" load="click" width={w} height={200} imports={["os/imports.mjs"]} assets="counter.wasm.assets.json">
		<button class="play">Play</button>
	</Island.Wasm>
</main>));
