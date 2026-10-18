// title: Sidebar
// summary: A sidebar of grouped menu buttons beside the page, its trigger (or Mod+B) collapsing it to its icons
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class SidebarProviderExample implements Markup {
	public static function view():View {
		var page = signal("Inbox"), open = signal(true);
		var pages = ["Inbox", "Drafts", "Sent"], icons = ["✉", "✎", "➤"];
		return <view width={460} height={220}><SidebarProvider tag="layout" open={open}>
			<Sidebar tag="sidebar" collapsible="icon">
				<SidebarHeader><text font-weight={600}>Mail</text></SidebarHeader>
				<SidebarContent>
					<SidebarGroup>
						<SidebarGroupLabel text="Folders"/>
						<SidebarGroupContent><SidebarMenu>{[
							for (i in 0...pages.length)
								<SidebarMenuItem><SidebarMenuButton tag={"page-" + i} label={pages[i]} active={() -> page.value == pages[i]}
									onClick={() -> page.value = pages[i]}><text>{icons[i]}</text></SidebarMenuButton></SidebarMenuItem>
						]}</SidebarMenu></SidebarGroupContent>
					</SidebarGroup>
				</SidebarContent>
				<SidebarFooter><text>Signed in</text></SidebarFooter>
			</Sidebar>
			<SidebarInset>
				<view direction="row" align-items="center" column-gap={8}><SidebarTrigger tag="trigger"/><text>{() -> page.value}</text></view>
			</SidebarInset>
		</SidebarProvider></view>;
	}
}
