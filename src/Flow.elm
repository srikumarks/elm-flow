module Flow
    exposing
        ( Flow
        , isStopped
        , isFlowing
        , step
        , run
        , stopped
        , flow
        , lift
        , fire
        , delay
        , track
        , fork
        , loop
        , repeat
        , genloop
        , gate
        )

{-| This library is for expressing precisely coordinated activities
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
-}

import Clock
import List


type alias TimeStamp =
    Clock.TimeStamp


type alias TimeInterval =
    Clock.TimeStamp



{-| A `Flow` is a process that produces a sequence of time stamped 
effects as it runs.

Note that we're using `List` here just because it serves as a
general enough structure using which to place constraints on
how the flow outputs compose - i.e. accumulative, but
we ignore the accumulation order. If we had higher order
types and type constraints in Elm, we would use that instead.
-}

type Flow input msg
    = Stopped
    | Flowing (Clock.Clock -> input -> ( Clock.Clock, List ( TimeStamp, msg ), Flow input msg ))


empty : List a
empty =
    []


{-| Returns `True` if a flow is stopped.
-}
isStopped : Flow a b -> Bool
isStopped flow =
    case flow of
        Stopped ->
            True

        Flowing _ ->
            False


{-| Returns `True` if a flow is running.
Currently, a flow can only be in one of these two
states.
-}
isFlowing : Flow a b -> Bool
isFlowing flow =
    case flow of
        Stopped ->
            False

        Flowing _ ->
            True


{-| Steps a flow for the time step indicated by the given `Clock`,
taking in any input available that can influence the generated events.
-}          
step : Flow input msg -> Clock.Clock -> input -> ( Clock.Clock, List ( TimeStamp, msg ), Flow input msg )
step p clock input =
    case p of
        Stopped ->
            ( clock, empty, Stopped )

        Flowing stepFn ->
            stepFn clock input


{-| Similar to `step`, but runs the flow and accumulates all 
effects generated up to time `t`.
-}
run : Clock.TimeStamp -> Flow input msg -> Clock.Clock -> input -> ( Clock.Clock, List ( TimeStamp, msg ), Flow input msg )
run t p clock input =
    if clock.t1 < t then
        runHelper t p clock input empty
    else
        ( clock, empty, p )


runHelper t p clock input cmds =
    let
        ( clock_, cmd_, p_ ) =
            step p clock input
    in
        if clock_.t1 < t then
            runHelper t p_ clock_ input (cmd_ ++ cmds)
        else
            ( clock_, cmds, p_ )


{-| Constructs a stopped flow.
-}
stopped =
    Stopped


{-| Constructs a flow that maintains a hidden `state` that it then uses
to determine its evolution over time. When the `foldFn` produces 
`Nothing` for a following state, then flow is taken to be stopped.

Note that `flow` can only be used to create a running flow. Since
all stopped flows are equivalent, use `stopped` instead if you need
to create a stopped flow.
-}
flow : state -> (Clock.Clock -> input -> state -> ( Clock.Clock, List ( TimeStamp, msg ), Maybe state )) -> Flow input msg
flow state foldFn =
    Flowing
        (\clock input ->
            let
                ( clock_, cmd_, state_ ) =
                    foldFn clock input state
            in
                case state_ of
                    Nothing ->
                        ( clock_, cmd_, Stopped )

                    Just nextState ->
                        ( clock_, cmd_, flow nextState foldFn )
        )


{-| Embeds a flow within a larger structure.
-}
lift : (input_ -> input) -> (msg -> msg_) -> Flow input msg -> Flow input_ msg_
lift unwrap wrap p =
    case p of
        Stopped ->
            Stopped

        Flowing stepFn ->
            Flowing
                (\clock a ->
                    let
                        ( clock_, cmd_, p_ ) =
                            stepFn clock (unwrap a)
                    in
                        ( clock_, List.map (\( t, cmd ) -> ( t, wrap cmd )) cmd_, lift unwrap wrap p_ )
                )


{-| Adds time stamps to a pre-computed event generator.
-}
fire : (input -> List msg) -> Flow input msg
fire command =
    Flowing (\clock input -> ( clock, command input |> List.map (\msg -> ( clock.t1, msg )), Stopped ))


{-| A flow whose only impact is to cause a time delay.
-}
delay : TimeInterval -> Flow Float a
delay dt =
    flow 0.0
        (\clock rate t ->
            if t >= dt then
                ( clock, empty, Nothing )
            else
                let
                    clock_ =
                        Clock.step clock rate
                in
                    if t + clock_.t1r - clock.t1r >= dt then
                        ( Clock.jumpToRel clock rate (clock.t1r + (min (t + clock_.t1r - clock.t1r) dt) - t), empty, Nothing )
                    else
                        ( clock_, empty, Just (t + clock_.t1r - clock.t1r) )
        )


