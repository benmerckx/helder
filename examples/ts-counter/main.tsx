// title: Counter in TypeScript
// summary: The counter in TSX: a signal, markup bound to it, a button that changes it
// tags: typescript, ui, view, signals
// demo: canvas 320x200
// The counter in TypeScript: a signal, TSX bound to it, a button that changes it.
import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);

UiWindow.run(
	<Surface title="Counter" width={320} height={200}>
		<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
			<text font-size={32}>{count}</text>
			<view:button role="button" focusable padding="8 16" radius={6} background="#18181b" color="#fafafa" cursor="pointer"
				onPress={() => count(c => c + 1)}>+1</view:button>
		</view>
	</Surface>
);
