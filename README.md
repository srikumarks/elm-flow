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

Another issue that I expect elm-flow to address is the synchronization
of just-in-time scheduled visuals and sounds. Since the perception of
audio is sensitive to breakups, audio is usually scheduled in a
double-buffered manner, where one buffer of, say, 512 sample frames
is computed while another buffer is being played out of the audio
subsystem. Here we trade off low latency response for continuous
audio. Visual displays, however, need to necessarily complete computation
within about 15ms and there is not as significant a perceptual penalty
for a skipped frame. So display latency can be kept within about 15ms. 
This means we're usually computing and scheduling audio a bit ahead 
of the corresponding frame to display. Furthermore, the audio output
pipeline can impose its own latencies. If you use a bluetooth speaker,
for example, you can incur an additional audio latency of about 300ms.
That's 20 frames of visuals! So a mechanism where we're able to precompute
and schedule visual frames as well as audio can be useful for such
applications.

This is CONCEPTUAL/EXPERIMENTAL work in progress and needs to be 
considered in conjunction with appropriate timed execution backends.

These concepts are based on the Steller library - https://github.com/srikumarks/steller
