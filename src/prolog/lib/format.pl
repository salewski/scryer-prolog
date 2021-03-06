/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Written March 2020 by Markus Triska (triska@metalevel.at)
   Part of Scryer Prolog.

   This library provides the nonterminal format_//2 to describe
   formatted strings. format/2 is provided for impure output.

   Usage:
   ======

   phrase(format_(FormatString, Arguments), Ls)

   format_//2 describes a list of characters Ls that are formatted
   according to FormatString. FormatString is a string (i.e.,
   a list of characters) that specifies the layout of Ls.
   The characters in FormatString are used literally, except
   for the following tokens with special meaning:

     ~w    use the next available argument from Arguments here
     ~q    use the next argument here, formatted as by writeq/1
     ~a    use the next argument here, which must be an atom
     ~s    use the next argument here, which must be a string
     ~d    use the next argument here, which must be an integer
     ~f    use the next argument here, a floating point number
     ~Nf   where N is an integer: format the float argument
           using N digits after the decimal point
     ~Nd   like ~d, placing the last N digits after a decimal point;
           if N is 0 or omitted, no decimal point is used.
     ~ND   like ~Nd, separating digits to the left of the decimal point
           in groups of three, using the character "," (comma)
     ~|    place a tab stop at this position
     ~N|   where N is an integer: place a tab stop at text column N
     ~N+   where N is an integer: place a tab stop N characters
           after the previous tab stop (or start of line)
     ~t    distribute spaces evenly between the two closest tab stops
     ~`Ct  like ~t, use character C instead of spaces to fill the space
     ~n    newline
     ~Nn   N newlines
     ~i    ignore the next argument
     ~~    the literal ~

   Instead of ~N, you can write ~* to use the next argument from Arguments
   as the numeric argument.

   The predicate format/2 is like format_//2, except that it outputs
   the text on the terminal instead of describing it declaratively.

   If at all possible, format_//2 should be used, to stress pure parts
   that enable easy testing etc. If necessary, you can emit the list Ls
   with maplist(write, Ls).

   The entire library only works if the Prolog flag double_quotes
   is set to chars, the default value in Scryer Prolog. This should
   also stay that way, to encourage a sensible environment.

   Example:

   ?- phrase(format_("~s~n~`.t~w!~12|", ["hello",there]), Cs).
   %@    Cs = "hello\n......there!"
   %@ ;  false.

   I place this code in the public domain. Use it in any way you want.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(format, [format_//2,
                   format/2,
                   portray_clause/1
                  ]).

:- use_module(library(dcgs)).
:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(charsio)).

format_(Fs, Args) -->
        { must_be(list, Fs),
          must_be(list, Args),
          phrase(cells(Fs,Args,0,[]), Cells) },
        format_cells(Cells).

format_cells([]) --> [].
format_cells([Cell|Cells]) -->
        format_cell(Cell),
        format_cells(Cells).

format_cell(newline) --> "\n".
format_cell(cell(From,To,Es)) -->
        % distribute the space between the glue elements
        { phrase(elements_gluevars(Es, 0, Length), Vs),
          (   Vs = [] -> true
          ;   Space is To - From - Length,
              (   Space =< 0 -> maplist(=(0), Vs)
              ;   length(Vs, NumGlue),
                  Distr is Space // NumGlue,
                  Delta is Space - Distr*NumGlue,
                  (   Delta =:= 0 ->
                      maplist(=(Distr), Vs)
                  ;   BigGlue is Distr + Delta,
                      reverse(Vs, [BigGlue|Rest]),
                      maplist(=(Distr), Rest)
                  )
              )
          ) },
        format_elements(Es).

format_elements([]) --> [].
format_elements([E|Es]) -->
        format_element(E),
        format_elements(Es).

format_element(chars(Cs)) --> list(Cs).
format_element(glue(Fill,Num)) -->
        { length(Ls, Num),
          maplist(=(Fill), Ls) },
        list(Ls).

list([]) --> [].
list([L|Ls]) --> [L], list(Ls).

elements_gluevars([], N, N) --> [].
elements_gluevars([E|Es], N0, N) -->
        element_gluevar(E, N0, N1),
        elements_gluevars(Es, N1, N).

element_gluevar(chars(Cs), N0, N) -->
        { length(Cs, L),
          N is N0 + L }.
