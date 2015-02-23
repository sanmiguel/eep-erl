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
%% File: eep_erl.hrl. Embedded Event Processing. Header file.
%%
%% -------------------------------------------------------------------

-define(EEP_MAX, 10000000000000).

-record(eep_clock,
        {
         at = undefined :: integer() | undefined,
         mark = undefined :: integer() | undefined,
         interval = 1 :: integer()
        }).

-record(eep_win,
        {
         type :: tumbling | sliding,
         by :: events | ticks,
         compensating :: boolean(),
         size :: pos_integer(),
         aggmod :: module(),
         agg :: any(),
         clockmod :: module(),
         clock :: any(),
         seed = [] :: list(),
         count = 1,
         log = eep_winlog:new() :: list(any())
        }).

-type ck_state() :: #eep_clock{}.
-export_type([ck_state/0]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
