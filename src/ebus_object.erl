-module(ebus_object).

-type init_result() ::
        {ok, State :: any()} |
        {stop, Reason :: term()}.

-type action() ::
        {signal, Interface::string(), Member::string()} |
        {signal, Path::ebus:object_path(), Interface::string(), Member::string(),
         Types::ebus:signature(), Args::[any()]} |
        {reply, Msg::ebus:message(), Types::ebus:signature(), Args::[any()]} |
        {reply_error, Msg::ebus:message(), ErrorName::string(), ErrorMsg::string() | undefined} |
        {continue, Continue::any}.

-type handle_call_result() ::
        {reply, Reply :: term(), State :: any()} |
        {reply, Reply :: term(), State :: any(), Action :: action()} |
        {noreply, State :: any()} |
        {noreply, State :: any(), Action :: action()} |
        {stop, Reason :: term(), State::any()} |
        {stop, Reason :: term(), Reply::term(), State::any()}.

-type handle_cast_result() ::
        {noreply, State::any()} |
        {noreply, State::any(), Action :: action()} |
        {stop, Reason::term(), State::any()}.

-type handle_info_result() ::
        {noreply, State :: any()} |
        {noreply, State :: any(), Action :: action()} |
        {stop, Reason :: term(), State::any()}.

-type handle_message_result() ::
        {noreply, State::any()} |
        {reply, Types::ebus:signature(), Args::[any()], State::any()} |
        {reply_error, ErrorName::string(), ErrorMsg::string() | undefined, State::any()} |
        {stop, Reason :: term(), State::any()}.

-export_type([init_result/0, handle_call_result/0, handle_cast_result/0,
              handle_info_result/0, handle_message_result/0]).

-callback init(Args::[any()]) -> init_result().
-callback handle_message(Member::string(), Message::ebus:message(), State::any()) -> handle_message_result().
-callback handle_call(Msg::term(), From::term(), State::any()) -> handle_call_result().
-callback handle_cast(Msg::term(), State::any()) -> handle_cast_result().
-callback handle_info(Msg::term(), State::any()) -> handle_info_result().
-callback handle_continue(Msg::term(), State::any()) -> handle_info_result().
-callback terminate(Reason::term(), State::any()) -> any().

-optional_callbacks([handle_info/2, handle_call/3, handle_cast/2, handle_continue/2, terminate/2]).

-behavior(gen_server).

%% gen_server
-export([start/5, stop/2, start_link/5, init/1,
         handle_call/3, handle_cast/2, handle_info/2, handle_continue/2,
         terminate/2]).

-record(state, {
                module :: atom(),
                state :: any(),
                path :: string(),
                bus :: pid()
               }).

start(Bus, Path, Module, Args, Options) ->
    gen_server:start(?MODULE, [Bus, Path, Module, Args], Options).

stop(Pid, Reason) ->
    gen_server:stop(Pid, Reason, infinity).

start_link(Bus, Path, Module, Args, Options) ->
    gen_server:start_link(?MODULE, [Bus, Path, Module, Args], Options).

