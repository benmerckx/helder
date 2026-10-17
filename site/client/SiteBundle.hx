import hxmc.web.Islands;

// site.js, every page's islands (site/islands/SiteIslands.hx): the menu, the
// theme switch, an example's source tabs; compiled to JavaScript by the port
// with @hxmc/web's DOM renderer (`make site`)
class SiteBundle {
	static function main()
		Islands.start([SiteIslands.Menu, SiteIslands.Theme, SiteIslands.Tabs]);
}
