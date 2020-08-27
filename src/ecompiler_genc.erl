-module(ecompiler_genc).

-export([generate_ccode/4]).

-import(ecompiler_utils, [exprsmap/2, is_primitive_type/1,
			  getvalues_bykeys/2]).

-include("./ecompiler_frame.hrl").

generate_ccode(Ast, GlobalVars, _InitCode, OutputFile) ->
    {FnMap, StructMap} = ecompiler_compile:fn_struct_map(Ast),
    Ast2 = fixfunction_for_c(Ast, FnMap, StructMap, GlobalVars),
    %% struct definition have to be before function declarations
    {StructAst, FnAst} = lists:partition(fun(A) ->
						 element(1, A) =:= struct
					 end, Ast2),
    {StructStatements, []} = statements_tostr(StructAst),
    {FnStatements, FnDeclars} = statements_tostr(FnAst),
    VarStatements = mapvars_to_str(GlobalVars),
    Code = [common_code(), "\n\n", StructStatements, "\n\n",
	    VarStatements, "\n\n", FnDeclars, "\n\n", FnStatements],
    file:write_file(OutputFile, Code).

fixfunction_for_c([#function{exprs=Exprs, var_types=VarTypes} = F | Rest],
		   FnMap, StructMap, GlobalVars) ->
    CurrentVars = maps:merge(GlobalVars, VarTypes),
    Ctx = {CurrentVars, FnMap, StructMap},
    [F#function{exprs=fixexprs_for_c(Exprs, Ctx)} |
     fixfunction_for_c(Rest, FnMap, StructMap, GlobalVars)];
fixfunction_for_c([A | Rest], FnMap, StructMap, GlobalVars) ->
    [A | fixfunction_for_c(Rest, FnMap, StructMap, GlobalVars)];
fixfunction_for_c([], _, _, _) ->
    [].

fixexprs_for_c(Exprs, Ctx) ->
    exprsmap(fun(E) -> fixexpr_for_c(E, Ctx) end, Exprs).

fixexpr_for_c(#op1{operator='@', operand=Operand, line=Line} = E,
	      {VarTypes, FnMap, StructMap} = Ctx) ->
    case ecompiler_type:typeof_expr(Operand, {VarTypes, FnMap, StructMap,
					      none}) of
	#array_type{elemtype=_} ->
	    #op2{operator='.', op1=fixexpr_for_c(Operand, Ctx),
		 op2=#varref{name=val, line=Line}};
	_ ->
	    E
    end;
fixexpr_for_c(#op1{operand=Operand} = E, Ctx) ->
    E#op1{operand=fixexpr_for_c(Operand, Ctx)};
fixexpr_for_c(#op2{op1=Op1, op2=Op2} = E, Ctx) ->
    E#op2{op1=fixexpr_for_c(Op1, Ctx), op2=fixexpr_for_c(Op2, Ctx)};
fixexpr_for_c(Any, _) ->
    Any.

common_code() ->
    "#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n\n"
    "typedef unsigned char u8;\ntypedef char i8;\n"
    "typedef unsigned short u16;\ntypedef short i16;\n"
    "typedef unsigned int u32;\ntypedef int i32;\n"
    "typedef unsigned long u64;\ntypedef long i64;\n"
    "typedef double f64;\ntypedef float f32;\n\n".

statements_tostr(Statements) ->
    statements_tostr(Statements, [], []).

statements_tostr([#function{name=Name, param_names=ParamNames, type=Fntype,
			    var_types=VarTypes, exprs=Exprs} | Rest],
		 StatementStrs, FnDeclars) ->
    ParamNameAtoms = get_names(ParamNames),
    PureParams = kvlist_frommap(ParamNameAtoms,
				maps:with(ParamNameAtoms, VarTypes)),
    PureVars = maps:without(ParamNameAtoms, VarTypes),
    Declar = fn_declar_str(Name, PureParams, Fntype#fun_type.ret),
    S = io_lib:format("~s~n{~n~s~n~n~s~n}~n~n",
		      [Declar, mapvars_to_str(PureVars), exprs_tostr(Exprs)]),
    statements_tostr(Rest, [S | StatementStrs],
		     [Declar ++ ";\n" | FnDeclars]);
statements_tostr([#struct{name=Name, field_types=FieldTypes,
			  field_names=FieldNames} | Rest],
		 StatementStrs, FnDeclars) ->
    FieldList = kvlist_frommap(get_names(FieldNames), FieldTypes),
    S = io_lib:format("struct ~s {~n~s~n};~n~n",
		      [Name, listvars_to_str(FieldList)]),
    statements_tostr(Rest, [S | StatementStrs], FnDeclars);
statements_tostr([], StatementStrs, FnDeclars) ->
    {lists:reverse(StatementStrs), lists:reverse(FnDeclars)}.

fn_declar_str(Name, Params, Rettype) ->
    ParamStr = params_to_str(Params),
    case Rettype of
	#basic_type{type={_, N}} when N > 0 ->
	    fnret_type_tostr(Rettype,
			     io_lib:format("(*~s(~s))", [Name, ParamStr]));
	#fun_type{line=_} ->
	    fnret_type_tostr(Rettype,
			     io_lib:format("(*~s(~s))", [Name, ParamStr]));
	_ ->
	    type_tostr(Rettype,
		       io_lib:format("~s(~s)", [Name, ParamStr]))
    end.

params_to_str(NameTypePairs) ->
    lists:join(",", lists:map(fun({N, T}) -> type_tostr(T, N) end,
			      NameTypePairs)).

params_to_str_noname(Types) ->
    lists:join(",", lists:map(fun(T) -> type_tostr(T, "") end, Types)).

%% order is not necessary for vars
mapvars_to_str(VarsMap) when is_map(VarsMap) ->
    lists:flatten(lists:join(";\n", vars_to_str(maps:to_list(VarsMap), [])),
		  ";").

listvars_to_str(VarList) when is_list(VarList) ->
    lists:flatten(lists:join(";\n", vars_to_str(VarList, [])), ";").

vars_to_str([{Name, Type} | Rest], Strs) ->
    vars_to_str(Rest, [type_tostr(Type, Name) | Strs]);
vars_to_str([], Strs) ->
    lists:reverse(Strs).

get_names(VarrefList) ->
    lists:map(fun(#varref{name=N}) -> N end, VarrefList).

kvlist_frommap(NameAtoms, ValueMap) ->
    lists:zip(NameAtoms, getvalues_bykeys(NameAtoms, ValueMap)).

fnret_type_tostr(#fun_type{params=Params, ret=Rettype}, NameParams) ->
    Paramstr = params_to_str_noname(Params),
    NewNameParams = io_lib:format("~s(~s)", [NameParams, Paramstr]),
    type_tostr(Rettype, NewNameParams);
fnret_type_tostr(#basic_type{type={Typeanno, N}} = T, NameParams)
  when N > 0 ->
    type_tostr(T#basic_type{type={Typeanno, N-1}}, NameParams).

%% convert type to C string
type_tostr(#array_type{size=Size, elemtype=ElementType}, Varname) ->
    io_lib:format("struct {~s val[~w];} ~s", [type_tostr(ElementType, ""),
					      Size, Varname]);
type_tostr(#basic_type{type={Typeanno, Depth}}, Varname) when Depth > 0 ->
    io_lib:format("~s~s ~s", [typeanno_tostr(Typeanno),
			      lists:duplicate(Depth, "*"), Varname]);
type_tostr(#basic_type{type={Typeanno, 0}}, Varname) ->
    io_lib:format("~s ~s", [typeanno_tostr(Typeanno), Varname]);
type_tostr(#fun_type{params=Params, ret=Rettype}, Varname) ->
    Paramstr = params_to_str_noname(Params),
    NameParams = io_lib:format("(*~s)(~s)", [Varname, Paramstr]),
    type_tostr(Rettype, NameParams).

typeanno_tostr(Name) when is_atom(Name) ->
    case is_primitive_type(Name) of
	false ->
	    io_lib:format("struct ~s", [Name]);
	true ->
	    atom_to_list(Name)
    end.

%% convert expression to C string
exprs_tostr(Exprs) ->
    [lists:join(";\n", exprs_tostr(Exprs, [])), ";"].

exprs_tostr([Expr | Rest], ExprList) ->
    exprs_tostr(Rest, [expr_tostr(Expr) | ExprList]);
exprs_tostr([], ExprList) ->
    lists:reverse(ExprList).

expr_tostr(#if_expr{condition=Condition, then=Then, else=Else}) ->
    io_lib:format("if (~s) {\n~s\n} else {\n~s}",
		  [expr_tostr(Condition), exprs_tostr(Then),
		   exprs_tostr(Else)]);
expr_tostr(#while_expr{condition=Condition, exprs=Exprs}) ->
    io_lib:format("while (~s) {\n~s\n}\n",
		  [expr_tostr(Condition), exprs_tostr(Exprs)]);
expr_tostr(#op2{operator='::', op1=#varref{name=c}, op2=Op2}) ->
    expr_tostr(Op2);
expr_tostr(#op2{operator=Operator, op1=Op1, op2=Op2}) ->
    io_lib:format("(~s ~s ~s)", [expr_tostr(Op1), translate_operator(Operator),
				 expr_tostr(Op2)]);
expr_tostr(#op1{operator=Operator, operand=Operand}) ->
    io_lib:format("(~s ~s)", [translate_operator(Operator),
			      expr_tostr(Operand)]);
expr_tostr(#call{fn=Fn, args=Args}) ->
    io_lib:format("~s(~s)", [expr_tostr(Fn),
			     lists:join(",", lists:map(fun expr_tostr/1,
						       Args))]);
expr_tostr(#return{expr=Expr}) ->
    io_lib:format("return ~s", [expr_tostr(Expr)]);
expr_tostr(#varref{name=Name}) ->
    io_lib:format("~s", [Name]);
expr_tostr({Any, _Line, Value}) when Any =:= integer; Any =:= float ->
    io_lib:format("~w", [Value]);
expr_tostr({Any, _Line, S}) when Any =:= string ->
    io_lib:format("\"~s\"", [handle_special_char_instr(S, special_chars())]).

special_chars() ->
    #{$\n => "\\n", $\r => "\\r", $\t => "\\t", $\f => "\\f", $\b => "\\b"}.

handle_special_char_instr([Char | Str], CharMap) ->
    C = case maps:find(Char, CharMap) of
	    {ok, MappedChar} ->
		MappedChar;
	    error ->
		Char
	end,
    [C | handle_special_char_instr(Str, CharMap)];
handle_special_char_instr([], _) ->
    [].

translate_operator('assign') -> "=";
translate_operator('rem') -> "%";
translate_operator('bxor') -> "^";
translate_operator('bsr') -> ">>";
translate_operator('bsl') -> "<<";
translate_operator('band') -> "&";
translate_operator('bor') -> "|";
translate_operator('and') -> "&&";
translate_operator('or') -> "||";
translate_operator('@') -> "&";
translate_operator('^') -> "*";
translate_operator(Any) -> Any.

