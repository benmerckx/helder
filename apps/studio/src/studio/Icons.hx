package studio;

import helder.ui.Svg;

// The studio's own icons (16 by 16, stroked in the text's colour, 1.3 wide: the Prism sheet's)
class Icons {
	static inline var OPEN = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">';

	public static final grid = Svg.parse(OPEN
		+ '<rect x="2" y="2" width="5" height="5" rx="1.2"/><rect x="9" y="2" width="5" height="5" rx="1.2"/><rect x="2" y="9" width="5" height="5" rx="1.2"/><rect x="9" y="9" width="5" height="5" rx="1.2"/></svg>');
	public static final code = Svg.parse(OPEN + '<path d="M5.5 4 2 8l3.5 4M10.5 4 14 8l-3.5 4"/></svg>');
	public static final stories = Svg.parse(OPEN + '<path d="M3 4.5h10M3 8h7M3 11.5h5"/></svg>');
	public static final panel = Svg.parse(OPEN + '<rect x="2" y="2.5" width="12" height="11" rx="2"/><path d="M6 2.5v11"/></svg>');
	public static final back = Svg.parse(OPEN + '<path d="M10 3.5 5.5 8l4.5 4.5"/></svg>');
	public static final undo = Svg.parse(OPEN + '<path d="M5 3.5 2.5 6 5 8.5"/><path d="M2.5 6h7a3.5 3.5 0 0 1 0 7H7"/></svg>');
	public static final redo = Svg.parse(OPEN + '<path d="M11 3.5 13.5 6 11 8.5"/><path d="M13.5 6h-7a3.5 3.5 0 0 0 0 7H9"/></svg>');
	public static final send = Svg.parse(OPEN + '<path d="M8 13V3.5M4 7.5 8 3.5l4 4"/></svg>');
}