element_gluevar(glue(_,V), N, N) --> [V].

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Our key datastructure is a list of cells and newlines.
   A cell has the shape from_to(From,To,Elements), where
   From and To denote the positions of surrounding tab stops.

   Elements is a list of elements that occur in a cell,
   namely terms of the form chars(Cs) and glue(Char, Var).
   "glue" elements (TeX terminology) are evenly stretched
   to fill the remaining whitespace in the cell. For each
   glue element, the character Char is used for filling,
   and Var is a free variable that is used when the
   available space is distributed.

   newline is used if ~n occurs in a format string.
   It is is used because a newline character does not
   consume whitespace in the sense of format strings.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

cells([], Args, Tab, Es) -->
        (   { Args == [] } -> cell(Tab, Tab, Es)
        ;   { domain_error(no_remaining_arguments, Args) }
        ).
cells([~,~|Fs], Args, Tab, Es) --> !,
        cells(Fs, Args, Tab, [chars("~")|Es]).
cells([~,w|Fs], [Arg|Args], Tab, Es) --> !,
        { write_term_to_chars(Arg, [], Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es]).
cells([~,q|Fs], [Arg|Args], Tab, Es) --> !,
        { write_term_to_chars(Arg, [quoted(true)], Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es]).
cells([~,a|Fs], [Arg|Args], Tab, Es) --> !,
        { atom_chars(Arg, Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es]).
cells([~|Fs0], Args0, Tab, Es) -->
        { numeric_argument(Fs0, Num, [d|Fs], Args0, [Arg|Args]) },
        !,
        { number_chars(Arg, Cs0) },
        (   { Num =:= 0 } -> { Cs = Cs0 }
        ;   { length(Cs0, L),
              (   L =< Num ->
                  Delta is Num - L,
                  length(Zs, Delta),
                  maplist(=('0'), Zs),
                  phrase(("0.",list(Zs),list(Cs0)), Cs)
              ;   BeforeComma is L - Num,
                  length(Bs, BeforeComma),
                  append(Bs, Ds, Cs0),
                  phrase((list(Bs),".",list(Ds)), Cs)
              ) }
        ),
        cells(Fs, Args, Tab, [chars(Cs)|Es]).
cells([~|Fs0], Args0, Tab, Es) -->
        { numeric_argument(Fs0, Num, ['D'|Fs], Args0, [Arg|Args]) },
        !,
        { number_chars(Num, NCs),
          phrase(("~",list(NCs),"d"), FStr),
          phrase(format_(FStr, [Arg]), Cs0),
          phrase(upto_what(Bs0, .), Cs0, Ds),
          reverse(Bs0, Bs1),
          phrase(groups_of_three(Bs1), Bs2),
          reverse(Bs2, Bs),
          append(Bs, Ds, Cs) },
        cells(Fs, Args, Tab, [chars(Cs)|Es]).
cells([~,i|Fs], [_|Args], Tab, Es) --> !,
        cells(Fs, Args, Tab, Es).
cells([~,n|Fs], Args, Tab, Es) --> !,
        cell(Tab, Tab, Es),
        n_newlines(1),
        cells(Fs, Args, 0, []).
cells([~|Fs0], Args0, Tab, Es) -->
        { numeric_argument(Fs0, Num, [n|Fs], Args0, Args) },
        !,
        cell(Tab, Tab, Es),
        n_newlines(Num),
        cells(Fs, Args, 0, []).
cells([~,s|Fs], [Arg|Args], Tab, Es) --> !,
        cells(Fs, Args, Tab, [chars(Arg)|Es]).
cells([~,f|Fs], [Arg|Args], Tab, Es) --> !,
        { number_chars(Arg, Chars) },
        cells(Fs, Args, Tab, [chars(Chars)|Es]).
cells([~|Fs0], Args0, Tab, Es) -->
        { numeric_argument(Fs0, Num, [f|Fs], Args0, [Arg|Args]) },
        !,
        { number_chars(Arg, Cs0),
          phrase(upto_what(Bs, .), Cs0, Cs),
          (   Num =:= 0 -> Chars = Bs
          ;   (   Cs = ['.'|Rest] ->
                  length(Rest, L),
                  (   Num < L ->
                      length(Ds, Num),
                      append(Ds, _, Rest)
                  ;   Num =:= L ->
                      Ds = Rest
                  ;   Num > L,
                      Delta is Num - L,
                      % we should look into the float with
                      % greater accuracy here, and use the
                      % actual digits instead of 0.
                      length(Zs, Delta),
                      maplist(=('0'), Zs),
                      append(Rest, Zs, Ds)
                  )
              ;   length(Ds, Num),
                  maplist(=('0'), Ds)
              ),
              append(Bs, ['.'|Ds], Chars)
          ) },
        cells(Fs, Args, Tab, [chars(Chars)|Es]).
