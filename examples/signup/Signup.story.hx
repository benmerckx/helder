import helder.story.Story;

// The card as screens, light and dark (`helder studio examples/signup`)
final light = story({name: "Sign up/Light", width: 420, height: 360, render: () -> Signup.themed(false)});

final dark = story({name: "Sign up/Dark", width: 420, height: 360, render: () -> Signup.themed(true)});
