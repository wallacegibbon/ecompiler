-module(ecompiler_parse_test).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

function_normal_test() ->
    {ok, Tks, _} = ecompiler_scan:string( "fun a(v: i8^): void v^ = 10; end"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks, [{'fun',1}, {identifier,1,a}, {'(',1},
		       {identifier,1,v}, {':',1}, {basic_type,1,i8}, {'^',1},
		       {')',1}, {':',1}, {basic_type,1,void},
		       {identifier,1,v}, {'^',1}, {'=',1}, {integer,1,10},
		       {';',1}, {'end',1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast, [{function_raw,1,a,
			[{vardef,1,v,{basic_type,1,{i8,1}},none}],
			{basic_type,1,{void,0}},
			[{op2,1,assign,
			  {op1,1,'^',{varref,1,v}},
			  {integer,1,10}}]}]),
    ok.

function_pointer_test() ->
    {ok, Tks, _} = ecompiler_scan:string("a: fun(u8, u8^): u16^ = b;"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks, [{identifier,1,a}, {':',1}, {'fun',1}, {'(',1},
		       {basic_type,1,u8}, {',',1}, {basic_type,1,u8}, {'^',1},
		       {')',1}, {':',1}, {basic_type,1,u16}, {'^',1}, {'=',1},
		       {identifier,1,b}, {';',1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast, [{vardef,1,a,
			{fun_type,1, [{basic_type,1,{u8,0}},
				      {basic_type,1,{u8,1}}],
			 {basic_type,1,{u16,1}}},
			{varref,1,b}}]),
    ok.

array_test() ->
    {ok, Tks, _} = ecompiler_scan:string("a: {u8, 100};"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks, [{identifier,1,a}, {':',1}, {'{',1}, {basic_type,1,u8},
		       {',',1}, {integer,1,100}, {'}',1}, {';',1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast, [{vardef,1,a,{array_type,1,{basic_type,1,{u8,0}},100},
			none}]),
    ok.

-endif.