cells([~,'`',Char,t|Fs], Args, Tab, Es) --> !,
        cells(Fs, Args, Tab, [glue(Char,_)|Es]).
cells([~,t|Fs], Args, Tab, Es) --> !,
        cells(Fs, Args, Tab, [glue(' ',_)|Es]).
cells([~|Fs0], Args0, Tab, Es) -->
        { numeric_argument(Fs0, Num, ['|'|Fs], Args0, Args) },
        !,
        cell(Tab, Num, Es),
        cells(Fs, Args, Num, []).
cells([~|Fs0], Args0, Tab0, Es) -->
        { numeric_argument(Fs0, Num, [+|Fs], Args0, Args) },
        !,
        { Tab is Tab0 + Num },
        cell(Tab0, Tab, Es),
        cells(Fs, Args, Tab, []).
cells([~,C|_], _, _, _) -->
        { atom_chars(A, [~,C]),
          domain_error(format_string, A) }.
cells(Fs0, Args, Tab, Es) -->
        { phrase(upto_what(Fs1, ~), Fs0, Fs),
          Fs1 = [_|_] },
        cells(Fs, Args, Tab, [chars(Fs1)|Es]).

domain_error(Type, Term) :-
        throw(error(domain_error(Type, Term), _)).

n_newlines(0) --> !.
n_newlines(1) --> !, [newline].
n_newlines(N0) --> { N0 > 1, N is N0 - 1 }, [newline], n_newlines(N).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- phrase(upto_what(Cs, ~), "abc~test", Rest).
Cs = [a,b,c], Rest = [~,t,e,s,t].
?- phrase(upto_what(Cs, ~), "abc", Rest).
Cs = [a,b,c], Rest = [].
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

upto_what([], W), [W] --> [W], !.
upto_what([C|Cs], W) --> [C], !, upto_what(Cs, W).
upto_what([], _) --> [].

groups_of_three([A,B,C,D|Rs]) --> !, [A,B,C], ",", groups_of_three([D|Rs]).
groups_of_three(Ls) --> list(Ls).

cell(From, To, Es0) -->
        (   { Es0 == [] } -> []
        ;   { reverse(Es0, Es) },
            [cell(From,To,Es)]
        ).

%?- numeric_argument("2f", Num, ['f'|Fs], Args0, Args).

%?- numeric_argument("100b", Num, Rs, Args0, Args).

numeric_argument(Ds, Num, Rest, Args0, Args) :-
        (   Ds = [*|Rest] ->
            Args0 = [Num|Args]
        ;   numeric_argument_(Ds, [], Ns, Rest),
            foldl(pow10, Ns, 0-0, Num-_),
            Args0 = Args
        ).

numeric_argument_([D|Ds], Ns0, Ns, Rest) :-
        (   member(D, "0123456789") ->
            number_chars(N, [D]),
            numeric_argument_(Ds, [N|Ns0], Ns, Rest)
        ;   Ns = Ns0,
            Rest = [D|Ds]
        ).


pow10(D, N0-Pow0, N-Pow) :-
        N is N0 + D*10^Pow0,
        Pow is Pow0 + 1.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Impure I/O, implemented as a small wrapper over format_//2.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

format(Fs, Args) :-
        phrase(format_(Fs, Args), Cs),
        maplist(write, Cs).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- phrase(cells("hello", [], 0, []), Cs).

?- phrase(cells("hello~10|", [], 0, []), Cs).
?- phrase(cells("~ta~t~10|", [], 0, []), Cs).

?- phrase(format_("~`at~50|", []), Ls).

?- phrase(cells("~`at~50|", [], 0, []), Cs),
   phrase(format_cells(Cs), Ls).
?- phrase(cells("~ta~t~tb~tc~21|", [], 0, []), Cs).
Cs = [cell(0,21,[glue(' ',_38),chars([a]),glue(' ',_62),glue(' ',_67),chars([b]),glue(' ',_91),chars([c])])].
?- phrase(cells("~ta~t~4|", [], 0, []), Cs).
Cs = [cell(0,4,[glue(' ',_38),chars([a]),glue(' ',_62)])].