{-| A track causes a list of flows to run in strict temporal order.
Each flow is able to determine its own duration. Once a flow in the
sequence becomes "stopped", the next flow in the sequence will start.
Once all flows in the given list are exhausted, the track itself
becomes a stopped flow.
-}
track : List (Flow input msg) -> Flow input msg
track ps =
    flow ps
        (\clock input ps ->
            case ps of
                [] ->
                    ( clock, empty, Nothing )

                p1 :: ps_ ->
                    let
                        ( clock_, cmd_, p1_ ) =
                            step p1 clock input
                    in
                        case p1_ of
                            Stopped ->
                                ( clock_, cmd_, Just ps_ )

                            Flowing _ ->
                                ( clock_, cmd_, Just (p1_ :: ps_) )
        )


{-| Starts all flows in parallel.
Such a fork is assumed to finish once all the flows
given have reached "stopped" state.
-}
fork : List (Flow input msg) -> Flow input msg
fork ps =
    flow Nothing
        (\clock input state ->
            case state of
                Nothing ->
                    -- Uninitialized. Note that at this point we clone the
                    -- clock to all the forks. Thereafter, they may diverge.
                    forkStep (List.map (\p -> ( clock, p )) ps) clock input

                Just [] ->
                    -- Stopped
                    ( clock, empty, Nothing )

                Just realState ->
                    forkStep realState clock input
        )


forkStep realState clock input =
    let
        state_ =
            List.foldl
                (\( aClock, aProc ) state ->
                    let
                        ( clock_, cmd_, p_ ) =
                            step aProc aClock input
                    in
                        { state
                            | cmds = cmd_ ++ state.cmds
                            , procs =
                                if isStopped p_ then
                                    state.procs
                                else
                                    ( clock_, p_ ) :: state.procs
                        }
                )
                { cmds = empty, procs = empty }
                realState
    in
        case state_.procs of
            [] ->
                ( clock, state_.cmds, Nothing )

            _ ->
                ( Clock.tick clock, state_.cmds, Just (Just state_.procs) )


{-| Takes a condition function and keeps looping a flow as long
as that condition remains `True`. The given flow is restarted
from its original state.
-}
loop : (Int -> input -> Bool) -> Flow input msg -> Flow input msg
loop condition theFlow =
    case theFlow of
        Stopped ->
            Stopped

        Flowing _ ->
            flow { startFlow = theFlow, flow = theFlow, i = 0 }
                (\clock input state ->
                    if condition state.i input then
                        let
                            ( clock_, cmd_, flow_ ) =
                                step state.flow clock input
                        in
                            case flow_ of
                                Stopped ->
                                    ( clock_, cmd_, Just { state | i = state.i + 1, flow = state.startFlow } )

                                Flowing _ ->
                                    ( clock_, cmd_, Just { state | flow = flow_ } )
                    else
                        ( clock, empty, Nothing )
                )


{-| Repeats a flow `n` times.
-}
repeat : Int -> Flow input msg -> Flow input msg
repeat n =
    loop (\i _ -> i < n)


{-| A more generic loop where the condition itself is a flow.
The loop stops once the condition flow reaches stopped state.                              
-}
genloop : Flow ( Int, input ) a -> Flow input msg -> Flow input msg
genloop condition theFlow =
    case ( condition, theFlow ) of
        ( Stopped, _ ) ->
            Stopped

        ( _, Stopped ) ->
            Stopped

        ( _, Flowing _ ) ->
            flow { startCond = condition, condition = condition, startFlow = theFlow, flow = theFlow, i = 0 }
                (\clock input state ->
                    let
                        ( clock_, _, shouldCont ) =
                            step state.condition clock ( state.i, input )
                    in
                        case shouldCont of
                            Stopped ->
                                ( clock_, empty, Nothing )

                            Flowing _ ->
                                let
                                    ( clock_, cmd_, flow_ ) =
                                        step state.flow clock input
                                in
                                    case flow_ of
                                        Stopped ->
                                            ( clock_, cmd_, Just { state | flow = state.startFlow, i = state.i + 1 } )

                                        Flowing _ ->
                                            ( clock_, cmd_, Just { state | flow = flow_ } )
                )


{-| Uses one flow to control another. As long as the 
control flow is running, the result of the gated flow is
that of the given flow. Once the control flow stops, the
gated flow grinds to a halt.
-}
gate : Flow input msg -> Flow input msg -> Flow input msg
gate control theFlow =
    case ( control, theFlow ) of
        ( Stopped, _ ) ->
            Stopped

        ( _, Stopped ) ->
            Stopped

        _ ->
            flow { control = control, flow = theFlow }
                (\clock input state ->
                    let
                        ( clock_, _, control_ ) =
                            step state.control clock input
                    in
                        case control_ of
                            Stopped ->
                                ( clock_, empty, Nothing )

                            Flowing _ ->
                                let
                                    ( clock_, cmd_, flow_ ) =
                                        step state.flow clock input
                                in
                                    ( clock_, cmd_, Just { state | control = control_, flow = flow_ } )
                )