init([Bus, Path, Module, Args]) ->
    case Module:init(Args) of
        {ok, MState} ->
            case ebus:register_object_path(Bus, Path, self()) of
                ok ->
                    {ok, #state{bus=Bus, path=Path, module=Module, state=MState}};
                Other ->
                    {stop, Other}
            end;
        Other -> Other
    end.

handle_call(Msg, From, State=#state{module=Module, state=ModuleState0}) ->
    case erlang:function_exported(Module, handle_call, 3) of
        true -> case Module:handle_call(Msg, From, ModuleState0) of
                    {reply, Reply, ModuleState} ->
                        {reply, Reply, State#state{state=ModuleState}};
                    {reply, Reply, ModuleState, Action} ->
                        handle_action({reply, Reply}, Action, State#state{state=ModuleState});
                    {noreply, ModuleState}  ->
                        {noreply, State#state{state=ModuleState}};
                    {noreply, ModuleState, Action} ->
                        handle_action(noreply, Action, State#state{state=ModuleState});
                    {stop, Reason, ModuleState} ->
                        {stop, Reason, State#state{state=ModuleState}};
                    {stop, Reason, Reply, ModuleState} ->
                        {stop, Reason, Reply, State#state{state=ModuleState}}
                end;
        false -> {reply, ok, State}
    end.

handle_cast(Msg, State=#state{module=Module, state=ModuleState0}) ->
    case erlang:function_exported(Module, handle_cast, 2) of
        true -> case Module:handle_cast(Msg, ModuleState0) of
                    {noreply, ModuleState}  ->
                        {noreply, State#state{state=ModuleState}};
                    {noreply, ModuleState, Action} ->
                        handle_action(noreply, Action, State#state{state=ModuleState});
                    {stop, Reason, ModuleState} ->
                        {stop, Reason, State#state{state=ModuleState}}
                end;
        false -> {noreply, State}
    end.

handle_info({handle_message, Msg}, State=#state{module=Module, state=ModuleState0}) ->
    case erlang:function_exported(Module, handle_message, 3) of
        true ->
            case Module:handle_message(ebus_message:interface_member(Msg), Msg, ModuleState0) of
                {reply, Types, Args, ModuleState} ->
                    handle_action(noreply, {reply, Msg, Types, Args},
                                  State#state{state=ModuleState});
                {reply_error, ErrorName, ErrorMsg, ModuleState} ->
                    handle_action(noreply, {reply_error, Msg, ErrorName, ErrorMsg},
                                 State#state{state=ModuleState});
                {noreply, ModuleState}  ->
                    {noreply, State#state{state=ModuleState}};
                {stop, Reason, ModuleState} ->
                    {stop, Reason, State#state{state=ModuleState}}
            end;
        false ->
            {noreply, State}
    end;
handle_info(Msg, State=#state{module=Module, state=ModuleState0}) ->
    case erlang:function_exported(Module, handle_info, 2) of
        true -> handle_info_result(Module:handle_info(Msg, ModuleState0), State);
        false -> {noreply, State}
    end.

handle_continue(Msg, State=#state{module=Module, state=ModuleState0}) ->
    case erlang:function_exported(Module, handle_continue, 2) of
        true -> handle_info_result(Module:handle_continue(Msg, ModuleState0), State);
        false -> {noreply, State}
    end.

terminate(Reason, State=#state{module=Module, state=ModuleState}) ->
    ebus:unregister_object_path(State#state.bus, self()),
    case erlang:function_exported(Module, terminate, 2) of
        true -> Module:terminate(Reason, ModuleState);
        false -> ok
    end.



%%
%% Internal
%%

handle_info_result({noreply, ModuleState}, State) ->
    {noreply, State#state{state=ModuleState}};
handle_info_result({noreply, ModuleState, Action}, State) ->
    handle_action(noreply, Action, State#state{state=ModuleState});
handle_info_result({stop, Reason, ModuleState}, State) ->
    {stop, Reason, State#state{state=ModuleState}}.

-spec handle_action(Result::noreply | {reply, any()}, Action::action(), #state{})
                   -> {noreply, #state{}} |
                      {noreply, #state{}, {continue, any()}} |
                      {reply, any(), #state{}} |
                      {reply, any(), #state{}, {continue, any()}}.
handle_action(Result, {signal, Interface, Member}, State=#state{}) ->
    handle_action(Result, {signal, State#state.path, Interface, Member, [], []}, State);
handle_action(Result, {signal, Path, Interface, Member, Types, Args}, State=#state{}) ->
    {ok, Msg}  = ebus_message:new_signal(Path, Interface, Member),
    ok = ebus_message:append_args(Msg, Types, Args),
    ok = ebus:send(State#state.bus, Msg),
    handle_result(Result, State);
handle_action(Result, {reply, Msg, Types, Args}, State=#state{}) ->
    {ok, Reply} = ebus_message:new_reply(Msg, Types, Args),
    ok = ebus:send(State#state.bus, Reply),
    handle_result(Result, State);
handle_action(Result, {reply_error, Msg, ErrorName, ErrorMsg}, State=#state{}) ->
    {ok, Reply} = ebus_message:new_reply_error(Msg, ErrorName, ErrorMsg),
    ok = ebus:send(State#state.bus, Reply),
    handle_result(Result, State);
handle_action(Result, {continue, Continue}, State=#state{}) ->
    handle_result({Result, {continue, Continue}}, State).

handle_result(noreply, State=#state{}) ->
    {noreply, State};
handle_result({noreply, {continue, Continue}}, State) ->
    {noreply, State, {continue, Continue}};
handle_result({reply, Reply}, State=#state{}) ->
    {reply, Reply, State};
handle_result({{reply, Reply}, {continue, Continue}}, State=#state{}) ->
    {reply, Reply, State, {continue, Continue}}.
