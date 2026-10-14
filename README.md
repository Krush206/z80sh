# z80sh — a PL/M-80 compiler

z80sh is a non-interactive compiler for the PL/M-80 language:
it reads PL/M-80 source and emits assembly. The goal is the
full PL/M-80 language as summarized in the PL/M-80 Language
Summary (the `doc_cpm_plm` reference): every construct below
is either supported today or explicitly planned, and nothing
outside the language (no C-like spellings) is accepted.

## Source form

- A semicolon terminates every statement. Newlines separate
  input lines for the compiler driver but are otherwise
  equivalent to spaces.
- The language is case-insensitive: `DECLARE`, `Declare` and
  `declare` are the same word.
- `$` signs imbedded in identifiers and numbers are ignored:
  `LINE$COUNT` and `LINECOUNT` name one variable.
- Comments are `/* ... */` only.
- One input line compiles alone unless a `DO`/`END` group
  spans lines, so keep `ELSE` on the same line as its `IF`
  or wrap the statement in a `DO` group.

## Character set

Alphabetics `A`–`Z`, numerics `0`–`9`, and the specials
`$ = . / ( ) + - ' * , < > : ;` plus space. Anything else
is rejected.

## Identifiers

1 to 31 characters: a leading alphabetic, then alphabetics
or numerics, with `$` freely imbedded for readability.
Supported.

Reserved words (never usable as identifiers):

    ADDRESS  AND      BASED    BY       BYTE     CALL
    CASE     DATA     DECLARE  DISABLE  DO       ELSE
    ENABLE   END      EOF      GO       GOTO     HALT
    IF       INITIAL  INPUT    INTERRUPT LABEL   LITERALLY
    MINUS    MOD      NOT      OR       OUTPUT   PLUS
    PROCEDURE RETURN   THEN     TO       WHILE    XOR

The compiler reserves the words it implements today and
rejects the rest as undeclared rather than misreading them.

## Data types

- `BYTE`: 8-bit values. Supported.
- `ADDRESS`: 16-bit values. Supported for storage
  (`DECLARE x ADDRESS` reserves two bytes); 16-bit
  arithmetic is planned.
- Arrays of either type, with subscripts from 0: planned.
- `BASED` variables addressed through a pointer: planned.
  Until then, pointer dereference is spelled `*p`.

## Constants

- Numeric constants with radix suffixes: `B` binary, `O`/`Q`
  octal, `D` decimal (also the default), `H` hexadecimal.
  Hexadecimal constants must start with a digit (`0FFH`).
  Supported; values must fit 16 bits.
- Character strings in apostrophes (`'A'`, doubled internal
  quotes). Length 1 is a `BYTE`, length 2 an `ADDRESS`.
  Supported for length 1; longer strings are planned
  (they need the dot operator).

## Expressions

Precedence, highest first:

    .                          (dot: address-of; planned)
    *  /  MOD
    +  -  PLUS  MINUS
    <  <=  =  >=  >  <>
    NOT
    AND
    OR  XOR

- Arithmetic (`+ - * / MOD PLUS MINUS`): supported on byte
  values. `*` and `/` producing `ADDRESS`, and carry
  semantics for `PLUS`/`MINUS`, are planned.
- Boolean (`NOT AND OR XOR`): supported. Operands and
  results are bytes today; `ADDRESS` operands with
  zero-extension are planned.
- Relational (`< <= = >= > <>`): supported. Full PL/M
  returns `0FFH` for true and `00H` for false; the
  compiler currently returns 1 and 0, which `IF` and
  `DO WHILE` test the same way. The `0FFH` convention
  is planned.
- `NOT` binds below relations, so `NOT a = b` reads
  `NOT (a = b)`; like the old tight `NOT` it tests
  `x == 0`. Supported.
- The dot operator (`.variable`, `.(...)` array
  constructors): planned.