?- phrase(format_cell(cell(0,1,[glue(a,_94)])), Ls).

?- phrase(format_cell(cell(0,50,[chars("hello")])), Ls).

?- phrase(format_("~`at~50|~n", []), Ls).
?- phrase(format_("hello~n~tthere~6|", []), Ls).

?- format("~ta~t~4|", []).
 a     true
;  false.

?- format("~ta~tb~tc~10|", []).
  a  b   c   true
;  false.

?- format("~tabc~3|", []).

?- format("~ta~t~4|", []).

?- format("~ta~t~tb~tc~20|", []).
    a        b     c   true
;  false.

?- format("~2f~n", [3]).
3.00
   true

?- format("~20f", [0.1]).
0.10000000000000000000   true % this should use higher accuracy!
;  false.

?- X is atan(2), format("~7f~n", [X]).
1.1071487
   X = 1.1071487177940906

?- format("~`at~50|~n", []).
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
   true

?- format("~t~N", []).

?- format("~q", [.]).
'.'   true
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   We also provide a rudimentary version of portray_clause/1.

   In the eventual library organization, portray_clause/1
   and related predicates (such as listing/1) may be placed
   in their own dedicated library.

   portray_clause/1 is useful for printing solutions in such a way
   that they can be read back with read/1.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

portray_clause(Term) :-
        phrase(portray_clause_(Term), Ls),
        maplist(write, Ls).

portray_clause_(Term) -->
        { term_variables(Term, Vs),
          foldl(var_name, Vs, VNs, 0, _) },
        portray_(Term, VNs), ".\n".

var_name(V, Name=V, Num0, Num) :-
        charsio:fabricate_var_name(numbervars, Name, Num0),
        Num is Num0 + 1.

literal(Lit, VNs) -->
        { write_term_to_chars(Lit, [quoted(true),variable_names(VNs)], Ls) },
        list(Ls).

portray_(Var, VNs) --> { var(Var) }, !, literal(Var, VNs).
portray_((Head :- Body), VNs) --> !,
        literal(Head, VNs), " :-\n",
        body_(Body, 0, 3, VNs).
portray_((Head --> Body), VNs) --> !,
        literal(Head, VNs), " -->\n",
        body_(Body, 0, 3, VNs).
portray_(Any, VNs) --> literal(Any, VNs).


body_(Var, C, I, VNs) --> { var(Var) }, !,
        indent_to(C, I),
        literal(Var, VNs).
body_((A,B), C, I, VNs) --> !,
        body_(A, C, I, VNs), ",\n",
        body_(B, 0, I, VNs).
body_((A ; Else), C, I, VNs) --> % ( If -> Then ; Else )
        { nonvar(A), A = (If -> Then) },
        !,
        indent_to(C, I),
        "(  ",
        { C1 is I + 3 },
        body_(If, C1, C1, VNs), " ->\n",
        body_(Then, 0, C1, VNs), "\n",
        else_branch(Else, C1, I, VNs).
body_((A;B), C, I, VNs) --> !,
        indent_to(C, I),
        "(  ",
        { C1 is I + 3 },
        body_(A, C1, C1, VNs), "\n",
        else_branch(B, C1, I, VNs).
body_(Goal, C, I, VNs) -->
        indent_to(C, I), literal(Goal, VNs).


else_branch(Else, C, I, VNs) -->
        indent_to(0, I),
        ";  ",
        body_(Else, C, C, VNs), "\n",
        indent_to(0, I),
        ")".

indent_to(CurrentColumn, Indent) -->
        { Delta is Indent - CurrentColumn },
        format_("~t~*|", [Delta]).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
?- portray_clause(a).
a.

?- portray_clause((a :- b)).
a :-
   b.

?- portray_clause((a :- b, c, d)).
a :-
   b,
   c,
   d.
   true


?- portray_clause([a,b,c,d]).
"abcd".

?- portray_clause(X).
?- portray_clause((f(X) :- X)).

?- portray_clause((h :- ( a -> b; c))).

?- portray_clause((h :- ( (a -> x ; y) -> b; c))).

?- portray_clause((h(X) :- ( (a(X) ; y(A,B)) -> b; c))).

?- portray_clause((h :- (a,d;b,c) ; (b,e;d))).

?- portray_clause((a :- b ; c ; d)).

?- portray_clause((h :- L = '.')).

?- portray_clause(-->(a, (b, {t}, d))).

?- portray_clause((A :- B)).

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */
