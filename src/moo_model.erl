-module(moo_model).
-export([parse/4]).
-export_type([content_type/0]).

-type content_type() :: {binary(), binary(), '*' | [{binary(), binary()}]}.

-callback init(Opts) -> State when
	  Opts :: [proplists:property()],
	  State :: term().
-callback parse_attribute(Name, Value, State) -> {ok, State} | {error, Reason} when
	  Name :: binary(),
	  Value :: term(),
	  State :: term(),
	  Reason :: term().
-callback finalize(State) -> {ok, Result} | {error, Reason} when
	  Result :: term(),
	  State :: term(),
	  Reason :: term().

-spec parse(content_type(), cowboy_req:req(), module(), [proplists:property()]) -> {ok, term()} | {error, term()}.
parse({<<"application">>, <<"x-www-form-urlencoded">>, _},
      Req, Module, Opts) ->
	case proplists:lookup(max_body_length, Opts) of
		{max_body_length, MaxBodyLength} ->
			handle_body_qs(Req, Module, Opts, cowboy_req:body_qs(MaxBodyLength, Req));
		none ->
			handle_body_qs(Req, Module, Opts, cowboy_req:body_qs(Req))
	end;

parse({<<"application">>, <<"json">>, _},
      Req, Module, Opts) ->
	case proplists:lookup(max_body_length, Opts) of
		{max_body_length, MaxBodyLength} ->
			handle_body_json(Req, Module, Opts, cowboy_req:body(MaxBodyLength, Req));
		none ->
			handle_body_json(Req, Module, Opts, cowboy_req:body(Req))
	end;

parse(_, Req, _, _) ->
	{error, unsupported, Req}.

handle_body_qs(_, Module, Opts, {ok, BodyQs, Req}) ->
	process_proplist(BodyQs, Module, Req, Module:init(Opts));
handle_body_qs(Req, _, _, {error, Reason}) ->
	{error, Reason, Req}.

handle_body_json(_, Module, Opts, {ok, Body, Req}) ->
	try jsx:decode(Body) of
		[{}] ->
			process_proplist([], Module, Req, Module:init(Opts));
		Json when is_list(Json) ->
			process_proplist(Json, Module, Req, Module:init(Opts));
		_ ->
			{error, malformed_json, Req}
	catch
		error:badarg ->
			{error, malformed_json, Req}
	end;
handle_body_json(Req, _, _, {error, Reason}) ->
	{error, Reason, Req}.

process_proplist([], Module, Req, State) ->
	case Module:finalize(State) of
		{ok, Result} -> {ok, Result, Req};
		{error, Reason} -> {error, Reason, Req}
	end;
process_proplist([{K, V}|Rest], Module, Req, State) ->
	case Module:parse_attribute(K, V, State) of
		{ok, NewState} -> process_proplist(Rest, Module, Req, NewState);
		{error, Reason} -> {error, Reason, Req}
	end.
