%%% this module operates on raw ast with function_raw, struct_raw.
-module(ecompiler_fillconst).

-export([parse_and_remove_const/1]).

-import(ecompiler_utils, [exprsmap/2, flat_format/2]).

-include("./ecompiler_frame.hrl").

%% find all consts in AST, calculate it and replace all const references.
parse_and_remove_const(Ast) ->
    {Constants, NewAst} = fetch_constants(Ast),
    replace_constants(NewAst, Constants).

%% fetch constants
fetch_constants(Ast) -> fetch_constants(Ast, [], #{}).

fetch_constants([#const{name=Name, val=Expr} | Rest], Statements, Constants) ->
    fetch_constants(Rest, Statements,
		    Constants#{Name => eval_constexpr(Expr, Constants)});
fetch_constants([Any | Rest], Statements, Constants) ->
    fetch_constants(Rest, [Any | Statements], Constants);
fetch_constants([], Statements, Constants) ->
    {Constants, lists:reverse(Statements)}.

eval_constexpr(#op2{operator='+', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) + eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='-', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) - eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='*', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) * eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='/', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) / eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='rem', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) rem eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='band', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) band eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='bor', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) bor eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='bxor', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) bxor eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='bsr', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) bsr eval_constexpr(Op2, Constants);
eval_constexpr(#op2{operator='bsl', op1=Op1, op2=Op2}, Constants) ->
    eval_constexpr(Op1, Constants) bsl eval_constexpr(Op2, Constants);
eval_constexpr(#varref{name=Name, line=Line}, Constants) ->
    try maps:get(Name, Constants)
    catch
	error:{badkey, _} ->
	    throw({Line, flat_format("undefined constant ~s", [Name])})
    end;
eval_constexpr({ImmiType, _, Val}, _) when ImmiType =:= integer;
					   ImmiType =:= float ->
    Val;
eval_constexpr(Num, _) when is_integer(Num); is_float(Num) ->
    Num;
eval_constexpr({Any, Line, Val}, _) ->
    E = flat_format("invalid const expression: ~s, ~p", [Any, Val]),
    throw({Line, E}).

%% replace constants in AST
replace_constants([#function_raw{params=Params, exprs=Exprs} = Fn | Rest],
		  Constants) ->
    [Fn#function_raw{params=replace_inexprs(Params, Constants),
		     exprs=replace_inexprs(Exprs, Constants)} |
     replace_constants(Rest, Constants)];
replace_constants([#struct_raw{fields=Fields} = S | Rest], Constants) ->
    [S#struct_raw{fields=replace_inexprs(Fields, Constants)} |
     replace_constants(Rest, Constants)];
replace_constants([#vardef{initval=Initval} = V | Rest], Constants) ->
    [V#vardef{initval=replace_inexpr(Initval, Constants)} |
     replace_constants(Rest, Constants)];
replace_constants([], _) ->
    [].

replace_inexprs(Exprs, Constants) ->
    exprsmap(fun (E) -> replace_inexpr(E, Constants) end, Exprs).

replace_inexpr(#vardef{name=Name, initval=Initval, type=Type,
		       line=Line} = Expr, Constants) ->
    case maps:find(Name, Constants) of
	{ok, _} ->
	    throw({Line, flat_format("name ~s is conflict with const",
				     [Name])});
	error ->
	    Expr#vardef{initval=replace_inexpr(Initval, Constants),
			type=replace_intype(Type, Constants)}
    end;
replace_inexpr(#varref{name=Name, line=Line} = Expr, Constants) ->
    case maps:find(Name, Constants) of
	{ok, Val} ->
	    constnum_to_token(Val, Line);
	error ->
	    Expr
    end;
replace_inexpr({constref, Line, Name}, Constants) ->
    case maps:find(Name, Constants) of
	{ok, Val} ->
	    constnum_to_token(Val, Line);
	error ->
	    throw({Line, flat_format("const ~s is not found", [Name])})
    end;
replace_inexpr(#op2{op1=Op1, op2=Op2} = Expr, Constants) ->
    Expr#op2{op1=replace_inexpr(Op1, Constants),
	     op2=replace_inexpr(Op2, Constants)};
replace_inexpr(#op1{operand=Operand} = Expr, Constants) ->
    Expr#op1{operand=replace_inexpr(Operand, Constants)};
replace_inexpr(Any, _) ->
    Any.

constnum_to_token(Num, Line) when is_float(Num) ->
    #float{val=Num, line=Line};
constnum_to_token(Num, Line) when is_integer(Num) ->
    #integer{val=Num, line=Line}.

replace_intype(#box_type{elemtype=ElementType, size=Size} = T,
			 Constants) ->
    T#box_type{elemtype=replace_intype(ElementType, Constants),
	       size=eval_constexpr(replace_inexpr(Size, Constants),
				   Constants)};
replace_intype(Any, _) ->
    Any.

