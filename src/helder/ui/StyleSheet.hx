package helder.ui;

// A theme: its rules (Rule) and the colours their token references name,
// light and dark (names without the dashes: "primary", "ring"). Installed
// per window (Ui.theme) or for a subtree (Node.theme, the nearest
// winning); Ui.dark picks the dark colours and makes "dark" hold. Its
// lengths are what Length.token references name ("radius"), light or dark.
// Its markers are the group and peer markers its slots carry, "group/item
// peer" ("group" unnamed), as an element's class: a rule's group: and peer:
// states find them as they find a node's group and peer attributes.
typedef StyleSheet = {
	rules:Array<Rule>,
	?light:Map<String, Color>,
	?dark:Map<String, Color>,
	?lengths:Map<String, Float>,
	?markers:Map<String, String>
}
