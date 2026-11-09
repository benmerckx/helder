import helder.story.Story;

// The client as a screen (`helder studio examples/mail`)
final inbox = story({name: "Mail/Inbox", width: 860, height: 560, render: () -> Mail.themed()});
