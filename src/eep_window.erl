%% -------------------------------------------------------------------
%% Copyright (c) 2013 Darach Ennis < darach at gmail dot com >
%%
%% Permission is hereby granted, free of charge, to any person obtaining a
%% copy of this software and associated documentation files (the
%% "Software"), to deal in the Software without restriction, including
%% without limitation the rights to use, copy, modify, merge, publish,
%% distribute, sublicense, and/or sell copies of the Software, and to permit
%% persons to whom the Software is furnished to do so, subject to the
%% following conditions:
%%
%% The above copyright notice and this permission notice shall be included
%% in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
%% OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
%% NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
%% DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
%% OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
%% USE OR OTHER DEALINGS IN THE SOFTWARE.
%%
%% File: eep_window.erl. Generic window-based functionality.
%%
%% -------------------------------------------------------------------
-module(eep_window).

-export([start/3]).
-export([start/4]).

-export([loop/3]).

-export([tumbling/5]).
-export([sliding/5]).
-export([push/2]).
-export([tick/1]).

-include("eep_erl.hrl").

%% Pure window functionality.

%% Window type creation functions.
%% TODO More window types/options to follow.
tumbling(Clock, clock, Size, Aggregate, Seed) ->
    #eep_win{type=tumbling, by=time, compensating=false,
         size=Size, aggmod=Aggregate, agg=(Aggregate:init(Seed)),
            clockmod=Clock, clock=(Clock:new(Size))};
tumbling(none, events, Size, Aggregate, Seed) ->
    #eep_win{type=tumbling, by=events, compensating=false,
             size=Size, aggmod=Aggregate, agg=(Aggregate:init(Seed))}.

sliding(Clock, clock, Size, Aggregate, Seed) ->
    #eep_win{type=sliding, by=time, compensating=true,
         size=Size, aggmod=Aggregate, agg=(Aggregate:init(Seed)),
         clockmod=Clock, clock=(Clock:new(Size))};
%% TODO This might need refactoring to give a more consistent control surface
sliding(none, events, Size, Aggregate, Seed) ->
    #eep_win{type=sliding, by=events, compensating=true,
         size=Size, aggmod=Aggregate, agg=(Aggregate:init(Seed))}.

%% Window command interface.
push(Event, #eep_win{type=sliding, by=time}=Win) ->
    decide([accumulate], Event, Win);
push(Event, #eep_win{type=sliding, by=events}=Win) ->
    #eep_win{count=Count, size=Size} = Win,
    Actions = slide(Count, Size),
    decide(Actions, Event, Win);
push(Event, #eep_win{type=tumbling, by=time}=Win) ->
    Actions = [accumulate], % TODO Work this into tumble/2 below
    decide(Actions, Event, Win);
push(Event, #eep_win{type=tumbling, by=events}=Win) ->
    #eep_win{count=Count, size=Size} = Win,
    Actions = tumble(Count, Size),
    decide(Actions, Event, Win).

tick(#eep_win{by=time}=Win) ->
    #eep_win{compensating=Comps, clockmod=CkMod, clock=Clock} = Win,
    case eep_clock:tick(CkMod, Clock) of
        {noop, UnTicked} -> {noop, Win#eep_win{clock=UnTicked}};
        {tock, Tocked} ->
            Action =
                if Comps -> [emit, compensate];
                   true -> [emit, reset]
                end,
            decide(Action, noop, Win#eep_win{clock=Tocked})
    end;
tick(#eep_win{}=_in) ->
    error({how, can, you, tick, that, which, is, untickable}).

%% Window behaviour functions: given the current relevant state of a window,
%% pick what action(s) are next.
%% TODO Most of this logic could be covered by using a monotonic clock and the
%% tick/tock mechanism on push instead.
tumble(Count, Size) when Count  < Size -> [accumulate];
tumble(Count, Size) when Count >= Size -> [accumulate, emit, reset].

slide(Count, Size) when Count  < Size -> [accumulate];
slide(Count, Size) when Count == Size -> [accumulate, emit];
slide(Count, Size) when Count  > Size -> [compensate, accumulate, emit].

%% Window internal mechanisms: these correspond to the actions decided upon
%% by the behaviour functions above.
accumulate(Event, #eep_win{aggmod=AMod, agg=Agg, count=Count}=Win) ->
    Accumed = Win#eep_win{agg=(AMod:accumulate(Agg, Event)), count=Count+1},
    if Win#eep_win.compensating -> %% If we're to compensate we must store the events
           Accumed#eep_win{events= Win#eep_win.events++[Event]};
       true ->
           Accumed
    end.

compensate(#eep_win{events=[]}=Win) -> %% No events, no compensation.
    Win;
compensate(#eep_win{aggmod=AMod, agg=Agg, events=[Oldest|Es]}=Win) ->
    Win#eep_win{agg=(AMod:compensate(Agg, Oldest)), events=Es}.

reset(#eep_win{aggmod=AMod, seed=Seed}=Win) ->
    Win#eep_win{agg=(AMod:init(Seed)), count=1}.

%% Given a list of actions (from the behaviour functions above), an event and
%% the current window state, apply the actions in order and return the result.
%% Its implementation is ~equivalent to lists:foldl/3 on the list of actions.
decide(Actions, Event, Window) ->
    decide(Actions, Event, Window, noop).

decide([], _, Window, Decision) -> {Decision, Window};
decide([accumulate|Actions], Event, Window, Decision) ->
    decide(Actions, Event, accumulate(Event, Window), Decision);
decide([compensate|Actions], Event, Window, Decision) ->
    decide(Actions, Event, compensate(Window), Decision);
decide([reset|Actions], Event, Window, Decision) ->
    decide(Actions, Event, reset(Window), Decision);
decide([emit|Actions], Event, Window, noop) ->
    %% TODO This enforces only one emission per decision: is this right?
    decide(Actions, Event, Window, {emit, Window#eep_win.agg}).

%% Process functionality: utils for running windows as a process.
start(Window, AggMod, Interval) ->
    start(Window, AggMod, eep_clock_wall, Interval).
start(Window, AggMod, ClockMod, Interval) ->
    {ok, EventPid } = gen_event:start_link(),
    CallbackFun = fun(NewAggregate) ->
        gen_event:notify(
            EventPid,
            {emit, AggMod:emit(NewAggregate)}
        )
    end,
    State = Window:new(AggMod, ClockMod, CallbackFun, Interval),
    spawn(?MODULE, loop, [Window, EventPid, State]).

loop(Window, EventPid, State) ->
  receive
    tick ->
      {_,NewState} = Window:tick(State),
      loop(Window, EventPid, NewState);
    { push, Event } ->
      {_,NewState} = Window:push(State,Event),
      loop(Window, EventPid, NewState);
    { add_handler, Handler, Arr } ->
      gen_event:add_handler(EventPid, Handler, Arr),
      loop(Window, EventPid, State);
    { delete_handler, Handler } ->
      gen_event:delete_handler(EventPid, Handler, []),
      loop(Window, EventPid, State);
    stop ->
      ok;
    {debug, From} ->
      From ! {debug, State},
      loop(Window, EventPid, State)
  end.
