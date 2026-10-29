package markup;

import helder.view.View;

// Components as module-level functions, no `implements Markup`: the CLI
// compiles markup in any function of the project (DESIGN.md 3.5).
function Label(props:{text:String}):View
	return <span class="label">{props.text}</span>;

function Panel(props:{title:String}):View
	return <div class="panel"><Label text={props.title}/><span>{"plain"}</span></div>;
