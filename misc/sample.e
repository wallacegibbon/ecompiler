%% vim: ft=erlang :

defbox user as
    id: u32 = 0,
    description: <i8, 10>.

% t: block<i8, 10>,   t@ --> i8^

-define(TOTOAL_USERCNT, 10).

main(Argc: i32, Argv: i8^^): i32 ->
    Users: <user, ?TOTOAL_USERCNT>,
    init_users(users@, users.len).

init_users(Users: user^, Size: u8): any ->
    init_users(Users, 0, Size).

init_users(Users: user^, Cnt: u8, Size: u8): any when Cnt < Size ->
    U: user = (Users + Cnt)^,
    U.id = Cnt,
    memcpy(U.description@, "hello"),
    init_users(Users, Cnt + 1);
init_users(Users: user^, Cnt: u8, Size: u8): any ->
    0.

