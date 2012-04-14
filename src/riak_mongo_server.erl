%%
%% This file is part of riak_mongo
%%
%% Copyright (c) 2012 by Pavlo Baron (pb at pbit dot org)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

%% @author Pavlo Baron <pb at pbit dot org>
%% @doc This is the TCP server of riak_mongo
%% @copyright 2012 Pavlo Baron

-module(riak_mongo_server).

-export([start_link/2, handle_info/2, new_connection/2, init/1, sock_opts/0]).

-behavior(gen_nb_server).

-include("riak_mongo_state.hrl").

start_link(IpAddr, Port) ->
    gen_nb_server:start_link(?MODULE, IpAddr, Port, []).

init(_Args) ->
    {ok, #server_state{old_owner=self()}}.

handle_info({controlling_process, Pid}, State) ->
    gen_tcp:controlling_process(State#server_state.sock, Pid),
    {reply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

new_connection(Sock, State) ->
    NewState = #server_state{old_owner=riak_mongo_worker_sup:new_worker(Sock, State),
				sock=Sock},
    {ok, NewState}.

sock_opts() ->
    [binary, {active, once}, {packet, 0}].
