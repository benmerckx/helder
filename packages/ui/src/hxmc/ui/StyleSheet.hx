package hxmc.ui;

// A theme: its rules (Rule) and the colours their token references name,
// light and dark (names without the dashes: "primary", "ring"). Installed
// per window (Ui.theme) or for a subtree (Node.theme, the nearest
// winning); Ui.dark picks the dark colours and makes "dark" hold. Its
// lengths are what Length.token references name ("radius"), light or dark.
typedef StyleSheet = {
	rules:Array<Rule>,
	?light:Map<String, Color>,
	?dark:Map<String, Color>,
	?lengths:Map<String, Float>
}
