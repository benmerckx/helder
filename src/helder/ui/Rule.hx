package helder.ui;

// A theme's rule (StyleSheet): the style a node with this slot (Node.slot,
// shadcn's data-slot names: "button", "switch-thumb"), variant and size
// (when given) takes while every state in when holds ("hover", "active",
// "focus", "focus-visible", "disabled", "placeholder", "dark", an
// attribute "data-state=checked" or a bare "data-disabled", another node's:
// "group:hover", "peer:checked", "has:data-state=open", "first", "last",
// "not:x", as Rules reads them). Later rules
// win, property by property, as CSS's source order; the node's own style
// wins over all of them. Colours may be token references (Color.token,
// "var(--primary)", "var(--ring)/50"), resolved with the sheet's colours.
typedef Rule = {
	slot:String,
	?variant:String,
	?size:String,
	?when:Array<String>,
	style:StyleProps
}
