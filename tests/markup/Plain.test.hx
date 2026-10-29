package markup;

import helder.test.Test;
import helder.web.Static;
import markup.Widgets;

function Badge():helder.view.View
	return <b>new</b>;

function tests() {
	test("markup in module-level functions, without implements Markup", () -> {
		equals(Static.render(Widgets.Panel({title: "hello"})), '<div class="panel"><span class="label">hello</span><span>plain</span></div>');
		equals(Static.render(Badge()), "<b>new</b>");
	});
}
