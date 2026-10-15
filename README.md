# z80sh — a PL/M-80 compiler

z80sh is a non-interactive compiler for the PL/M-80 language:
it reads PL/M-80 source and emits assembly. The goal is the
full PL/M-80 language as summarized in the PL/M-80 Language
Summary (the `doc_cpm_plm` reference): every construct below
is either supported today or explicitly planned, and nothing
outside the language (no C-like spellings) is accepted.

## Usage

`z80sh` reads PL/M-80 from standard input, or from the file
named on the command line, and writes assembly to standard
output:

    z80sh [-o address] [-h] [file.plm]

By default the output is plain code: it begins at address 0
and ends with `halt`. Two target-specific pieces are opt-in:

- `-o address` emits the startup at that address: interrupt
  vectors, the boot stub that clears RAM, silences the sound
  chip and enters the program at `start`. The address is a
  PL/M constant (`0`, `8000H`, `32768`) or a `0x` hexadecimal
  word (`0x2000`).
- `-h` emits the Sega cartridge header (`TMR SEGA`) at
  `0x7FF0` after the code.

Either flag may be given alone; together they produce a
complete cartridge image.

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
  or a `PROCEDURE` body spans lines, or the line ends in
  `label:`; keep `ELSE` on the same line as its `IF` or
  wrap the statement in a `DO` group. A final line without
  a trailing newline still compiles.

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

- `BYTE`: 8-bit values, returned in `A`. Supported.
- `ADDRESS`: 16-bit values, returned in `HL` and stored
  as two bytes; an expression is 16-bit when either
  operand is, after the PL/M-80 promotion rules.
  Supported, with 16-bit `+ - OR XOR AND` and
  comparisons.
- Arrays of either type, with subscripts from 0:
  supported; an `ADDRESS` array indexes two bytes per
  element.
- `BASED` variables: `DECLARE v BASED p BYTE;` names the
  object at the address held by the `ADDRESS` scalar `p`,
  with no storage of its own. The base must be a plain,
  already declared `ADDRESS` scalar. Supported; pointer
  dereference may also be spelled `*p`.

## Constants

- Numeric constants with radix suffixes: `B` binary, `O`/`Q`
  octal, `D` decimal (also the default), `H` hexadecimal.
  Hexadecimal constants must start with a digit (`0FFH`).
  Supported; values must fit 16 bits.
- Character strings in apostrophes (`'A'`, doubled internal
  quotes). Length 1 is a `BYTE`, length 2 an `ADDRESS`.
  Supported, including longer strings in `DATA` and
  `INITIAL` lists.

## Expressions

Precedence, highest first:

    .                          (dot: address-of; planned)
    *  /  MOD
    +  -  PLUS  MINUS
    <  <=  =  >=  >  <>
    NOT
    AND
    OR  XOR

- Arithmetic (`+ - * / MOD PLUS MINUS`): `+` and `-` are
  supported at 16 bits, promoting to `ADDRESS` when either
  operand is. `*`, `/` and `MOD` stay 8-bit unless an
  operand is `ADDRESS`, and carry semantics for
  `PLUS`/`MINUS` are planned.
- Boolean (`NOT AND OR XOR`): supported, at 16 bits with
  `ADDRESS` operands.
- Relational (`< <= = >= > <>`): supported at both widths.
  Full PL/M returns `0FFH` for true and `00H` for false; the
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
- `DO variable = e1 TO e2 [BY e3]; ... END;`: supported for
  an already-declared `BYTE` or `ADDRESS` variable, stepping
  by `e3` (default 1) while the variable is `<= e2`.
- `DO CASE expression; ... END;`: supported; runs the
  statement numbered from 0 by the selector value, and
  nothing when it is out of range.
- `IF expression THEN stmt;` and
  `IF expression THEN stmt; ELSE stmt;`: supported.
  `ELSE` binds to the nearest open `IF`.
- `GOTO label;` and `GO TO label;`: supported. A label is
  declared by `DECLARE label LABEL;` or implicitly by
  `label: statement;`; the statement may start on the next
  line, and forward references resolve in the assembler.
- `DISABLE;` / `ENABLE;` (interrupts off/on): supported.
- `HALT;`: supported.
- `CALL name;` and `CALL name(args);` invoke a void
  procedure. A typed procedure is called in an
  expression: `x = f(a, b);`. Both are supported.
- A program may be wrapped in a module,
  `name: DO; ...; END name;`, with the name after `END`
  optional; the wrapper may also be omitted, leaving the
  statements to compile on their own.

