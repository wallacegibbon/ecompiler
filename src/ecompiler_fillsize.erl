-module(ecompiler_fillsize).

-export([fill_structinfo/2, expand_size/2]).

-import(ecompiler_utils, [names_of_varrefs/1, getvalues_bykeys/2,
			  primitive_size/1, is_primitive_type/1,
			  flat_format/2, fn_struct_map/1,
			  fillto_pointerwidth/2, fill_offset/2]).

-include("./ecompiler_frame.hrl").

%% ast functions
fill_structinfo(Ast, {_, PointerWidth} = Ctx) ->
    Ast1 = lists:map(fun(E) -> fill_structsize(E, Ctx) end, Ast),
    {_, StructMap1} = fn_struct_map(Ast1),
    Ctx1 = {StructMap1, PointerWidth},
    Ast2 = lists:map(fun(E) -> fill_structoffsets(E, Ctx1) end, Ast1),
    Ast2.

expand_size(Ast, {_StructMap, _PointerWidth} = Ctx) ->
    lists:map(fun(E) -> expand_size_fun(E, Ctx) end, Ast).

expand_size_fun(#function{exprs=Exprs} = F, Ctx) ->
    F#function{exprs=expand_size_inexprs(Exprs, Ctx)};
expand_size_fun(Any, _) ->
    Any.

expand_size_inexprs(Exprs, Ctx) ->
    lists:map(fun(E) -> expand_size_inexpr(E, Ctx) end, Exprs).

expand_size_inexpr(#if_expr{condition=Cond, then=Then, else=Else} = If, Ctx) ->
    If#if_expr{condition=expand_size_inexpr(Cond, Ctx),
	       then=expand_size_inexprs(Then, Ctx),
	       else=expand_size_inexprs(Else, Ctx)};
expand_size_inexpr(#while_expr{condition=Cond, exprs=Exprs} = While, Ctx) ->
    While#while_expr{condition=expand_size_inexpr(Cond, Ctx),
		     exprs=expand_size_inexprs(Exprs, Ctx)};
expand_size_inexpr(#sizeof{type=T, line=Line}, Ctx) ->
    try
	{integer, Line, sizeof(T, Ctx)}
    catch
	throw:I ->
	    throw({Line, I})
    end;
expand_size_inexpr(#call{fn=Callee, args=Args} = Fncall, Ctx) ->
    Fncall#call{fn=expand_size_inexpr(Callee, Ctx),
		args=expand_size_inexprs(Args, Ctx)};
expand_size_inexpr(#return{expr=Retexpr} = Return, Ctx) ->
    Return#return{expr=expand_size_inexpr(Retexpr, Ctx)};
expand_size_inexpr(#op2{op1=Op1, op2=Op2} = O, Ctx) ->
    O#op2{op1=expand_size_inexpr(Op1, Ctx), op2=expand_size_inexpr(Op2, Ctx)};
expand_size_inexpr(#op1{operand=Operand} = O, Ctx) ->
    O#op1{operand=expand_size_inexpr(Operand, Ctx)};
expand_size_inexpr(Any, _) ->
    Any.

%%
fill_structsize(#struct{name=_} = S, Ctx) ->
    S#struct{size=sizeof_struct(S, Ctx)};
fill_structsize(Any, _) ->
    Any.

fill_structoffsets(#struct{name=_} = S, Ctx) ->
    S#struct{field_offsets=offsetsof_struct(S, Ctx)};
fill_structoffsets(Any, _) ->
    Any.

offsetsof_struct(#struct{field_names=FieldNames, field_types=FieldTypes},
		 Ctx) ->
    FieldTypeList = getkvs_byrefs(FieldNames, FieldTypes),
    {_, OffsetMap} = sizeof_fields(FieldTypeList, 0, #{}, Ctx),
    OffsetMap.

sizeof_struct(#struct{size=Size}, _) when is_integer(Size) ->
    Size;
sizeof_struct(#struct{field_names=FieldNames, field_types=FieldTypes}, Ctx) ->
    FieldTypeList = getkvs_byrefs(FieldNames, FieldTypes),
    {Size, _} = sizeof_fields(FieldTypeList, 0, #{}, Ctx),
    Size.

getkvs_byrefs(RefList, Map) ->
    Keys = names_of_varrefs(RefList),
    Values = getvalues_bykeys(Keys, Map),
    lists:zip(Keys, Values).

%% this is the function that calculate size and offsets
sizeof_fields([{Fname, Ftype} | Rest], CurrentOffset, OffsetMap,
	      {_, PointerWidth} = Ctx) ->
    FieldSize = sizeof(Ftype, Ctx),
    if (CurrentOffset rem PointerWidth) =/= 0 ->
	   NextOffset = CurrentOffset + FieldSize,
	   if NextOffset div PointerWidth > CurrentOffset ->
		  NewOffset = fill_offset(CurrentOffset, PointerWidth),
		  sizeof_fields(Rest, NewOffset + FieldSize,
				OffsetMap#{Fname => NewOffset}, Ctx);
	      true ->
		  sizeof_fields(Rest, CurrentOffset + FieldSize,
				OffsetMap#{Fname => CurrentOffset}, Ctx)
	   end;
       true ->
	   sizeof_fields(Rest, CurrentOffset + FieldSize,
			 OffsetMap#{Fname => CurrentOffset}, Ctx)
    end;
sizeof_fields([], CurrentOffset, OffsetMap, _) ->
    {CurrentOffset, OffsetMap}.

%%
sizeof(#array_type{elemtype=T, len=Len}, {_, PointerWidth} = Ctx) ->
    ElemSize = sizeof(T, Ctx),
    if (ElemSize < PointerWidth) ->
	   if (PointerWidth rem ElemSize =:= 0) ->
		  ElemSize * Len;
	      true ->
		  PointerWidth * Len
	   end;
       true ->
	   fillto_pointerwidth(ElemSize, PointerWidth) * Len
    end;
sizeof(#basic_type{type={_, N}}, {_, PointerWidth}) when N > 0 ->
    PointerWidth;
sizeof(#basic_type{type={Sym, 0}}, {StructMap, _} = Ctx) ->
    case is_primitive_type(Sym) of
	false ->
	    case maps:find(Sym, StructMap) of
		{ok, S} ->
		    sizeof_struct(S, Ctx);
		error ->
		    throw(flat_format("~s is not found", [Sym]))
	    end;
	true ->
	    primitive_size(Sym)
    end;
sizeof(#fun_type{ret=_}, {_, PointerWidth}) ->
    PointerWidth;
sizeof(A, _) ->
    throw(flat_format("invalid type ~p on sizeof", [A])).
