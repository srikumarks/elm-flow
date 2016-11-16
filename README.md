# elm-flow

A library for expressing precisely coordinated activities
in the browser - for example, animation and audio events that need 
to be in perfect sync.

A "flow" can be used to produce a sequence of time stamped messages
whose structure and function are left open. These "messages" could be
`Html msg` or `Cmd msg` or any such effects. They are then expected
to be passed on to a subsystem that will perform the effects at the 
indicated time stamps.

Note that the implementation of these time stamps can be different
for different subsystems. For example, a `Html msg` can be rendered
only to within an accuracy of 15ms, whereas an audio event can be 
rendered with an accuracy of 0.02ms (1/48KHz sampling rate). It is
possible to use a high precision time stamp to cover both cases because
the WebAudio API spec recently added support for converting between
sample time and `DOMHiresTimeStamp`.

This is CONCEPTUAL/EXPERIMENTAL work in progress and needs to be 
considered in conjunction with appropriate timed execution backends.

These concepts are based on the Steller library - https://github.com/srikumarks/steller