## Declarations

Supported today:

    DECLARE name BYTE;
    DECLARE name ADDRESS;
    DECLARE (a, b, ...) BYTE;      group form
    DECLARE name (size) BYTE;      arrays, subscripts 0..size-1
    DECLARE name BYTE INITIAL (v, ...);   preset bytes
    DECLARE name DATA (v, ...);    ROM-resident bytes
    DECLARE name BASED base BYTE;  at the base's address
    DECLARE name LITERALLY 'text'; source substitution
    DECLARE name LABEL;            a GOTO target

Array elements read and write with `A(i)` for any byte
index expression, nesting included; `ADDRESS` arrays index
two bytes per element. `LENGTH(A)` folds to the element
count and `LAST(A)` to the highest subscript. Sizes take
full PL/M numbers (`10`, `0AH`, `101B`, `1$0`); at most
255 elements, since subscripts are bytes. Bare array names
are rejected in expressions.

`INITIAL` writes ROM-resident values then copies them into
the variable at its declaration, so the storage is preset
at run time; `DATA` names ROM-resident bytes directly and
takes no writable storage. A `LITERALLY` macro substitutes
its text at parse time and declares no storage. A `LABEL`
declares a `GOTO` target and no storage. A `BASED` name
declares no storage either: it reads and writes the object
at the address held by its base, like `*base`. The base
must be a plain, already declared `ADDRESS` scalar, and the
group form (`DECLARE (v BASED p, ...) BYTE;`) applies the
base to each name.

## Procedures

Supported:

    name: PROCEDURE (args) type;
        DECLARE arg BYTE; ...;
        statement; ...;
    END name;

Parameters are `BYTE` or `ADDRESS`; they are declared at the
top of the body in header order, exactly as in PL/M-80. The
result is `BYTE` (left in `A`) or `ADDRESS` (left in `HL`); a
void procedure is invoked with `CALL` and a typed one in an
expression, again after PL/M-80. `RETURN;` and
`RETURN expression;` both work. The `name:` and `PROCEDURE`
may be split by a line break, the name after `END` may be
omitted (`END;`), and statements may follow the procedure's
`END` inside the same block, as PL/M-80 allows.

Calls follow the PL/M-80 convention: a single argument
arrives in `BC` (a `BYTE` in `C`); with two or more, the last
is in `DE` (`E` for a `BYTE`) and the one before it in `BC`
(`C` for a `BYTE`); earlier arguments travel on the stack,
deepest first. An argument is widened to fill an `ADDRESS`
parameter and an `ADDRESS` argument keeps only its low byte
for a `BYTE` parameter. Arguments evaluate left to right, and
procedures are non-recursive, since parameters live in
static storage.

An interrupt procedure is `name: PROCEDURE INTERRUPT n;`
(no parameters, no result type). Its body saves and restores
`hl`, `de`, `bc` and `af` and re-enables interrupts with
`ei` before returning. Supported.

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
| `CALL TIME(n)` | Supported: about 100us per unit; `TIME` is an untyped procedure, so it is valid only after `CALL` |
| `DEC(a + b)`, `DEC(a PLUS b)` | Supported: `daa` after the addition |
| `LENGTH(A)`, `LAST(A)` | Supported: folded element count, highest subscript |

## Predefined variables

`CARRY`, `ZERO`, `SIGN`, and `PARITY` are byte-valued predefined
variables that read a Z80 flag: the value is `0FFH` when the flag
is set and `00H` when it is clear, after the PL/M-80 true/false
convention.  A read tests the flag left by the preceding
instruction, so it sees the result of the most recent arithmetic
or compare.  They may not be assigned to or redeclared, and the
names are matched case-insensitively with `$` signs ignored.

`MEMORY` and `STACKPTR`: planned.

## Building and testing

Prerequisites: `gcc` and `z80asm`.

    gcc -c -Wall -Wdeclaration-after-statement *.m

Any warning is treated as a defect. Then link the objects
with the local `libobjc` (Boehm-GC build; heap memory is
never freed) and run the suite:

    bash tests/run.sh

The suite rebuilds the compiler and checks exit codes,
diagnostics, emitted assembly and final image bytes for
233 programs, including one rejection test per non-PL/M
spelling (`int`, `==`, `!=`, `!`, `&&`, `||`, `&`, `|`,
`^`, `%`, bare `WHILE`, `THEN`-less `IF`, `{`/`}`,
`//` comments).