`=` compares inside conditions and expressions but assigns
at statement level, so `IF X = Y THEN ...` tests equality
while `X = Y;` stores. Imbedded assignment `(x := y)` is
supported anywhere an expression parses, including
conditions, call arguments and nested inside itself; a
bare `x := y;` statement parses too, as it is
unambiguous. The selector of `DO CASE` re-evaluates per
branch, so prefer a variable there.

## Statements

- Assignment: `variable = expression;`, including
  `OUTPUT(port) = expression;`. Supported.
- `DO; ... END;` grouping: supported.
- `DO WHILE expression; ... END;`: supported; the loop
  runs while the value is non-zero.
- `DO variable = e1 TO e2; ... END;`: supported for an
  already-declared byte variable, stepping by 1 while
  the variable is `<= e2`.
- `DO CASE expression; ... END;`: supported; runs the
  statement numbered from 0 by the selector value, and
  nothing when it is out of range.
- `IF expression THEN stmt;` and
  `IF expression THEN stmt; ELSE stmt;`: supported.
  `ELSE` binds to the nearest open `IF`.
- `GOTO`/`GO TO` with labels: planned.
- `DISABLE;` / `ENABLE;` (interrupts off/on): supported.
- `HALT;`: supported.
- `CALL name(args);` and procedure calls in expressions:
  planned, with procedures themselves.

## Declarations

Supported today:

    DECLARE name BYTE;
    DECLARE name ADDRESS;
    DECLARE name (size) BYTE;   arrays, subscripts 0..size-1

Array elements read and write with `A(i)` for any byte
index expression, nesting included. `LENGTH(A)` folds to
the element count and `LAST(A)` to the highest subscript.
Sizes take full PL/M numbers (`10`, `0AH`, `101B`, `1$0`);
at most 255 elements, since subscripts are bytes. Bare
array names are rejected in expressions, and `ADDRESS`
arrays stay an error until 16-bit values exist.

Planned, in this order:

    DECLARE (a, b, ...) BYTE;      group form
    ... INITIAL(v, ...);            preset values
    DECLARE name DATA (...);        storage constants
    DECLARE name LITERALLY '...';   source substitution
    DECLARE x LABEL;                labels
    DECLARE p ADDRESS, v BASED p BYTE;

## Procedures

Planned:

    name: PROCEDURE (args) type;
        statement; ...;
    END name;

with `RETURN;` / `RETURN expression;`, non-recursive calls,
and `INTERRUPT n` handlers for `n` in 0–7.

## Built-in procedures

| Name | Status |
|---|---|
| `INPUT(port)` | Supported: byte from an I/O port |
| `OUTPUT(port) = expr` | Supported: byte to an I/O port |
| `LOW(expr)` | Supported: low byte, the value itself |
| `HIGH(expr)` | Supported: high byte, always zero |
| `DOUBLE(expr)` | Supported: zero-extended value itself |
| `SHL(v, n)`, `SHR(v, n)` | Supported: shift by count, 0 keeps value |
| `ROL(v, n)`, `ROR(v, n)` | Supported: rotate by count |
| `SCL(v, n)`, `SCR(v, n)` | Supported: rotate through clear carry |
| `TIME(n)` | Supported: about 100us per unit |
| `DEC(a + b)`, `DEC(a PLUS b)` | Supported: `daa` after the addition |
| `LENGTH(A)`, `LAST(A)` | Supported: folded element count, highest subscript |

## Predefined variables

`CARRY ZERO SIGN PARITY MEMORY STACKPTR`: planned.

## Building and testing

Prerequisites: `gcc` and `z80asm`.

    gcc -c -Wall -Wdeclaration-after-statement *.m

Any warning is treated as a defect. Then link the objects
with the local `libobjc` (Boehm-GC build; heap memory is
never freed) and run the suite:

    bash tests/run.sh

The suite rebuilds the compiler and checks exit codes,
diagnostics, emitted assembly and final image bytes for
127 programs, including one rejection test per non-PL/M
spelling (`int`, `==`, `!=`, `!`, `&&`, `||`, `&`, `|`,
`^`, `%`, bare `WHILE`, `THEN`-less `IF`, `{`/`}`,
`//` comments).
