package hxmc.ui;

// where pages (or columns) may break around or inside a node (CSS's
// break-before, break-after and break-inside: Style.breakBefore...): a
// document host's paged layout reads them; a window has no pages
enum abstract PageBreak(Int) {
	var Auto;
	var Avoid;
	var AvoidPage;
	var Page;
	var Left;
	var Right;
	var AvoidColumn;
	var Column;
}
