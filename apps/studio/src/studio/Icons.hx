package studio;

import helder.ui.Svg;

// The studio's own icons, only where a word would not do (16 by 16, stroked in the text's colour, 1.3 wide)
class Icons {
	static inline var OPEN = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">';

	public static final undo = Svg.parse(OPEN + '<path d="M5 3.5 2.5 6 5 8.5"/><path d="M2.5 6h7a3.5 3.5 0 0 1 0 7H7"/></svg>');
	public static final redo = Svg.parse(OPEN + '<path d="M11 3.5 13.5 6 11 8.5"/><path d="M13.5 6h-7a3.5 3.5 0 0 0 0 7H9"/></svg>');
}
