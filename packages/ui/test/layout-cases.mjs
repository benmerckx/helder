// The layout tests' cases (layout-ref.mjs draws them in Chromium; UiTest
// lays them out with hxmc.ui.Layout): a tree of styles (Style's property
// names; lengths in pixels or "<n>%"), the root sized width x height.
const box = (w, h, style = {}) => ({ style: { width: w, height: h, ...style } });
const grow = (g, style = {}) => ({ style: { grow: g, ...style } });
const h = (v) => ({ style: { height: v } });

export const cases = [
	{ name: 'column of fixed boxes', width: 200, height: 200, tree: { children: [box(50, 30), box(80, 40), box(20, 10)] } },
	{ name: 'column stretches width', width: 200, height: 200, tree: { children: [{ style: { height: 30 } }, { style: { height: 40 } }] } },
	{ name: 'row of fixed boxes', width: 200, height: 100, tree: { style: { direction: 'Row' }, children: [box(50, 30), box(80, 40)] } },
	{ name: 'row stretches height', width: 200, height: 100, tree: { style: { direction: 'Row' }, children: [{ style: { width: 30 } }, { style: { width: 40 } }] } },
	{ name: 'grow equally', width: 300, height: 50, tree: { style: { direction: 'Row' }, children: [grow(1), grow(1), grow(1)] } },
	{ name: 'grow by factors', width: 300, height: 50, tree: { style: { direction: 'Row' }, children: [grow(1), grow(2), box(60, 20)] } },
	{ name: 'grow with basis', width: 300, height: 50, tree: { style: { direction: 'Row' }, children: [grow(1, { basis: 100 }), grow(1, { basis: 50 })] } },
	{ name: 'grow capped by max', width: 300, height: 50, tree: { style: { direction: 'Row' }, children: [grow(1, { maxWidth: 50 }), grow(1)] } },
	{ name: 'shrink to fit', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [box(150, 20), box(150, 20)] } },
	{ name: 'shrink weighted by basis', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [box(200, 20), box(100, 20)] } },
	{ name: 'shrink zero overflows', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [box(150, 20, { shrink: 0 }), box(150, 20)] } },
	{ name: 'shrink with min', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [box(150, 20, { minWidth: 120 }), box(150, 20)] } },
	{ name: 'justify end', width: 200, height: 50, tree: { style: { direction: 'Row', justify: 'End' }, children: [box(40, 20), box(40, 20)] } },
	{ name: 'justify center', width: 200, height: 50, tree: { style: { direction: 'Row', justify: 'Center' }, children: [box(40, 20), box(40, 20)] } },
	{ name: 'justify space-between', width: 200, height: 50, tree: { style: { direction: 'Row', justify: 'SpaceBetween' }, children: [box(40, 20), box(40, 20), box(40, 20)] } },
	{ name: 'justify space-around', width: 200, height: 50, tree: { style: { direction: 'Row', justify: 'SpaceAround' }, children: [box(40, 20), box(40, 20)] } },
	{ name: 'justify space-evenly', width: 210, height: 50, tree: { style: { direction: 'Row', justify: 'SpaceEvenly' }, children: [box(40, 20), box(40, 20)] } },
	{ name: 'align start', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { width: 40 }, children: [box(10, 30)] }] } },
	{ name: 'align end', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'End' }, children: [box(40, 20), box(40, 30)] } },
	{ name: 'align center', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'Center' }, children: [box(40, 20), box(40, 30)] } },
	{ name: 'align self', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [box(40, 20), box(40, 20, { alignSelf: 'End' }), { style: { width: 40, alignSelf: 'Stretch' } }] } },
	{ name: 'padding and border', width: 200, height: 200, tree: { style: { padding: 10, borderWidth: 5 }, children: [{ style: { height: 30 } }, box(50, 20)] } },
	{ name: 'border sides', width: 200, height: 200, tree: { style: { padding: 5, borders: [2, 10, 6, 4] }, children: [{ style: { height: 30 } }, box(50, 20)] } },
	{ name: 'row border sides', width: 300, height: 60, tree: { style: { direction: 'Row', borders: [0, 0, 4, 0] }, children: [grow(1), grow(1, { borders: [1, 8, 1, 2] })] } },
	{ name: 'absolute in border sides', width: 200, height: 200, tree: { style: { borders: [3, 6, 9, 12] }, children: [{ style: { position: 'Absolute', left: 10, right: 20, top: 5, bottom: 15 } }, box(30, 30, { position: 'Absolute' })] } },
	{ name: 'padding sides', width: 200, height: 200, tree: { style: { padding: [5, 10, 15, 20] }, children: [{ style: { grow: 1 } }] } },
	{ name: 'margins', width: 200, height: 200, tree: { children: [{ style: { height: 30, margin: [5, 10, 15, 20] } }, box(40, 20, { margin: 8 })] } },
	{ name: 'row margins and grow', width: 300, height: 60, tree: { style: { direction: 'Row' }, children: [grow(1, { margin: [0, 10, 0, 10] }), grow(1, { margin: 5 })] } },
	{ name: 'gaps', width: 200, height: 200, tree: { style: { rowGap: 10 }, children: [box(50, 20), box(50, 20), box(50, 20)] } },
	{ name: 'row gaps and grow', width: 300, height: 50, tree: { style: { direction: 'Row', columnGap: 15 }, children: [grow(1), grow(1), grow(1)] } },
	{ name: 'wrap', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true }, children: [box(80, 30), box(80, 40), box(80, 20), box(80, 30)] } },
	{ name: 'wrap with gaps', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true, rowGap: 10, columnGap: 10 }, children: [box(60, 30), box(60, 30), box(60, 30), box(60, 30)] } },
	{ name: 'wrap align content center', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true, alignContent: 'Center' }, children: [box(120, 30), box(120, 40)] } },
	{ name: 'wrap align content stretch', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true, alignContent: 'Stretch' }, children: [{ style: { width: 120 } }, box(120, 40)] } },
	{ name: 'wrap align content space-between', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true, alignContent: 'SpaceBetween' }, children: [box(120, 30), box(120, 40), box(120, 20)] } },
	{ name: 'wrap grow per line', width: 200, height: 100, tree: { style: { direction: 'Row', wrap: true }, children: [box(80, 20, { grow: 1 }), box(80, 20, { grow: 1 }), box(80, 20, { grow: 1 })] } },
	{ name: 'column wrap', width: 200, height: 100, tree: { style: { wrap: true }, children: [box(40, 40), box(40, 40), box(40, 40)] } },
	{ name: 'percent sizes', width: 400, height: 200, tree: { style: { direction: 'Row' }, children: [box('25%', '50%'), box('50%', '100%')] } },
	{ name: 'percent padding parent', width: 400, height: 200, tree: { style: { padding: 20 }, children: [box('50%', '50%')] } },
	{ name: 'min max', width: 300, height: 300, tree: { children: [box(500, 10, { maxWidth: 100 }), box(10, 10, { minWidth: 50 }), { style: { height: 10, maxWidth: '50%' } }] } },
	{ name: 'column grow', width: 100, height: 300, tree: { children: [box(50, 50), grow(1), grow(2)] } },
	{ name: 'row reverse', width: 200, height: 50, tree: { style: { direction: 'RowReverse' }, children: [box(40, 20), box(50, 20)] } },
	{ name: 'column reverse', width: 100, height: 200, tree: { style: { direction: 'ColumnReverse' }, children: [box(40, 20), box(50, 30)] } },
	{ name: 'row reverse justify end', width: 200, height: 50, tree: { style: { direction: 'RowReverse', justify: 'End' }, children: [box(40, 20), box(50, 20)] } },
	{ name: 'absolute offsets', width: 200, height: 200, tree: { style: { padding: 10 }, children: [box(50, 50, { position: 'Absolute', left: 20, top: 30 }), box(40, 40)] } },
	{ name: 'absolute right bottom', width: 200, height: 200, tree: { children: [box(50, 30, { position: 'Absolute', right: 10, bottom: 20 })] } },
	{ name: 'absolute stretched', width: 200, height: 200, tree: { style: { borderWidth: 4 }, children: [{ style: { position: 'Absolute', left: 10, right: 20, top: 5, bottom: 15 } }] } },
	{ name: 'absolute percent', width: 200, height: 100, tree: { children: [box('50%', '50%', { position: 'Absolute', left: '25%', top: '10%' })] } },
	{ name: 'relative offsets', width: 200, height: 200, tree: { children: [box(50, 50, { left: 10, top: 5 }), box(50, 50, { right: 10, bottom: 5 })] } },
	{ name: 'display none', width: 200, height: 200, tree: { children: [box(50, 50), box(50, 50, { display: 'None' }), box(60, 20)] } },
	{ name: 'nested auto sizes', width: 300, height: 300, tree: { style: { alignItems: 'Start' }, children: [{ style: { direction: 'Row', padding: 5 }, children: [box(30, 20), box(40, 50)] }] } },
	{ name: 'nested grow', width: 300, height: 200, tree: { style: { direction: 'Row' }, children: [{ style: { grow: 1, padding: 10 }, children: [grow(1), box(20, 20)] }, { style: { width: 100 }, children: [box(30, 30)] }] } },
	{ name: 'content basis', width: 400, height: 100, tree: { style: { direction: 'Row' }, children: [{ style: { direction: 'Row' }, children: [box(50, 20), box(70, 20)] }, grow(1)] } },
	{ name: 'aspect ratio width', width: 200, height: 200, tree: { style: { alignItems: 'Start' }, children: [box(100, 'auto', { aspectRatio: 2 })] } },
	{ name: 'aspect ratio height', width: 200, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [box('auto', 40, { aspectRatio: 1.5 })] } },
	{ name: 'auto min width in a row', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [{ children: [box(150, 20)] }, { children: [box(150, 20)] }] } },
	{ name: 'auto min height in a column', width: 100, height: 100, tree: { children: [{ children: [box(50, 80)] }, { children: [box(50, 80)] }] } },
	{ name: 'overflow hidden may shrink', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [{ style: { overflow: 'Hidden' }, children: [box(150, 20)] }, { children: [box(150, 20)] }] } },
	{ name: 'width below its content', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [{ style: { width: 100 }, children: [box(150, 20)] }, box(150, 20)] } },
	{ name: 'min width 0 may shrink', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [{ style: { minWidth: 0 }, children: [box(150, 20)] }, { style: { minWidth: 0 }, children: [box(150, 20)] }] } },
	{ name: 'min content of a nested row', width: 200, height: 50, tree: { style: { direction: 'Row' }, children: [{ style: { direction: 'Row', padding: 5, columnGap: 4 }, children: [box(60, 20), box(70, 20)] }, grow(1, { basis: 300 })] } },
	{ name: 'min content of a wrapping row', width: 200, height: 100, tree: { style: { direction: 'Row' }, children: [{ style: { direction: 'Row', wrap: true }, children: [box(60, 20), box(90, 20), box(40, 20)] }, grow(1, { basis: 300 })] } },
	{ name: 'toolbar', width: 400, height: 300, tree: { children: [
		{ style: { direction: 'Row', alignItems: 'Center', padding: [4, 8], columnGap: 6, height: 40 }, children: [box(24, 24), box(80, 20), grow(1), box(60, 28)] },
		{ style: { grow: 1, direction: 'Row' }, children: [{ style: { width: 120, padding: 8, rowGap: 4 }, children: [{ style: { height: 20 } }, { style: { height: 20 } }] }, { style: { grow: 1, padding: 12 } }] },
		{ style: { height: 24 } }] } },
	// grids
	{ name: 'grid fixed columns', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '50px 100px' }, children: [h(20), h(30), h(25), h(10)] } },
	{ name: 'grid fr columns', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 2fr' }, children: [h(30), h(30), h(30)] } },
	{ name: 'grid px fr auto', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '80px 1fr auto', alignContent: 'Start' }, children: [h(20), h(20), { children: [box(40, 20)] }] } },
	{ name: 'grid gaps', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr 1fr', rowGap: 10, columnGap: 6, alignContent: 'Start' }, children: [h(20), h(20), h(20), h(20), h(20)] } },
	{ name: 'grid template rows', width: 200, height: 200, tree: { style: { display: 'Grid', gridTemplateRows: '40px 1fr 30px' }, children: [{}, {}, {}] } },
	{ name: 'grid placement', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '40px' }, children: [{ style: { gridColumn: '2 / 4' } }, { style: { gridColumn: '1', gridRow: '2' } }, {}, {}] } },
	{ name: 'grid spans', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '30px', columnGap: 4 }, children: [{ style: { gridColumn: 'span 2' } }, {}, {}, { style: { gridColumn: 'span 3' } }, { style: { gridRow: 'span 2' } }, {}] } },
	// (an item's percentages of its grid area: the calendar's days, aspect-square w-full h-full)
	{ name: 'grid percent items', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 40px)', alignContent: 'Start' }, children: [{ style: { width: '100%', height: '100%', aspectRatio: 1 } }, { style: { width: '50%' }, children: [box(10, 10)] }, h(20)] } },
	{ name: 'grid negative lines', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '50px 1fr 50px', gridAutoRows: '30px' }, children: [{ style: { gridColumn: '1 / -1' } }, { style: { gridColumn: '-2' } }] } },
	{ name: 'grid minmax', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: 'minmax(100px, 1fr) minmax(50px, 80px) 1fr' }, children: [h(20), h(20), h(20)] } },
	{ name: 'grid percent columns', width: 400, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: '25% 75%' }, children: [h(20), h(20)] } },
	{ name: 'grid content columns', width: 400, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: 'min-content max-content auto', alignContent: 'Start' },
		children: [{ style: { direction: 'Row', wrap: true }, children: [box(60, 20), box(50, 20)] }, { style: { direction: 'Row', wrap: true }, children: [box(60, 20), box(50, 20)] }, { children: [box(30, 20)] }] } },
	{ name: 'grid items aligned', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '100px 100px', justifyItems: 'Center', alignItems: 'End' },
		children: [box(40, 30), box(50, 20, { justifySelf: 'End', alignSelf: 'Start' }), box(30, 30, { justifySelf: 'Stretch', width: 'auto' }), { style: { height: 20, justifySelf: 'Start' }, children: [box(25, 10)] }] } },
	{ name: 'grid auto flow column', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateRows: '50px 50px', gridAutoFlow: 'Column', gridAutoColumns: '60px' }, children: [{}, {}, {}, {}, {}] } },
	// (dense: a wide item leaves a hole the next small ones fill; sparse, they go after it)
	{ name: 'grid sparse holes', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '30px' }, children: [{}, { style: { gridColumn: 'span 3' } }, {}, { style: { gridColumn: 'span 2' } }, {}, {}] } },
	{ name: 'grid dense', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '30px', gridAutoFlow: 'RowDense' }, children: [{}, { style: { gridColumn: 'span 3' } }, {}, { style: { gridColumn: 'span 2' } }, {}, {}] } },
	{ name: 'grid dense locked', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(4, 1fr)', gridAutoRows: '30px', gridAutoFlow: 'RowDense' }, children: [{ style: { gridColumn: '3', gridRow: '1' } }, { style: { gridRow: '1', gridColumn: 'span 2' } }, { style: { gridRow: '1' } }, { style: { gridColumn: '2' } }, {}, { style: { gridColumn: 'span 3' } }, {}] } },
	{ name: 'grid dense columns', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateRows: '40px 40px 40px', gridAutoColumns: '50px', gridAutoFlow: 'ColumnDense' }, children: [{ style: { gridRow: 'span 2' } }, { style: { gridRow: 'span 2' } }, {}, {}, { style: { gridRow: 'span 3' } }, {}] } },
	{ name: 'grid auto columns from content', width: 400, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { display: 'Grid', gridTemplateColumns: 'auto auto', columnGap: 10, padding: 5 }, children: [box(70, 20), box(40, 30), box(20, 20)] }] } },
	{ name: 'grid padding and border', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', padding: 10, borderWidth: 5, alignContent: 'Start' }, children: [h(30), h(30)] } },
	{ name: 'grid absolute child', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr', padding: 10 }, children: [h(30), box(40, 40, { position: 'Absolute', right: 5, top: 5 })] } },
	{ name: 'grid justify content center', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '60px 60px', gridTemplateRows: '40px', justify: 'Center', alignContent: 'End' }, children: [{}, {}] } },
	{ name: 'grid space between', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '60px 60px 60px', gridTemplateRows: '40px 40px', justify: 'SpaceBetween', alignContent: 'SpaceBetween' }, children: [{}, {}, {}, {}] } },
	{ name: 'grid rows from content', width: 300, height: 300, tree: { style: { display: 'Grid', gridTemplateColumns: '100px 1fr', alignContent: 'Start', columnGap: 8, rowGap: 4 }, children: [box(50, 40), { children: [h(20), h(25)] }, h(15), {}] } },
	{ name: 'grid fr at indefinite width', width: 400, height: 100, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { display: 'Grid', gridTemplateColumns: '1fr 2fr' }, children: [box(60, 20), box(40, 20)] }] } },
	{ name: 'grid item margins', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', gridAutoRows: '50px' }, children: [{ style: { margin: 5 } }, { style: { margin: [2, 4, 6, 8] } }, box(40, 20, { margin: 10, justifySelf: 'End', alignSelf: 'Center' })] } },
	{ name: 'grid spanning content', width: 400, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { display: 'Grid', gridTemplateColumns: 'auto auto' }, children: [box(200, 20, { gridColumn: 'span 2' }), box(30, 20), box(50, 20)] }] } },
	{ name: 'grid nested', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '100px 1fr', alignContent: 'Start' }, children: [h(40), { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', columnGap: 4 }, children: [h(20), h(30), h(10)] }] } },
	{ name: 'grid min content in a row', width: 300, height: 100, tree: { style: { direction: 'Row' }, children: [{ style: { display: 'Grid', gridTemplateColumns: 'auto auto', columnGap: 10 }, children: [box(80, 20), box(60, 20)] }, box(250, 20)] } },
	{ name: 'grid auto rows minmax', width: 300, height: 300, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', gridAutoRows: 'minmax(40px, auto)', alignContent: 'Start' }, children: [h(20), h(60), h(10)] } },
	{ name: 'grid wide item in fr', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr 1fr', alignContent: 'Start' }, children: [{ children: [box(200, 20)] }, h(20)] } },
	// found by random trees against Chromium: a border box no smaller than its padding and border; an absolute box's auto height is
	// its content's; the flex base size not clamped by min-height; a column's item across fit-content; a row's intrinsic width from
	// its items' max-content contributions, flex-basis left out
	{ name: 'padding and border floor a small box', width: 200, height: 100, tree: { style: { alignItems: 'Start' }, children: [box(10, 10, { padding: 4, borderWidth: 3 }), box(4, 4, { padding: [1, 2, 3, 4] })] } },
	{ name: 'absolute box by its bottom: its content height', width: 200, height: 100, tree: { children: [{ style: { height: 20 }, children: [{ style: { position: 'Absolute', bottom: 4, left: 5 }, children: [box(30, 10, { grow: 1 })] }] }] } },
	{ name: 'flex base size before min-height', width: 300, height: 150, tree: { children: [{ style: { grow: 0.5, width: 10, minHeight: 20, padding: [1, 2, 3, 4] } }] } },
	{ name: 'column item across: fit-content', width: 200, height: 100, tree: { children: [{ style: { alignItems: 'Center', width: 40, height: 40 }, children: [{ style: { direction: 'Row', margin: 3 }, children: [box(60, 10)] }] }] } },
	{ name: 'column auto height past the room', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { rowGap: 5 }, children: [box(40, 80), box(40, 80)] }] } },
	{ name: 'absolute static position: justify and align', width: 200, height: 150, tree: { style: { justify: 'SpaceEvenly', alignItems: 'Center', padding: [2, 6] }, children: [box(30, 20, { position: 'Absolute', left: 5 }), box(30, 20, { position: 'Absolute', bottom: 4 }), box(30, 20, { position: 'Absolute', alignSelf: 'End' })] } },
	{ name: 'absolute static position in a reversed row', width: 200, height: 100, tree: { style: { direction: 'RowReverse', justify: 'Center', alignItems: 'End' }, children: [box(40, 20, { position: 'Absolute' }), box(30, 30, { position: 'Absolute', margin: [0, 10] })] } },
	{ name: 'percentage basis of an indefinite column: content', width: 200, height: 150, tree: { style: { wrap: true }, children: [{ style: { padding: 4, width: 40 }, children: [box(30, 30, { basis: '30%', grow: 1, shrink: 0 }), h(10)] }] } },
	{ name: 'space-around and space-evenly overflowing: at the start', width: 200, height: 100, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { justify: 'SpaceAround', height: 30, width: 60 }, children: [box(40, 50)] }, { style: { justify: 'SpaceEvenly', height: 30, width: 60 }, children: [box(40, 30), box(40, 30)] }, { style: { wrap: true, alignContent: 'SpaceAround', width: 30, height: 40 }, children: [box(50, 20)] }] } },
	{ name: 'row intrinsic width: a basis and the factors', width: 300, height: 200, tree: { style: { alignItems: 'Start' }, children: [{ style: { direction: 'Row' }, children: [box(100, 10, { basis: 20 })] }, { style: { direction: 'Row' }, children: [{ style: { basis: 50, minWidth: 20, height: 10 } }] }, { style: { direction: 'Row' }, children: [{ style: { basis: 20, height: 10 }, children: [box(100, 10)] }] }, { style: { direction: 'Row' }, children: [{ style: { basis: 50, minWidth: 20, height: 10 } }, box(100, 10)] }, { style: { direction: 'Row' }, children: [box(100, 10, { basis: 20, grow: 0.5 })] }, { style: { direction: 'Row' }, children: [box(20, 10, { basis: 60, shrink: 0 })] }] } },
	{ name: 'wrapping at max-width, not at the room', width: 300, height: 200, tree: { style: { alignItems: 'Start' }, children: [{ style: { direction: 'Row', wrap: true, maxWidth: 80, columnGap: 10 }, children: [box(30, 10), box(60, 20)] }, { style: { wrap: true, height: 50 }, children: [box(30, 40), box(30, 40)] }] } },
	// percentages of a height that is not definite (an auto one, laid out or not) resolve as auto; a stretched item's height is definite
	{ name: 'percentages in an auto-height column', width: 300, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start', columnGap: 10 }, children: [{ children: [box(20, 40), box(20, '50%')] }, { children: [box(20, 40), { style: { width: 20, basis: '50%' } }] }, { style: { minHeight: 100 }, children: [{ style: { grow: 1 }, children: [box(20, '50%')] }] }] } },
	{ name: 'percentages in an auto-height row', width: 300, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start', columnGap: 10 }, children: [{ style: { direction: 'Row' }, children: [box(20, 40), box(20, '50%')] }, { style: { direction: 'Row' }, children: [{ style: { direction: 'Row' }, children: [box(20, 40), box(20, '50%')] }, box(5, 80)] }] } },
	{ name: 'percentages in an absolute box', width: 300, height: 200, tree: { children: [{ style: { position: 'Absolute', left: 0, top: 0 }, children: [box(20, 40), box(20, '50%')] }, { style: { position: 'Absolute', left: 50, top: 0, bottom: 100 }, children: [box(20, 40), box(20, '50%')] }, { style: { position: 'Absolute', left: 100, top: 0, maxHeight: 30 }, children: [box(20, 40), box(20, '50%')] }] } },
	{ name: 'percentages in a stretched column', width: 300, height: 200, tree: { style: { direction: 'Row', height: 100 }, children: [{ children: [box(20, 40), box(20, '50%')] }, { style: { direction: 'Row' }, children: [box(20, 40), box(20, '50%')] }] } },
	// an absolute box's auto width: shrink to fit the room its offsets leave, not below its min-content width
	{ name: 'absolute shrink-to-fit', width: 200, height: 200, tree: { style: { width: 120 }, children: [{ style: { direction: 'Row', position: 'Absolute', left: 5, top: 0 }, children: [box(60, 20), box(70, 20)] }, { style: { direction: 'Row', position: 'Absolute', left: 30, top: 40 }, children: [box(40, 20), { style: { width: 50, height: 20, minWidth: 0 } }] }, { style: { direction: 'Row', position: 'Absolute', right: 0, top: 80, columnGap: 10 }, children: [h(20), { style: { width: 30, minWidth: 0, height: 20 } }, box(40, 20, { shrink: 0 })] }] } },
	// an absolute box with both offsets and a size on an axis: placed between them by its justifySelf and alignSelf
	{ name: 'absolute self-alignment', width: 200, height: 400, tree: { children: [
		{ style: { height: 100 }, children: [{ style: { position: 'Absolute', width: 40, height: 30, top: 10, bottom: 20, left: 10, right: 20 } }, { style: { position: 'Absolute', width: 40, height: 30, top: 10, bottom: 20, left: 10, right: 20, alignSelf: 'End', justifySelf: 'Center' } }, { style: { position: 'Absolute', width: 40, height: 30, top: 10, bottom: 20, left: 10, right: 20, alignSelf: 'Center', justifySelf: 'End', margin: [5, 6, 7, 8] } }] },
		{ style: { height: 100, dir: 'Rtl' }, children: [{ style: { position: 'Absolute', width: 40, height: 30, top: 10, bottom: 20, left: 10, right: 20 } }, { style: { position: 'Absolute', width: 40, height: 30, top: 10, bottom: 20, left: 10, right: 20, justifySelf: 'End' } }] },
		{ style: { height: 100 }, children: [{ style: { position: 'Absolute', width: 40, height: 300, top: 10, bottom: 20, left: 10, alignSelf: 'End' } }] },
		{ style: { height: 100 }, children: [{ style: { position: 'Absolute', width: 40, height: 95, top: 10, bottom: 20, left: 10 } }, { style: { position: 'Absolute', width: 40, height: 95, top: 10, bottom: 20, left: 60, alignSelf: 'Start' } }] }] } },
	// a width under the padding: its border box no smaller than the padding, in the min-content width too
	{ name: 'width under its padding, min-content', width: 200, height: 150, tree: { style: { wrap: true, padding: [2, 6] }, children: [{ style: { direction: 'RowReverse', shrink: 0, maxHeight: 80 }, children: [{ style: { direction: 'Row', margin: [0, 5], position: 'Absolute', top: 7, bottom: 4 },
		children: [{ style: { basis: 50, width: 60, height: 30 } }, { style: { wrap: true, grow: 2, shrink: 0, width: 10, padding: [2, 6] } }, box(10, 30, { grow: 0.5, margin: 3 })] }] }] } },
	// space-around and space-evenly overflowing: at the writing mode's start (a reversed direction's far end); space-between at the flex start
	{ name: 'reversed overflow fallback', width: 300, height: 300, tree: { style: { alignItems: 'Start', rowGap: 4 }, children: [
		{ style: { direction: 'RowReverse', justify: 'SpaceAround', width: 60, height: 10 }, children: [box(40, 10, { shrink: 0 }), box(40, 10, { shrink: 0 })] },
		{ style: { direction: 'RowReverse', justify: 'SpaceEvenly', width: 60, height: 10, dir: 'Rtl' }, children: [box(40, 10, { shrink: 0 }), box(40, 10, { shrink: 0 })] },
		{ style: { direction: 'RowReverse', justify: 'SpaceBetween', width: 60, height: 10 }, children: [box(40, 10, { shrink: 0 }), box(40, 10, { shrink: 0 })] },
		{ style: { direction: 'Row', alignItems: 'Start', columnGap: 4 }, children: [{ style: { direction: 'ColumnReverse', justify: 'SpaceAround', width: 10, height: 60 }, children: [box(10, 40, { shrink: 0 }), box(10, 40, { shrink: 0 })] }] }] } },
	// a stretched item's content measured at its own max-width: its wrapping row's lines as wide
	{ name: 'stretched item measured within its max-width', width: 200, height: 150, tree: { style: { justify: 'End' }, children: [{ style: { maxWidth: 40 }, children: [{ style: { direction: 'Row', wrap: true }, children: [box(30, 60), box(20, 40)] }, { style: { basis: 50, height: 60 } }] }] } },
	// auto margins: the free space along shared among them (justify-content left out), across the line's room left (not stretched)
	{ name: 'auto margins in a row', width: 300, height: 200, tree: { style: { rowGap: 4 }, children: [
		{ style: { direction: 'Row', height: 30, justify: 'Center' }, children: [box(40, 20), box(40, 20, { margin: [0, 0, 0, 'auto'] }), box(40, 20)] },
		{ style: { direction: 'Row', height: 30, columnGap: 10 }, children: [box(40, 20, { margin: [0, 'auto'] }), box(40, 20, { margin: ['auto', 0, 0, 'auto'] }), { style: { width: 40, margin: ['auto', 5, 'auto', 5] } }] },
		{ style: { direction: 'Row', height: 30 }, children: [box(200, 20, { margin: [0, 'auto'], shrink: 0 }), box(150, 20, { margin: ['auto', 0, 'auto', 0], height: 50 })] },
		{ style: { direction: 'RowReverse', height: 30, dir: 'Rtl' }, children: [box(40, 20, { margin: [0, 'auto', 0, 0] }), box(40, 20)] }] } },
	{ name: 'auto margins in a column and a grid', width: 300, height: 300, tree: { style: { direction: 'Row', columnGap: 10, alignItems: 'Start' }, children: [
		{ style: { height: 200, width: 80 }, children: [box(40, 20, { margin: ['auto', 'auto', 0, 'auto'] }), box(40, 20), box(40, 20, { margin: [0, 0, 'auto', 'auto'] }), h(20)] },
		{ style: { display: 'Grid', gridTemplateColumns: '80px 80px', gridAutoRows: '60px', width: 160 }, children: [box(30, 20, { margin: 'auto' }), box(30, 20, { margin: [0, 0, 'auto', 'auto'] }), { style: { height: 20, margin: [0, 'auto'] } }, { style: { margin: ['auto', 0] } }] }] } },
	{ name: 'auto margins overflowing, justify-content kept', width: 300, height: 100, tree: { style: { justify: 'Center' }, children: [{ style: { height: 80, shrink: 0 } }, box(40, 60, { margin: ['auto', 0, 0, 'auto'], shrink: 0 })] } },
	// an absolute box with both offsets and an auto size: stretched only when its self-alignment is auto or stretch, else fit-content
	{ name: 'absolute self-aligned fit-content', width: 300, height: 200, tree: { style: { height: 200 }, children: [
		{ style: { position: 'Absolute', left: 10, right: 10, top: 10, bottom: 10, alignSelf: 'End', justifySelf: 'Center' }, children: [box(40, 20)] },
		{ style: { position: 'Absolute', left: 10, top: 0, bottom: 0, alignSelf: 'Baseline', margin: ['auto', 0, 0, 0] }, children: [box(30, 10)] }] } },
	{ name: 'auto margins on absolute boxes', width: 300, height: 200, tree: { style: { height: 200 }, children: [
		{ style: { position: 'Absolute', left: 10, right: 10, top: 10, bottom: 10, width: 100, height: 50, margin: 'auto' } },
		{ style: { position: 'Absolute', left: 10, right: 10, top: 0, width: 100, height: 20, margin: [0, 0, 0, 'auto'] } },
		{ style: { position: 'Absolute', left: 10, right: 10, top: 30, bottom: 0, width: 400, height: 20, margin: ['auto', 'auto', 0, 'auto'] } },
		{ style: { position: 'Absolute', left: 0, right: 0, top: 60, margin: [0, 'auto'], height: 10 } }] } },
	// baselines: a box without text has its bottom edge's, a container its first item's (a row's: its items aligned on theirs)
	{ name: 'baseline alignment', width: 300, height: 300, tree: { style: { rowGap: 6 }, children: [
		{ style: { direction: 'Row', alignItems: 'Baseline', columnGap: 4 }, children: [box(30, 20), box(30, 40, { margin: [5, 0, 3, 0] }), { style: { padding: [4, 0, 0, 0] }, children: [box(20, 10), box(20, 30)] },
			{ style: { direction: 'Row', alignItems: 'Baseline' }, children: [box(20, 15), box(20, 25, { margin: [0, 0, 6, 0] })] }, box(30, 10, { alignSelf: 'Center' })] },
		{ style: { direction: 'Row', alignItems: 'Baseline', height: 80, borderWidth: 2 }, children: [box(30, 20), box(30, 40)] },
		{ style: { direction: 'Row', alignItems: 'Baseline' }, children: [{ style: { width: 30, height: 30 }, children: [box(20, 50, { shrink: 0 })] }, box(30, 20)] },
		{ style: { direction: 'Row', wrap: true, alignItems: 'Baseline', width: 100, columnGap: 4, rowGap: 4 }, children: [box(40, 20), box(40, 30), box(40, 10), box(40, 25)] },
		{ style: { alignItems: 'Baseline', width: 100 }, children: [box(40, 20), box(60, 20, { margin: [0, 0, 0, 8] }), box(30, 10, { alignSelf: 'Start' })] }] } },
	// the shorthands: gap (both gaps), inset (the four offsets), flex: n (n 1 0%)
	{ name: 'gap, inset and flex shorthands', width: 300, height: 200, tree: { style: { gap: 6 }, children: [
		{ style: { direction: 'Row', gap: 10, height: 20 }, children: [{ style: { flex: 1 } }, { style: { flex: 2 } }, box(30, 20)] },
		{ style: { direction: 'Row', alignItems: 'Start' }, children: [{ children: [{ style: { flex: 1 }, children: [box(20, 30)] }, box(20, 10)] }] },
		{ style: { height: 60 }, children: [{ style: { position: 'Absolute', inset: 10 } }] }] } },
	// intrinsic widths: min-content (its widest item), max-content (all on one line), fit-content (the latter within the room)
	{ name: 'intrinsic widths', width: 300, height: 300, tree: { style: { width: 120, alignItems: 'Start', rowGap: 4 }, children: [
		{ style: { direction: 'Row', wrap: true, width: 'min-content' }, children: [box(40, 10), box(50, 10), box(30, 10)] },
		{ style: { direction: 'Row', wrap: true, width: 'max-content' }, children: [box(60, 10), box(50, 10), box(30, 10)] },
		{ style: { direction: 'Row', wrap: true, width: 'fit-content' }, children: [box(40, 10), box(50, 10), box(30, 10)] },
		{ style: { direction: 'Row', wrap: true, width: 'fit-content' }, children: [box(40, 10), box(30, 10)] },
		{ style: { direction: 'Row', wrap: true, width: 20, minWidth: 'min-content' }, children: [box(40, 10), box(50, 10)] },
		{ style: { direction: 'Row', wrap: true, maxWidth: 'min-content' }, children: [box(40, 10), box(50, 10)] },
		{ style: { direction: 'Row', alignSelf: 'Stretch' }, children: [{ style: { width: 'max-content', direction: 'Row' }, children: [box(30, 10), box(30, 10)] }, { style: { width: 'min-content', direction: 'Row', wrap: true }, children: [box(20, 10), box(25, 10)] }] },
		{ style: { position: 'Absolute', left: 0, top: 200, width: 'max-content', direction: 'Row' }, children: [box(100, 10), box(100, 10)] }] } },
	// shrinking weighs each item's base size inside its padding and border
	{ name: 'shrink by the content-box base size', width: 200, height: 60, tree: { style: { direction: 'Row' }, children: [box(100, 20, { padding: [0, 20] }), box(100, 20, { borderWidth: 10 }), box(100, 20)] } },
	{ name: 'row intrinsic width without flex-basis', width: 300, height: 100, tree: { style: { alignItems: 'Start' }, children: [{ style: { direction: 'Row', columnGap: 4 }, children: [box(100, 30), { style: { basis: 50, minWidth: 20, margin: 3 } }] }] } },
	// a scroll container's automatic minimum is 0 (its padding and border): a wide one does not widen its fr or auto track
	{ name: 'grid clipped wide item in fr', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: '50px 1fr 40px', alignContent: 'Start' }, children: [h(20), { style: { overflow: 'Hidden', padding: [0, 6] }, children: [box(400, 20)] }, h(20)] } },
	{ name: 'grid clipped item in an auto track', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: 'auto 1fr', alignContent: 'Start' }, children: [{ style: { overflow: 'Hidden' }, children: [box(400, 20)] }, h(20)] } },
	{ name: 'grid clipped tall item in fr rows', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: '1fr', gridTemplateRows: '1fr 30px' }, children: [{ style: { overflow: 'Hidden' }, children: [box(40, 200)] }, {}] } },
	{ name: 'grid clipped item with a min width', width: 300, height: 100, tree: { style: { display: 'Grid', gridTemplateColumns: '50px 1fr 40px', alignContent: 'Start' }, children: [h(20), { style: { overflow: 'Hidden', minWidth: 250 }, children: [box(400, 20)] }, h(20)] } },
	{ name: 'grid template areas', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '80px 1fr', gridTemplateRows: '40px 1fr 30px', gridTemplateAreas: "'head head' 'side main' 'foot foot'" },
		children: [{ style: { gridArea: 'main' } }, { style: { gridArea: 'foot' } }, { style: { gridArea: 'head' } }, { style: { gridArea: 'side' } }] } },
	{ name: 'grid areas beyond the templates', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: '60px', gridAutoColumns: '50px', gridAutoRows: '30px', alignContent: 'Start', gridTemplateAreas: "'a b c' 'a . c'" },
		children: [{ style: { gridArea: 'c' } }, {}, { style: { gridArea: 'a' } }, {}, {}] } },
	{ name: 'grid area lines by name', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '40px', gridTemplateAreas: "'x x y' 'z . y'" },
		children: [{ style: { gridColumn: 'x-start / y-end', gridRow: '2' } }, { style: { gridColumn: 'y', gridRow: 'x' } }, { style: { gridColumn: 'z / 3' } }, { style: { gridColumn: 'nowhere' } }, { style: { gridArea: '1 / 2 / 3' } }] } },
	// reversed directions with margins on one side; right to left (dir: CSS's direction)
	{ name: 'row reverse, one-sided margins', width: 300, height: 60, tree: { style: { direction: 'RowReverse' }, children: [box(40, 20, { margin: [0, 0, 0, 10] }), box(50, 20, { margin: [0, 20, 0, 0] })] } },
	{ name: 'column reverse, one-sided margins', width: 100, height: 200, tree: { style: { direction: 'ColumnReverse' }, children: [box(40, 20, { margin: [5, 0, 0, 0] }), box(50, 20, { margin: [0, 0, 15, 0] })] } },
	{ name: 'rtl row', width: 300, height: 60, tree: { style: { direction: 'Row', dir: 'Rtl', padding: [0, 12, 0, 4], columnGap: 6 }, children: [box(40, 20, { margin: [0, 0, 0, 10] }), box(50, 20, { margin: [0, 8, 0, 0] }), grow(1, { height: 10, maxWidth: 30 })] } },
	{ name: 'rtl row justified', width: 300, height: 60, tree: { style: { direction: 'Row', dir: 'Rtl', justify: 'SpaceBetween' }, children: [box(40, 20), box(50, 20), box(30, 20)] } },
	{ name: 'rtl row reverse', width: 300, height: 60, tree: { style: { direction: 'RowReverse', dir: 'Rtl' }, children: [box(40, 20, { margin: [0, 0, 0, 10] }), box(50, 20)] } },
	{ name: 'rtl column', width: 200, height: 200, tree: { style: { dir: 'Rtl', alignItems: 'Start', padding: [4, 20, 4, 6] }, children: [box(40, 20, { margin: [0, 0, 0, 10] }), box(60, 20, { margin: [0, 5, 0, 0] }), box(30, 20, { alignSelf: 'Center' }), box(30, 20, { alignSelf: 'End' }), h(20)] } },
	{ name: 'rtl wrap', width: 200, height: 200, tree: { style: { direction: 'Row', wrap: true, dir: 'Rtl', rowGap: 4, columnGap: 4 }, children: [box(80, 20), box(80, 30), box(80, 20), box(30, 20)] } },
	{ name: 'rtl inherited', width: 300, height: 100, tree: { style: { dir: 'Rtl' }, children: [{ style: { direction: 'Row', height: 40 }, children: [box(40, 20), box(50, 20)] }, { style: { direction: 'Row', dir: 'Ltr', height: 40 }, children: [box(40, 20), box(50, 20)] }] } },
	{ name: 'rtl grid', width: 300, height: 200, tree: { style: { display: 'Grid', dir: 'Rtl', gridTemplateColumns: '60px 1fr 80px', gridAutoRows: '40px', columnGap: 5, padding: [0, 10, 0, 0] },
		children: [{}, { style: { gridColumn: '2 / 4' } }, box(30, 20, { justifySelf: 'Start' }), box(30, 20, { justifySelf: 'End', margin: [0, 0, 0, 6] })] } },
	// order (CSS's): items laid out by it, ties in the tree's order
	{ name: 'order in a row', width: 300, height: 60, tree: { style: { direction: 'Row', columnGap: 5 }, children: [box(40, 20, { order: 2 }), box(50, 20), box(30, 20, { order: -1 }), box(20, 20, { order: 2 })] } },
	{ name: 'order in a wrapping column', width: 200, height: 100, tree: { style: { wrap: true, columnGap: 4 }, children: [box(40, 40, { order: 1 }), box(50, 40), box(30, 40, { order: 1 }), box(20, 30)] } },
	{ name: 'order in a grid', width: 300, height: 200, tree: { style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)', gridAutoRows: '30px' }, children: [{ style: { order: 3 } }, {}, { style: { order: 1, gridColumn: 'span 2' } }, {}] } },
	{ name: 'rtl absolute static position', width: 300, height: 200, tree: { style: { dir: 'Rtl', padding: [10, 15, 10, 5], borderWidth: 2 }, children: [h(30), box(40, 40, { position: 'Absolute', margin: [0, 6, 0, 0] }), box(40, 40, { position: 'Absolute', left: 10, top: 50 })] } },
	// (found by random trees against Chromium) a basis under the padding: the padding and border; a wrapping column of unknown width as wide
	// as on one line unless its height is its own; its automatic minimum its lines broken at its own height
	{ name: 'basis floored at padding', width: 300, height: 200, tree: { children: [grow(2), grow(1, { basis: 8, padding: 10 })] } },
	{ name: 'flexed wrapping column, one line wide', width: 300, height: 200, tree: { style: { direction: 'Row', alignItems: 'Start' }, children: [{ style: { height: 30 }, children: [{ style: { wrap: true, grow: 1, basis: 85, minHeight: 0 }, children: [box(12, 20), box(106, 15)] }] }] } },
	{ name: 'wrapping column fit-content within the room', width: 300, height: 200, tree: { style: { alignItems: 'Start' }, children: [{ style: { width: 67, alignItems: 'Start' }, children: [{ style: { wrap: true, height: 20 }, children: [box(50, 20), box(40, 20)] }] }] } },
	{ name: 'wrapping column minimum at its own height', width: 300, height: 200, tree: { style: { justify: 'End' }, children: [{ style: { wrap: true, basis: 40, height: 107, borderWidth: 2 }, children: [box(10, 50), box(10, 40), box(10, 73)] }] } },
	// (a wrapping row's max-content: an item's percentage basis of its indefinite width as auto's, its width)
	{ name: 'fit-content wrapping row, percentage basis', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row', wrap: true, alignSelf: 'Start' }, children: [box(26, 10), box(49, 10, { basis: '100%' })] }] } },
	// (a wrapping column's basis in a row: its lines broken at the height it is stretched to, but on one line in a row that is
	// a column's item, unless its items' heights or its min-height are percentages of its (a min-height in pixels not); its max-content, not the room's)
	{ name: 'wrapping column basis in a row', width: 300, height: 43, tree: { style: { direction: 'Row' }, children: [{ style: { wrap: true }, children: [box(2, 30), box(16, 30)] }] } },
	{ name: 'wrapping column basis in a row item', width: 300, height: 200, tree: { style: { direction: 'Row' }, children: [{ style: { direction: 'Row', height: 43 }, children: [{ style: { wrap: true }, children: [box(2, 30), box(16, 30)] }] }] } },
	{ name: 'wrapping column basis in a column item', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row', height: 43 }, children: [{ style: { wrap: true }, children: [box(2, 30), box(16, 30)] }] }] } },
	{ name: 'wrapping column basis in a column item, percentage heights', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row', height: 43 }, children: [{ style: { wrap: true }, children: [box(2, 2), box(16, '100%')] }] }] } },
	{ name: 'wrapping column basis in a column item, its min-height', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row', width: 72, height: 43 }, children: [{ style: { wrap: true, shrink: 0, minHeight: '50%' }, children: [box('50%', 88, { basis: 62, minWidth: 62 }), box(2, 29), box(89, 90, { margin: 8 })] }] }] } },
	{ name: 'wrapping column basis in a column item, a min-height in pixels', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row', height: 43 }, children: [{ style: { wrap: true, minHeight: 31 }, children: [box(58, 112), box(6, 6)] }] }] } },
	// (a wrapping column centred in a column: as wide as on one line, its flexed height (its min-height) not breaking it; its own height or max-height does)
	{ name: 'wrapping column fit-content, its min-height', width: 300, height: 200, tree: { children: [{ style: { alignItems: 'Center', height: 26 }, children: [{ style: { wrap: true, minHeight: 31 }, children: [box(58, 112), box(6, 6)] }] }] } },
	{ name: 'wrapping column fit-content, its max-height', width: 300, height: 200, tree: { children: [{ style: { alignItems: 'Center' }, children: [{ style: { wrap: true, maxHeight: 31 }, children: [box(58, 112), box(6, 6)] }] }] } },
	// (a wrapping column's basis in a column: its lines broken at its max-height in pixels, its tallest line's; a percentage one of its column's height not)
	{ name: 'wrapping column basis at its max-height', width: 300, height: 200, tree: { children: [{ children: [{ style: { wrap: true, maxHeight: 105 }, children: [{ style: { basis: 45 } }, { style: { basis: 68 } }] }] }] } },
	{ name: 'wrapping column basis, a percentage max-height', width: 300, height: 200, tree: { children: [{ children: [{ style: { minHeight: 34 } }, { style: { wrap: true, maxHeight: '50%' }, children: [{ style: { padding: 8, margin: 3 } }, { style: { padding: 1, margin: 2 } }, { style: { padding: 4 } }] }] }] } },
	// (a wrapping column's automatic minimum: its lines unbroken at its own height when that is a percentage)
	{ name: 'wrapping column minimum, a percentage height', width: 300, height: 200, tree: { children: [{ style: { height: 113 }, children: [{ style: { wrap: true, basis: 4, height: '100%' }, children: [{ style: { height: 76 } }, { style: { height: 30, margin: 4 } }] }] }] } },
	// (a wrapping row with less room than its widest item: its lines broken at its fit-content width, that item's)
	{ name: 'wrapping row narrower than its widest item', width: 300, height: 200, tree: { children: [{ style: { alignItems: 'Start', maxWidth: 10 }, children: [{ style: { direction: 'RowReverse', wrap: true }, children: [{ style: { padding: 8 } }, { style: { margin: 6 } }, { style: { borderWidth: 1 } }] }] }] } },
	// (a column's item with a basis in pixels: its height definite for its children's percentages, though the column's is not)
	{ name: 'basis in pixels definite in a column of auto height', width: 300, height: 200, tree: { style: { direction: 'Row' }, children: [{ style: { alignSelf: 'Start' }, children: [{ style: { basis: 115 }, children: [{ style: { height: '25%', width: 20 } }] }] }] } },
	{ name: 'basis in pixels, shrunk in a wrapping column: percentages of the size it shrank to', width: 300, height: 200, tree: { children: [{ style: { wrap: true, height: 39 }, children: [{ style: { direction: 'Row', alignItems: 'End', basis: 66, minHeight: '100%' }, children: [{ style: { minHeight: '25%', width: 10 } }] }] }] } },
	// (a wrapping row's max-content no less than its min-content: an item's basis under its content)
	{ name: 'wrapping row basis, its min-content', width: 300, height: 200, tree: { style: { direction: 'RowReverse' }, children: [{ style: { direction: 'RowReverse', wrap: true, grow: 0.5 }, children: [{ style: { basis: 39, minWidth: '50%' }, children: [{ style: { minWidth: 75, height: 10 } }] }] }] } },
	// (a wrapping column's automatic minimum: its lines broken at its height within its max-height)
	{ name: 'wrapping column minimum within its max-height', width: 300, height: 200, tree: { children: [{ style: { wrap: true, height: 52, maxHeight: 24, rowGap: 3 }, children: [box(16, 16), box(8, 8)] }, { style: { height: 193, shrink: 0 } }] } },
	// (found by layout-fuzz.mjs's more trees) a grid's absolute child at its static position by its alignment; a grid item's percentage width
	// auto while the tracks are sized; a track's auto minimum an item's min-content when it has a width, though it clips; aspect ratios: a
	// stretched item's contribution not from its flexed height, a fit-content width giving a column item's height, its automatic minimum
	// its own height; an absolute box's height at the width it shrank to
	{ name: 'grid absolute static position aligned', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', alignItems: 'End', justifyItems: 'Center' }, children: [box(20, 10, { position: 'Absolute' }), { style: { padding: 2 } }] }] } },
	{ name: 'grid item percentage width of its area', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', gridTemplateColumns: 'repeat(3, 1fr)' }, children: [box('100%', 10)] }] } },
	{ name: 'grid auto minimum of an item with a width', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', maxWidth: 75, gridTemplateColumns: 'repeat(3, 1fr)' }, children: [box(33, 10, { overflow: 'Hidden' }), h(10)] }] } },
	{ name: 'aspect ratio contribution not from a flexed height', width: 300, height: 200, tree: { children: [{ style: { alignSelf: 'Start' }, children: [{ style: { basis: 96, aspectRatio: 1 } }] }, { style: { basis: 96, aspectRatio: 1, alignSelf: 'Start' } }] } },
	{ name: 'aspect ratio height from a fit-content width', width: 300, height: 200, tree: { children: [{ style: { alignSelf: 'Start', aspectRatio: 0.5 }, children: [box(69, 0)] }] } },
	{ name: 'aspect ratio automatic minimum its height', width: 300, height: 200, tree: { children: [{ style: { alignSelf: 'Start' }, children: [{ style: { basis: 96, height: 111, aspectRatio: 1 } }] }] } },
	{ name: 'aspect ratio automatic minimum, its width not definite', width: 300, height: 200, tree: { children: [{ style: { basis: 19, height: 96, margin: [3, 4, 5, 'auto'], aspectRatio: 0.5 } }] } },
	{ name: 'absolute box height at its shrunk width', width: 300, height: 200, tree: { children: [{ style: { position: 'Absolute' }, children: [{ style: { aspectRatio: 0.5 } }, { children: [{ style: { padding: 8 } }] }] }] } },
	// (a grid's absolute child in its padding box; its tracks overflowing a centred grid on both sides, a distributed one at the end;
	// an item of its content's height not definite for its children's percentages)
	{ name: 'grid absolute static position in the padding box', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', padding: 2 }, children: [box(10, 10, { position: 'Absolute' })] }] } },
	{ name: 'grid tracks overflowing, centred', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', justify: 'Center', width: 73, padding: 9, gridTemplateColumns: 'repeat(3, 1fr)' }, children: [{ style: { padding: 7 } }, box(40, 8, { margin: [1, 5, 5, 'auto'] })] }] } },
	{ name: 'grid tracks overflowing, evenly', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', justify: 'SpaceEvenly', width: 39 }, children: [box('auto', 10, { minWidth: 50 })] }] } },
	{ name: 'grid item of its content height, percentages', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid' }, children: [{ style: { wrap: true, margin: [4, 8, 'auto', 2] }, children: [{ style: { padding: 10 } }, box(20, '50%')] }] }] } },
	// (a grid item's percentage min-height auto while the rows are sized; a grid's basis within its min-height when it has tracks;
	// percentage tracks auto while a grid's width is its content's)
	{ name: 'grid item percentage min-height while rows are sized', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid' }, children: [h(68), { style: { minHeight: '25%' } }] }] } },
	{ name: 'grid basis within its min-height', width: 300, height: 200, tree: { children: [{ style: { grow: 0.5, minHeight: 29, display: 'Grid' }, children: [h(10)] }, { style: { grow: 0.5, minHeight: 29, display: 'Grid', gridTemplateRows: 'auto auto' } }, { style: { grow: 0.5, minHeight: 29, display: 'Grid' } }] } },
	{ name: 'grid percentage tracks auto while fit to content', width: 300, height: 200, tree: { children: [{ style: { alignItems: 'Center', width: 49 }, children: [{ style: { display: 'Grid', gridTemplateColumns: '30% auto' }, children: [box(101, 10)] }] }, { style: { width: 72, display: 'Grid' }, children: [{ style: { margin: 9, display: 'Grid', gridTemplateColumns: '30% auto' }, children: [box(70, 10)] }] }] } },
	// (a spanning item's minimum shared up to the tracks' growth limits first, then beyond them equally)
	{ name: 'grid span up to growth limits', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid' }, children: [h(10), box(96, 10, { gridColumn: '1 / 3' })] }, { style: { display: 'Grid', gridTemplateColumns: 'auto auto' }, children: [box(20, 10), box(30, 10), box(96, 10, { gridColumn: '1 / 3' })] }] } },
	// (a grid's absolute children in the areas their lines give: an auto line or one the grid has not its padding edge)
	{ name: 'grid absolute children in their areas', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', gridTemplateColumns: '50px 1fr 60px', gridTemplateRows: '30px 40px', padding: 5 }, children: [
		box(10, 10, { position: 'Absolute', gridColumn: '-1' }), { style: { position: 'Absolute', gridColumn: '2 / 4', gridRow: '2', left: 3, right: 4, top: 0, bottom: 0 } },
		{ style: { position: 'Absolute', gridColumn: '1 / span 2', right: 0, height: 5 } }, box(8, 8, { position: 'Absolute', gridColumn: '7', gridRow: '1', bottom: 0 })] }] } },
	{ name: 'rtl grid absolute children in their areas', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', dir: 'Rtl', gridTemplateColumns: '50px 1fr 60px', padding: [0, 5, 0, 9] }, children: [
		{ style: { position: 'Absolute', gridColumn: '2 / 3', left: 0, right: 0, height: 5 } }, box(10, 10, { position: 'Absolute', gridColumn: '1' })] }] } },
	// (an item with an aspect ratio, neither size its own: at its start, its width the area's within the heights it may have through the ratio)
	{ name: 'grid item with an aspect ratio and a max height', width: 300, height: 200, tree: { children: [{ children: [{ style: { display: 'Grid' }, children: [{ style: { maxHeight: '50%', aspectRatio: 1 } }] }] }, { style: { display: 'Grid', gridTemplateColumns: '200px' }, children: [{ style: { aspectRatio: 2, minHeight: 20 } }] }] } },
	// (an item with an aspect ratio: its least width its min height's through the ratio; stretched, its width the height's, its content's when wider)
	{ name: 'row item with an aspect ratio, a min height, a stretched height', width: 300, height: 200, tree: { children: [{ style: { direction: 'Row' }, children: [{ style: { basis: 27, minHeight: 84, aspectRatio: 1 } }] },
		{ style: { direction: 'RowReverse' }, children: [{ style: { aspectRatio: 1 }, children: [{ style: { maxHeight: '25%' } }] }, { style: { padding: 2 } }] },
		{ style: { direction: 'RowReverse' }, children: [{ style: { maxHeight: 23, aspectRatio: 1 }, children: [{ style: { maxHeight: '25%' } }, { style: { width: 59 } }] }] }] } },
	// (a grid of a height laid out, not definite: its rows sized in an indefinite room (not shrunk to its max-height), stretched to its min-height, its percentage rows of its height)
	{ name: 'grid rows in a height laid out', width: 300, height: 200, tree: { children: [{ style: { alignItems: 'Center', display: 'Grid' }, children: [{ style: { maxHeight: '50%', display: 'Grid', gridAutoRows: 'minmax(10px, auto)' }, children: [h(60), {}] }] },
		{ style: { display: 'Grid', gridTemplateRows: '50% 20px', position: 'Absolute' }, children: [{}] },
		{ style: { aspectRatio: 1, width: 100 }, children: [{ style: { minHeight: '50%', display: 'Grid', position: 'Absolute' }, children: [{}] }] }] } },
	// (an item with an aspect ratio and neither size its own: the columns sized again from its rows' height through the ratio, the grid's
	// height its first rows'; its rows' contribution at the width it will have, within its max-width)
	{ name: 'grid columns sized again for an aspect ratio', width: 300, height: 200, tree: { children: [{ style: { display: 'Grid', width: 2, gridTemplateColumns: '50px 1fr' }, children: [{ style: { order: 2, aspectRatio: 0.5 } }, { style: { borderWidth: 3 } }] },
		{ style: { display: 'Grid', width: 100, gridTemplateColumns: 'auto auto' }, children: [{ style: { aspectRatio: 0.5 } }, h(10)] },
		{ style: { display: 'Grid', width: 300, gridTemplateColumns: 'min-content 1fr' }, children: [{ style: { aspectRatio: 0.5 } }, h(40)] },
		{ style: { display: 'Grid' }, children: [{ style: { maxWidth: 40, aspectRatio: 0.5 } }] }] } },
	// (a box with an aspect ratio, its height auto, its min-height auto, its overflow visible: its content's height when more than the ratio's,
	// within its max-height, a wrapping column's lines broken at the ratio's; a flex base size the ratio's, its minimum its content's within
	// its max-width through the ratio; a percentage height not)
	{ name: 'aspect ratio and the content height', width: 300, height: 200, tree: { children: [{ style: { width: 35, aspectRatio: 0.5 }, children: [{ style: { basis: 75 } }] },
		{ style: { direction: 'Row' }, children: [{ style: { width: 35, aspectRatio: 0.5 }, children: [h(75)] }, { style: { width: 35, aspectRatio: 0.5, overflow: 'Hidden' }, children: [h(75)] }, { style: { width: 35, aspectRatio: 0.5, maxHeight: 72 }, children: [h(75)] }] },
		{ style: { wrap: true, width: 74, aspectRatio: 1 }, children: [{ style: { minHeight: 62 } }, h(44)] },
		{ style: { maxWidth: 39, aspectRatio: 2 }, children: [h(25)] }, { children: [{ style: { width: 66, height: '50%', aspectRatio: 1 }, children: [{ style: { height: 52, margin: 8 } }] }] }] } },
	{ name: 'aspect ratio, a percentage height, shrunk', width: 300, height: 200, tree: { children: [{ style: { width: 70, height: '50%', aspectRatio: 2 } }, { style: { basis: 105 } }] } },
];
