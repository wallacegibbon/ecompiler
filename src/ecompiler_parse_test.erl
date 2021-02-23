-module(ecompiler_parse_test).

-ifdef(EUNIT).

-include_lib("eunit/include/eunit.hrl").

function_normal_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("fun a(v: i8^) v^ = 10; end"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{'fun', 1}, {identifier, 1, a}, {'(', 1},
		  {identifier, 1, v}, {':', 1}, {integer_type, 1, i8},
		  {'^', 1}, {')', 1}, {identifier, 1, v}, {'^', 1},
		  {'=', 1}, {integer, 1, 10}, {';', 1}, {'end', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{function_raw, 1, a,
		   [{vardef, 1, v, {basic_type, 1, 1, integer, i8}, none}],
		   {basic_type, 1, 0, void, void},
		   [{op2, 1, assign, {op1, 1, '^', {varref, 1, v}},
		     {integer, 1, 10}}]}]),
    ok.

function_pointer_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("a: fun(u8, u8^): u16^ = b;"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{identifier, 1, a}, {':', 1}, {'fun', 1}, {'(', 1},
		  {integer_type, 1, u8}, {',', 1}, {integer_type, 1, u8},
		  {'^', 1}, {')', 1}, {':', 1}, {integer_type, 1, u16},
		  {'^', 1}, {'=', 1}, {identifier, 1, b}, {';', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{vardef, 1, a,
		   {fun_type, 1,
		    [{basic_type, 1, 0, integer, u8},
		     {basic_type, 1, 1, integer, u8}],
		    {basic_type, 1, 1, integer, u16}},
		   {varref, 1, b}}]),
    ok.

function_call_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("b: u8 = a::b(13);"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{identifier, 1, b}, {':', 1}, {integer_type, 1, u8},
		  {'=', 1}, {identifier, 1, a}, {'::', 1},
		  {identifier, 1, b}, {'(', 1}, {integer, 1, 13},
		  {')', 1}, {';', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{vardef, 1, b, {basic_type, 1, 0, integer, u8},
		   {call, 1,
		    {op2, 1, '::', {varref, 1, a}, {varref, 1, b}},
		    [{integer, 1, 13}]}}]),
    ok.

array_test() ->
    {ok, Tks, _} = ecompiler_scan:string("a: {u8, 100};"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{identifier, 1, a}, {':', 1}, {'{', 1},
		  {integer_type, 1, u8}, {',', 1}, {integer, 1, 100},
		  {'}', 1}, {';', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{vardef, 1, a,
		   {array_type, 1, {basic_type, 1, 0, integer, u8},
		    {integer, 1, 100}},
		   none}]),
    ok.

array_init_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("a: {u8, 2} = {11, 22};"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{identifier, 1, a}, {':', 1}, {'{', 1},
		  {integer_type, 1, u8}, {',', 1}, {integer, 1, 2},
		  {'}', 1}, {'=', 1}, {'{', 1}, {integer, 1, 11},
		  {',', 1}, {integer, 1, 22}, {'}', 1}, {';', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{vardef, 1, a,
		   {array_type, 1, {basic_type, 1, 0, integer, u8},
		    {integer, 1, 2}},
		   {array_init, 1,
		    [{integer, 1, 11}, {integer, 1, 22}]}}]),
    ok.

struct_init_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("a: S = S{name=\"a\", val=2};"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{identifier, 1, a}, {':', 1}, {identifier, 1, 'S'},
		  {'=', 1}, {identifier, 1, 'S'}, {'{', 1},
		  {identifier, 1, name}, {'=', 1}, {string, 1, "a"},
		  {',', 1}, {identifier, 1, val}, {'=', 1},
		  {integer, 1, 2}, {'}', 1}, {';', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{vardef, 1, a, {basic_type, 1, 0, struct, 'S'},
		   {struct_init_raw, 1, 'S',
		    [{op2, 1, assign, {varref, 1, name}, {string, 1, "a"}},
		     {op2, 1, assign, {varref, 1, val},
		      {integer, 1, 2}}]}}]),
    ok.

assign_test() ->
    {ok, Tks, _} =
	ecompiler_scan:string("fun b() a * = 3;c bsr = 5;end"),
    %?debugFmt("~p~n", [Tks]),
    ?assertEqual(Tks,
		 [{'fun', 1}, {identifier, 1, b}, {'(', 1}, {')', 1},
		  {identifier, 1, a}, {'*', 1}, {'=', 1}, {integer, 1, 3},
		  {';', 1}, {identifier, 1, c}, {'bsr', 1}, {'=', 1},
		  {integer, 1, 5}, {';', 1}, {'end', 1}]),
    {ok, Ast} = ecompiler_parse:parse(Tks),
    %?debugFmt("~p~n", [Ast]),
    ?assertEqual(Ast,
		 [{function_raw, 1, b, [],
		   {basic_type, 1, 0, void, void},
		   [{op2, 1, assign, {varref, 1, a},
		     {op2, 1, '*', {varref, 1, a}, {integer, 1, 3}}},
		    {op2, 1, assign, {varref, 1, c},
		     {op2, 1, 'bsr', {varref, 1, c}, {integer, 1, 5}}}]}]),
    ok.

-endif.
