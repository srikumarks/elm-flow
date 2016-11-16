module Clock
    exposing
        ( TimeStamp
        , Clock
        , clock
        , step
        , tick
        , jumpTo
        , jumpToRel
        , sync
        , abs2rel
        , rel2abs
        )


{-| The `Clock` module exposes a clock that tracks a time
interval featuring real physical time as well as a rate
integrated "virtual" time. The virtual time is useful 
in cases where we want to exercise control over the rate
of evolution of a flow, such as when controlling musical
tempo.
-}

type alias TimeStamp =
    Float


type alias Clock =
    { dt : Float
    , t1 : TimeStamp
    , t2 : TimeStamp
    , t1r : TimeStamp
    , t2r : TimeStamp
    , rate : Float
    }


{-| Constructs a clock in its initial state.
-}                          
clock : Float -> Float -> TimeStamp -> Clock
clock rate dt t =
    Clock dt t (t + dt) 0.0 (rate * dt) rate


{-| Step a clock to the next time interval.
The rate can be changed using this function.
-}
step clock rate =
    { clock
        | t1 = clock.t2
        , t2 = clock.t2 + clock.dt
        , t1r = clock.t2r
        , t2r = clock.t2r + rate * clock.dt
        , rate = rate
    }


{-| Same as `step`, but uses the clock's current rate.
-}
tick clock =
    step clock clock.rate


jumpTo clock rate t =
    let
        dt =
            t - clock.t1

        dtr =
            dt * rate
    in
        { clock
            | t1 = clock.t1 + dt
            , t2 = clock.t2 + dt
            , t1r = clock.t1r + dtr
            , t2r = clock.t2r + dtr
            , rate = rate
        }


jumpToRel clock rate tr =
    let
        dtr =
            tr - clock.t1r

        dt =
            dtr / rate
    in
        { clock
            | t1 = clock.t1 + dt
            , t2 = clock.t2 + dt
            , t1r = clock.t1r + dtr
            , t2r = clock.t2r + dtr
            , rate = rate
        }


sync clock1 clock2 =
    { clock1
        | t1 = clock2.t1
        , t2 = clock2.t1 + clock1.dt
        , t1r = clock2.t1r
        , t2r = clock2.t1r + clock1.rate * clock1.dt
    }


{-| Converts a relative (i.e. rate integrated) time stamp to 
absolute time in the reference frame of a given clock.
-}
rel2abs clock rel =
    clock.t1 + (rel - clock.t1r) / clock.rate


{-| Converts an absolute time stamp to relative (i.e. rate
integrated) time in the reference frame of a given clock.
-}                    
abs2rel clock t =
    clock.t1r + clock.rate * (t - clock.t1)
