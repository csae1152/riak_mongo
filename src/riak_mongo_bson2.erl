%%
%% This file is part of riak_mongo
%%
%% Copyright (c) 2012 by Trifork
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

%% @author Kresten Krab Thorup
%%
%% @doc Encode/decode bson to Erlang terms.
%%
%% The reason for not using the standard erlang-bson module is that
%% (1) erlang-bson does not specify a license which leaves us in libo
%% for using it, (2) erlang-bson generates atoms for all keys in BSON
%% documents, which is highly undesirable for server-side programming
%% since atoms are not garbage collected. In this implementation keys
%% are always utf8-encoded binaries. And finally, (3) we find the
%% mochi_json-like structure easier to work with.
%%
%% @copyright 2012 Trifork

-module(riak_mongo_bson2).

-export([get_document/1, get_raw_document/1]).

-include("riak_mongo_bson2.hrl").

-define(DOUBLE_TAG,    16#01).
-define(STRING_TAG,    16#02).
-define(DOCUMENT_TAG,  16#03).
-define(ARRAY_TAG,     16#04).
-define(BINARY_TAG,    16#05).
-define(UNDEFINED_TAG, 16#06).
-define(OBJECTID_TAG,  16#07).
-define(BOOLEAN_TAG,   16#08).
-define(UTC_TIME_TAG,  16#09).
-define(NULL_TAG,      16#0A).
-define(REGEX_TAG,     16#0B).
-define(JAVASCRIPT_TAG,16#0D).
-define(SYMBOL_TAG,    16#0E).
-define(INT32_TAG,     16#10).
-define(INT64_TAG,     16#12).
-define(MIN_KEY_TAG,   16#FF).
-define(MAX_KEY_TAG,   16#7f).

%%
%% get and parse document from binary
%%
-spec get_document(binary()) -> {bson_document(), binary()}.
get_document(<<Size:32/little-unsigned, Rest0/binary>>) ->
    BodySize = Size-5,
    <<Body:BodySize/binary, 0, Rest/binary>> = Rest0,
    {{struct, get_elements(Body, [])}, Rest}.

%%
%% get raw document (we use this for INSERT)
%%
-spec get_raw_document(binary()) -> {bson_raw_document(), binary()}.
get_raw_document(<<Size:32/little-unsigned, _/binary>>=Binary) ->
    <<Document:Size/binary, Rest/binary>> = Binary,
    case get_raw_element(<<"_id">>, Document) of
        {ok, ID} -> ok;
        false -> ID = undefined
    end,
    {#bson_raw_document{ id=ID, body=Document}, Rest}.


get_raw_element(Bin, <<_Size:32, Body/binary>>) ->
    get_raw_element0(Bin, Body).

get_raw_element0(_,<<0>>) ->
    false;
get_raw_element0(Bin, Body) ->
    case get_element(Body) of
        {{Bin, Value}, _} ->
            {ok, Value};
        {_, Rest} ->
            get_raw_element0(Bin, Rest)
    end.


get_elements(<<>>, Acc) ->
    lists:reverse(Acc);

get_elements(Bin, Acc) ->
    {KeyValue, Rest} = get_element(Bin),
    get_elements(Rest, [KeyValue|Acc]).

-compile({inline,[get_element/1, get_element_value/2]}).

get_element(<<Tag, Rest0/binary>>) ->
    {Name, Rest1} = get_cstring(Rest0),
    {Value, Rest2} = get_element_value(Tag, Rest1),
    {{Name,Value}, Rest2}.

get_element_value(?DOUBLE_TAG, <<Value:64/float, Rest/binary>>) ->
    {Value, Rest};

get_element_value(?STRING_TAG, Rest) ->
    get_string(Rest);

get_element_value(?DOCUMENT_TAG, Rest) ->
    get_document(Rest);

get_element_value(?ARRAY_TAG, Rest0) ->
    {{struct, Elements}, Rest} = get_document(Rest0),
    {elements_to_list(Elements), Rest};

get_element_value(?BINARY_TAG, Rest) ->
    get_binary(Rest);

get_element_value(?UNDEFINED_TAG, Rest) ->
    {undefined, Rest};

get_element_value(?OBJECTID_TAG, <<ObjectID:12/binary, Rest>>) ->
    {{objectid, ObjectID}, Rest};


get_element_value(?BOOLEAN_TAG, <<Bool, Rest/binary>>) ->
    case Bool of
        0 -> {true, Rest};
        1 -> {false, Rest}
    end;

get_element_value(?UTC_TIME_TAG, <<MilliSecs:64/little-unsigned, Rest/binary>>) ->
    {{MilliSecs div 1000000000, (MilliSecs div 1000) rem 1000000, (MilliSecs * 1000) rem 1000000}, Rest};

get_element_value(?NULL_TAG, Rest) ->
    {null, Rest};

get_element_value(?REGEX_TAG, Rest0) ->
    {Regex, Rest1} = get_cstring(Rest0),
    {Options, Rest} = get_cstring(Rest1),
    {{regex, Regex, Options}, Rest};

get_element_value(?JAVASCRIPT_TAG, Rest0) ->
    {Value, Rest} = get_string(Rest0),
    {{javascript, Value}, Rest};

get_element_value(?SYMBOL_TAG, Rest0) ->
    {Value, Rest} = get_string(Rest0),
    {{symbol, Value}, Rest};

get_element_value(?INT32_TAG, <<Value:32/little-signed, Rest>>) ->
    {Value, Rest};

get_element_value(?INT64_TAG, <<Value:64/little-signed, Rest>>) ->
    {Value, Rest};

get_element_value(?MIN_KEY_TAG, Rest) ->
    {'$min_key', Rest};

get_element_value(?MAX_KEY_TAG, Rest) ->
    {'$max_key', Rest}.


-spec get_binary(binary()) -> {bson_binary(), binary()}.
get_binary(<<Size:32/little-unsigned, SubType, Blob:Size/binary, Rest/binary>>) ->
    case SubType of
        16#00 -> Tag = binary;
        16#01 -> Tag = function;
        16#02 -> Tag = binary;
        16#03 -> Tag = uuid;
        16#04 -> Tag = md5;
        16#80 -> Tag = binary
    end,
    {{Tag, Blob}, Rest}.

-spec get_cstring(binary()) -> {bson_utf8(), binary()}.
get_cstring(Bin) ->
    {Pos, _} = binary:match(Bin, <<0>>),
    <<Value:Pos/binary, 0, Rest/binary>> = Bin,
    {Value, Rest}.

-spec get_string(binary()) -> {bson_utf8(), binary()}.
get_string(<<Length:32/little-unsigned, Bin/binary>>) ->
    StringLength = Length-1,
    <<Value:StringLength/binary, 0, Rest/binary>> = Bin,
    {Value, Rest}.

%% @doc convert `[{<<"0">>, Value1}, {<<"1">>, Value2}, ...]' to `[Value1, Value2, ...]'
-spec elements_to_list([bson_element()]) -> [bson_value()].
elements_to_list(Elements) ->
    elements_to_list(0, Elements, []).

elements_to_list(N, [{NBin, Value}|Rest], Acc) ->
    N = bin_to_int(NBin),
    elements_to_list(N+1, Rest, [Value|Acc]);
elements_to_list(_, [], Acc) ->
    lists:reverse(Acc).

bin_to_int(Bin) ->
    bin_to_int(Bin, 0).

bin_to_int(<<>>, N) ->
    N;
bin_to_int(<<CH, Rest/binary>>, N) ->
    bin_to_int(Rest, N*10 + (CH - $0)).
