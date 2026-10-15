#!/usr/bin/env bash
# Tests for the z80sh PL/M-80 non-interactive compiler.
#
# Usage: bash tests/run.sh
# Exit status is 0 when every test passes, 1 otherwise.
#
# Each test feeds a source program on stdin, then checks the
# compiler exit code, stderr diagnostics, the emitted assembly
# on stdout, and (where asked) that z80asm assembles the output
# or that the final image has the right size and header bytes.
#
# The language is PL/M only: DECLARE, DO..END, IF..THEN,
# word operators, = and <>. C-like spellings (int, address
# statements, ==, !=, !, &&, ||, &, |, ^, %, braces, bare
# while/if, // comments) are rejected with a syntax error.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/z80sh-test-$$
mkdir -p "$TMP/obj" || exit 1
trap 'rm -rf "$TMP"' EXIT

CSH=$TMP/csh
PASS=0
FAIL=0

pass() {
	PASS=$((PASS + 1))
	echo "ok - $1"
}

fail() {
	FAIL=$((FAIL + 1))
	echo "FAIL - $1: $2"
}

# Build the compiler exactly as documented: no warnings allowed.
WARN=$(
	for f in lex.m misc.m parse.m sem.m sh.m; do
		gcc -c -Wall -Wdeclaration-after-statement \
			-o "$TMP/obj/${f%.m}.o" "$ROOT/$f" 2>&1
	done
)
if [ -n "$WARN" ]; then
	echo "BUILD WARNINGS (treated as failure):"
	echo "$WARN"
	exit 1
fi
if ! gcc -o "$CSH" "$TMP"/obj/*.o \
	-L/usr/local/GNUstep/Local/Library/Libraries -lobjc \
	-Wl,-rpath,/usr/local/GNUstep/Local/Library/Libraries 2>"$TMP/link.err"; then
	cat "$TMP/link.err"
	echo "LINK FAILED"
	exit 1
fi
echo "build clean, no warnings"

# t_ok <name> : stdin is the source; expects exit 0, empty
# stderr, and output that z80asm accepts.
t_ok() {
	name=$1
	cat > "$TMP/t.in"
	if ! timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"; then
		fail "$name" "exit=$? stderr=[$(cat "$TMP/t.err")]"
		return
	fi
	if [ -s "$TMP/t.err" ]; then
		fail "$name" "stderr not empty: [$(cat "$TMP/t.err")]"
		return
	fi
	if ! z80asm -o "$TMP/t.bin" "$TMP/t.asm" 2> "$TMP/t.asserr"; then
		fail "$name" "z80asm rejected output: [$(cat "$TMP/t.asserr")]"
		return
	fi
	pass "$name"
}

# t_grep <name> <pattern>... : like t_ok, plus every extended
# regexp pattern must match a line of the emitted assembly.
t_grep() {
	name=$1
	shift
	cat > "$TMP/t.in"
	if ! timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"; then
		fail "$name" "exit=$? stderr=[$(cat "$TMP/t.err")]"
		return
	fi
	if [ -s "$TMP/t.err" ]; then
		fail "$name" "stderr not empty: [$(cat "$TMP/t.err")]"
		return
	fi
	pat=
	for pat in "$@"; do
		if ! grep -Eq "$pat" "$TMP/t.asm"; then
			fail "$name" "assembly lacks /$pat/"
			return
		fi
	done
	if ! z80asm -o "$TMP/t.bin" "$TMP/t.asm" 2> "$TMP/t.asserr"; then
		fail "$name" "z80asm rejected output: [$(cat "$TMP/t.asserr")]"
		return
	fi
	pass "$name"
}

# t_nogrep <name> <pattern>... : like t_ok, plus no extended
# regexp pattern may match any line of the assembly.
t_nogrep() {
	name=$1
	shift
	cat > "$TMP/t.in"
	if ! timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"; then
		fail "$name" "exit=$? stderr=[$(cat "$TMP/t.err")]"
		return
	fi
	if [ -s "$TMP/t.err" ]; then
		fail "$name" "stderr not empty: [$(cat "$TMP/t.err")]"
		return
	fi
	for pat in "$@"; do
		if grep -Eq "$pat" "$TMP/t.asm"; then
			fail "$name" "assembly has /$pat/"
			return
		fi
	done
	if ! z80asm -o "$TMP/t.bin" "$TMP/t.asm" 2> "$TMP/t.asserr"; then
		fail "$name" "z80asm rejected output: [$(cat "$TMP/t.asserr")]"
		return
	fi
	pass "$name"
}

# t_order <name> <first> <second> : like t_ok, plus the
# first pattern must match on an earlier assembly line
# than the second (proves evaluation order).
t_order() {
	name=$1
	first=$2
	second=$3
	cat > "$TMP/t.in"
	if ! timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"; then
		fail "$name" "exit=$? stderr=[$(cat "$TMP/t.err")]"
		return
	fi
	if [ -s "$TMP/t.err" ]; then
		fail "$name" "stderr not empty: [$(cat "$TMP/t.err")]"
		return
	fi
	fl=$(grep -n -m1 -E "$first" "$TMP/t.asm" | cut -d: -f1)
	sl=$(grep -n -m1 -E "$second" "$TMP/t.asm" | cut -d: -f1)
	if [ -z "$fl" ] || [ -z "$sl" ]; then
		fail "$name" "missing /$first/ or /$second/"
		return
	fi
	if [ "$fl" -ge "$sl" ]; then
		fail "$name" "/$first/ (line $fl) not before /$second/ (line $sl)"
		return
	fi
	if ! z80asm -o "$TMP/t.bin" "$TMP/t.asm" 2> "$TMP/t.asserr"; then
		fail "$name" "z80asm rejected output: [$(cat "$TMP/t.asserr")]"
		return
	fi
	pass "$name"
}

# t_err <name> <exit> <stderr-pattern> : stdin is the source;
# expects the given exit code and matching stderr.
t_err() {
	name=$1
	want_exit=$2
	want_err=$3
	cat > "$TMP/t.in"
	timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"
	got_exit=$?
	if [ "$got_exit" != "$want_exit" ]; then
		fail "$name" "exit=$got_exit, want $want_exit"
		return
	fi
	if ! grep -Eq "$want_err" "$TMP/t.err"; then
		fail "$name" "stderr [$(cat "$TMP/t.err")] lacks /$want_err/"
		return
	fi
	pass "$name"
}

# t_rom <name> : stdin is the source; expects a full 32768-byte
# image with the TMR SEGA header at 0x7FF0.
t_rom() {
	name=$1
	cat > "$TMP/t.in"
	if ! timeout 5 "$CSH" < "$TMP/t.in" > "$TMP/t.asm" 2> "$TMP/t.err"; then
		fail "$name" "exit=$? stderr=[$(cat "$TMP/t.err")]"
		return
	fi
	if ! z80asm -o "$TMP/t.bin" "$TMP/t.asm" 2> "$TMP/t.asserr"; then
		fail "$name" "z80asm rejected output: [$(cat "$TMP/t.asserr")]"
		return
	fi
	size=$(wc -c < "$TMP/t.bin")
	if [ "$size" != "32768" ]; then
		fail "$name" "image is $size bytes, want 32768"
		return
	fi
	head=$(od -A n -t x1 -j 0x7ff0 -N 10 "$TMP/t.bin" | tr -d ' \n')
	if [ "$head" != "544d5220534547412020" ]; then
		fail "$name" "header bytes are [$head]"
		return
	fi
	pass "$name"
}

# --- declarations, arithmetic, scope -------------------------

t_ok decl-arith <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
DECLARE C BYTE
A = 2
B = 3
C = A + B * 4 - A / B MOD 3
EOF

t_ok decl-unspaced <<'EOF'
DECLARE X BYTE
X=5
DECLARE Y BYTE
Y=X*2+1
EOF

t_grep decl-char-literal "ld a, 65" <<'EOF'
DECLARE C BYTE
C = 'A'
EOF

t_ok decl-block-scope <<'EOF'
DECLARE X BYTE
X = 1
DO;
DECLARE X BYTE
DECLARE Y BYTE
Y = X
END;
DECLARE Z BYTE
Z = X
EOF

t_ok decl-address-deref <<'EOF'
DECLARE P ADDRESS
DECLARE V BYTE
DECLARE W BYTE
V = 65
*P = V
W = *P
EOF

t_ok decl-io <<'EOF'
DECLARE X BYTE
X = INPUT (220)
OUTPUT (191) = X
EOF

t_grep decl-io-upper "in a, \(c\)" "out \(c\), a" <<'EOF'
DECLARE X BYTE
X = INPUT (220)
OUTPUT (191) = X
EOF

t_err decl-redeclared 255 "redeclared" <<'EOF'
DECLARE X BYTE
DECLARE X BYTE
EOF

t_err decl-undeclared 255 "undeclared" <<'EOF'
DECLARE Y BYTE
Y = Z
EOF

# --- case-insensitivity and $ handling -----------------------

t_grep plm-uppercase "ld a, 5" "ld \(x\), a" <<'EOF'
DECLARE X BYTE
X = 5
IF X = 5 THEN OUTPUT (191) = X
EOF

t_grep plm-dollar-declare "linecount:.equ" <<'EOF'
DECLARE LINE$COUNT BYTE
LineCount = 5
LINE$COUNT = LINECOUNT + 1
EOF

t_err plm-dollar-dup 255 "redeclared" <<'EOF'
DECLARE A$B BYTE
DECLARE AB BYTE
EOF

t_err plm-case-dup 255 "redeclared" <<'EOF'
DECLARE X BYTE
DECLARE X BYTE
EOF

t_grep plm-number-dollar "ld a, 10$" <<'EOF'
DECLARE A BYTE
A = 1$0
EOF

t_grep plm-number-hex "ld a, 0FFH" "ld a, 101B" <<'EOF'
DECLARE H BYTE
H = 0FFH
DECLARE B BYTE
B = 101B
EOF

t_ok plm-star-comment <<'EOF'
/* greetings */
DECLARE X BYTE
X = 1 /* trailing */
EOF

# --- PL/M word operators and comparisons --------------------

t_ok plm-word-operators <<'EOF'
DECLARE A BYTE
DECLARE O BYTE
DECLARE X BYTE
DECLARE M BYTE
DECLARE P BYTE
DECLARE S BYTE
DECLARE N BYTE
A = 1 AND 0
O = 1 OR 0
X = 1 XOR 1
M = 7 MOD 3
P = 1 PLUS 2
S = 5 MINUS 2
N = NOT 0
EOF

t_grep plm-and-is-logical "or a" "jr z" <<'EOF'
DECLARE A BYTE
A = 1 AND 0
EOF

t_grep plm-or-is-logical "or a" "jr nz" <<'EOF'
DECLARE O BYTE
O = 1 OR 0
EOF

t_grep plm-not-compares "cp b" <<'EOF'
DECLARE N BYTE
N = NOT 0
EOF

t_grep plm-equals-compares "cp b" <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 5
Y = 5
IF X = Y THEN X = 1
EOF

t_grep plm-relational "cp b" <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 5
Y = 6
IF X < Y THEN X = 1
IF X <= Y THEN X = 2
IF X > Y THEN X = 3 ELSE X = 4
IF X >= Y THEN X = 5 ELSE X = 6
IF X <> Y THEN X = 7
EOF

t_grep plm-not-equals "jr nz" <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 5
Y = 6
IF (X <> Y) THEN X = 2
EOF

t_ok plm-not-binds-below-relations <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
A = 5
B = 6
IF NOT A = B THEN A = 1 ELSE A = 2
EOF

t_ok plm-not-above-and <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
A = 1
B = 0
IF NOT A AND B THEN A = 9
EOF

t_order plm-xor-levels-and-tighter "or a" "xor b" <<'EOF'
DECLARE R BYTE
R = 0 AND 1 XOR 1
EOF

t_ok plm-or-xor-left-assoc <<'EOF'
DECLARE R BYTE
R = 1 OR 0 XOR 0
EOF

t_ok plm-assign-imbedded <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = (Y := 5) + 1
EOF

t_grep plm-assign-imbedded-stores "ld \(y\), a" "ld \(x\), a" <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = (Y := 5) + 1
EOF

t_ok plm-assign-imbedded-nested <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = (Y := (X := 3))
EOF

t_ok plm-assign-imbedded-cond <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 0
Y = 0
IF (X := 1) THEN Y = 2
EOF

t_ok plm-assign-imbedded-deref <<'EOF'
DECLARE P ADDRESS
DECLARE V BYTE
P = 200
V = 1
OUTPUT (191) = (*P := V)
EOF

t_err plm-assign-imbedded-bad-lhs 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = (5 := 1)
EOF

t_err plm-assign-imbedded-no-rhs 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = (X := )
EOF

t_err plm-assign-imbedded-prefix 255 "undeclared" <<'EOF'
DECLARE X BYTE
X = 1
FOO (X := 2)
EOF

t_ok plm-assign-imbedded-nested <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = (Y := (X := 3))
EOF

t_ok plm-assign-imbedded-cond <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 0
Y = 0
IF (X := 1) THEN Y = 2
EOF

t_ok plm-assign-imbedded-call-arg <<'EOF'
DECLARE X BYTE
X = INPUT (X := 220)
EOF

t_ok plm-assign-imbedded-deref <<'EOF'
DECLARE P ADDRESS
DECLARE V BYTE
P = 200
V = 1
OUTPUT (191) = (*P := V)
EOF

t_err plm-assign-imbedded-undecl 255 "undeclared" <<'EOF'
DECLARE X BYTE
X = (Z := 5)
EOF

t_err plm-reserved-name 255 "syntax error" <<'EOF'
DECLARE AND BYTE
EOF

t_err plm-declare-bad-type 255 "syntax error" <<'EOF'
DECLARE X INT
EOF

t_err plm-declare-short 255 "syntax error" <<'EOF'
DECLARE X
EOF

# --- PL/M statements -----------------------------------------

t_ok plm-if-then-else <<'EOF'
DECLARE X BYTE
X = 1
IF X = 1 THEN X = 2 ELSE X = 3
IF (X = 2) THEN X = 4
EOF

t_ok plm-nested-if <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
X = 1
Y = 2
IF X = 1 THEN IF Y = 2 THEN X = 3 ELSE X = 4 ELSE X = 5
EOF

t_err plm-if-without-then 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
IF X = 1 X = 2
EOF

t_ok plm-do-block <<'EOF'
DECLARE X BYTE
X = 0
DO;
X = 1;
X = X + 1;
END;
EOF

t_ok plm-do-while <<'EOF'
DECLARE X BYTE
X = 3
DO WHILE X;
X = X - 1;
END;
EOF

t_grep plm-do-iterative "ld \(i\), a" "add a, b" "or a" <<'EOF'
DECLARE I BYTE
DECLARE X BYTE
X = 0
DO I = 1 TO 3;
X = X + I;
END;
EOF

t_ok plm-nested-do <<'EOF'
DECLARE X BYTE
X = 0
DO;
DO;
X = 1;
END;
IF X = 1 THEN X = 2;
END;
EOF

t_ok plm-do-case <<'EOF'
DECLARE X BYTE
X = 1
DO CASE X;
X = 10;
X = 20;
X = 30;
END;
EOF

t_grep plm-do-case-tests-each "cp b" <<'EOF'
DECLARE X BYTE
X = 1
DO CASE X;
X = 10;
X = 20;
X = 30;
END;
EOF

t_ok plm-do-case-out-of-range <<'EOF'
DECLARE X BYTE
X = 9
DO CASE X;
X = 10;
X = 20;
END;
EOF

t_ok plm-do-case-nested <<'EOF'
DECLARE I BYTE
DECLARE X BYTE
X = 0
DO I = 1 TO 2;
DO CASE I;
X = X + 10;
X = X + 20;
END;
END;
EOF

t_ok plm-do-case-group-branch <<'EOF'
DECLARE X BYTE
X = 0
DO CASE X;
DO;
X = 1;
END;
X = 2;
END;
EOF

t_ok plm-do-case-empty <<'EOF'
DECLARE X BYTE
X = 0
DO CASE X;
END;
EOF

t_err plm-do-case-nosemi 255 "syntax error" <<'EOF'
DECLARE X BYTE
DO CASE X
X = 1;
END;
EOF

t_err plm-do-unclosed 255 "syntax error" <<'EOF'
DO;
X = 1;
EOF

t_err plm-do-while-nosemi 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
DO WHILE X
X = 2;
END;
EOF

t_err plm-bare-end 255 "syntax error" <<'EOF'
END
EOF

t_err plm-bare-to 255 "syntax error" <<'EOF'
TO
EOF

t_grep plm-disable-enable-halt "di$" "ei$" "halt$" <<'EOF'
DISABLE;
ENABLE;
HALT;
EOF

# --- removed C-like spellings all fail -----------------------

t_err rm-int-decl 255 "syntax error" <<'EOF'
int x = 1
EOF

t_err rm-address-stmt 255 "syntax error" <<'EOF'
address p
EOF

t_err rm-eqeq 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
IF X == 1 THEN X = 2
EOF

t_err rm-noteq 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
IF X != 1 THEN X = 2
EOF

t_err rm-bang 255 "syntax error" <<'EOF'
DECLARE Y BYTE
Y = !0
EOF

t_err rm-andand 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
A = 1
B = A && 1
EOF

t_err rm-oror 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
A = 1
B = A || 1
EOF

t_err rm-bitand 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE B BYTE
A = 5
B = A & 3
EOF

t_err rm-bitor 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE O BYTE
A = 5
O = A | 3
EOF

t_err rm-caret 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE X BYTE
A = 5
X = A ^ 3
EOF

t_err rm-percent 255 "syntax error" <<'EOF'
DECLARE A BYTE
DECLARE M BYTE
A = 7
M = A % 3
EOF

t_err rm-c-while 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 3
WHILE (X) X = X - 1
EOF

t_err rm-c-if-paren 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
IF (X = 1) X = 2
EOF

t_err rm-braces 255 "syntax error" <<'EOF'
DECLARE X BYTE
{ X = 1; }
EOF

t_err rm-brace-block 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 0
{
X = 1;
}
EOF

t_err rm-line-comment 255 "syntax error" <<'EOF'
DECLARE X BYTE // comment
X = 1
EOF

# --- built-in procedures ---------------------------------

t_grep builtin-shl "sla a" <<'EOF'
DECLARE X BYTE
X = SHL(1, 3)
EOF

t_grep builtin-shr "sra a" <<'EOF'
DECLARE X BYTE
X = SHR(16, 2)
EOF

t_grep builtin-rol "rlca" <<'EOF'
DECLARE X BYTE
X = ROL(129, 1)
EOF

t_grep builtin-ror "rrca" <<'EOF'
DECLARE X BYTE
X = ROR(129, 1)
EOF

t_grep builtin-scl "rl c" <<'EOF'
DECLARE X BYTE
X = SCL(129, 1)
EOF

t_grep builtin-scr "rr c" <<'EOF'
DECLARE X BYTE
X = SCR(129, 1)
EOF

t_ok builtin-shift-var-count <<'EOF'
DECLARE X BYTE
DECLARE N BYTE
N = 2
X = SHL(X, N)
EOF

t_ok builtin-shift-nested <<'EOF'
DECLARE X BYTE
X = SHL(SHL(1, 1), 2)
EOF

t_ok builtin-shift-expr-args <<'EOF'
DECLARE X BYTE
X = SHL(1 + 2, 3 - 1)
EOF

t_ok builtin-time-expr <<'EOF'
TIME(5 + 5);
EOF

t_ok builtin-dec-nested-shift <<'EOF'
DECLARE X BYTE
X = DEC(SHL(1, 3) + 1)
EOF

t_grep builtin-low-side-effect "in a, \(c\)" <<'EOF'
DECLARE X BYTE
X = LOW(INPUT(220))
EOF

t_grep builtin-time "dec c" <<'EOF'
TIME(10);
EOF

t_grep builtin-dec "add a, b" "daa" <<'EOF'
DECLARE X BYTE
X = DEC(150 + 27)
EOF

t_ok builtin-dec-plus <<'EOF'
DECLARE X BYTE
X = DEC(150 PLUS 27)
EOF

t_ok builtin-low <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
Y = 7
X = LOW(Y)
EOF

t_grep builtin-high "ld a, 0" <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
Y = 7
X = HIGH(Y)
EOF

t_ok builtin-double <<'EOF'
DECLARE X BYTE
DECLARE Y BYTE
Y = 7
X = DOUBLE(Y)
EOF

t_err builtin-shl-one-arg 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = SHL(1)
EOF

t_err builtin-shl-three-args 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = SHL(1, 2, 3)
EOF

t_err builtin-shl-bare 255 "syntax error" <<'EOF'
SHL
EOF

t_err builtin-input-two-args 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = INPUT(1, 2)
EOF

t_err builtin-dec-no-plus 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = DEC(150)
EOF

t_err builtin-dec-minus 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = DEC(150 MINUS 27)
EOF

t_err builtin-dec-bare 255 "syntax error" <<'EOF'
DEC
EOF

t_err builtin-stray-comma 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1,
EOF

t_err array-length-scalar 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = LENGTH(X)
EOF

# --- full image ----------------------------------------------

# --- arrays ----------------------------------------------------

t_ok array-basic <<'EOF'
DECLARE A(4) BYTE
DECLARE X BYTE
A(0) = 10
A(3) = 40
X = A(0) + A(3)
EOF

t_grep array-ram-growth "equ 0xC004" "equ 0xC006" <<'EOF'
DECLARE A(4) BYTE
DECLARE B(2) BYTE
DECLARE X BYTE
X = A(0)
EOF

t_ok array-expr-index <<'EOF'
DECLARE A(8) BYTE
DECLARE I BYTE
DECLARE X BYTE
I = 2
A(I + 1) = 99
X = A(I * 2)
EOF

t_ok array-nested <<'EOF'
DECLARE A(4) BYTE
DECLARE B(4) BYTE
DECLARE X BYTE
B(1) = 2
A(B(1)) = 9
X = A(B(1))
EOF

t_grep array-length "ld a, 4" <<'EOF'
DECLARE A(4) BYTE
DECLARE X BYTE
X = LENGTH(A)
EOF

t_grep array-last "ld a, 3" <<'EOF'
DECLARE A(4) BYTE
DECLARE X BYTE
X = LAST(A)
EOF

t_grep array-hex-size "ld a, 10" <<'EOF'
DECLARE A(0AH) BYTE
DECLARE X BYTE
X = LENGTH(A)
EOF

t_grep array-bin-dollar-size "ld a, 10" <<'EOF'
DECLARE B(101B) BYTE
DECLARE C(1$0) BYTE
DECLARE X BYTE
X = LENGTH(B) + LENGTH(C)
EOF

t_ok array-scope <<'EOF'
DECLARE X BYTE
X = 1
DO;
DECLARE A(2) BYTE
A(0) = 5
END;
X = X + 1
EOF

t_ok array-scope-shadow <<'EOF'
DECLARE A(2) BYTE
A(0) = 1
DO;
DECLARE A BYTE
A = 2
END;
DECLARE X BYTE
X = A(1)
EOF

t_ok array-same-batch <<'EOF'
DECLARE A(4) BYTE; DECLARE X BYTE; X = A(0)
DECLARE Y BYTE; Y = LENGTH(A)
EOF

t_ok decl-group <<'EOF'
DECLARE (A, B, C) BYTE
A = 1
B = 2
C = A + B
EOF

t_ok decl-group-address <<'EOF'
DECLARE (P, Q) ADDRESS
P = 5
EOF

t_grep decl-group-ram "b:.equ 0xC001" "c:.equ 0xC002" <<'EOF'
DECLARE (A, B, C) BYTE
A = 1
EOF

t_err decl-group-empty 255 "syntax error" <<'EOF'
DECLARE () BYTE
EOF

t_err decl-group-trailing-comma 255 "syntax error" <<'EOF'
DECLARE (A,) BYTE
EOF

t_err decl-group-leading-comma 255 "syntax error" <<'EOF'
DECLARE (,A) BYTE
EOF

t_err decl-group-double-comma 255 "syntax error" <<'EOF'
DECLARE (A,,B) BYTE
EOF

t_err decl-group-keyword 255 "syntax error" <<'EOF'
DECLARE (A, IF) BYTE
EOF

t_err decl-group-badname 255 "syntax error" <<'EOF'
DECLARE (5A) BYTE
EOF

t_err decl-group-paren-item 255 "syntax error" <<'EOF'
DECLARE (A(2)) BYTE
EOF

t_err decl-group-no-type 255 "syntax error" <<'EOF'
DECLARE (A, B)
EOF

t_err decl-group-bad-type 255 "syntax error" <<'EOF'
DECLARE (A) INT
EOF

t_err decl-group-redecl 255 "redeclared" <<'EOF'
DECLARE A BYTE
DECLARE (A, B) BYTE
EOF

t_err decl-group-redecl-inner 255 "redeclared" <<'EOF'
DECLARE (A, A) BYTE
EOF

t_err decl-group-too-many 255 "syntax error" <<'EOF'
DECLARE (A) BYTE EXTRA
EOF

t_err decl-group-unclosed 255 "syntax error" <<'EOF'
DECLARE (A, B BYTE
EOF

t_ok do-array-last-batch <<'EOF'
DO;
DECLARE A(2) BYTE
END;
EOF

t_ok do-array-use-last-batch <<'EOF'
DO;
DECLARE A(2) BYTE
A(0) = 5
END;
EOF

t_ok do-group-last-batch <<'EOF'
DO;
DECLARE (A, B) BYTE
A = 1
END;
EOF

t_ok do-array-sameline-last <<'EOF'
DO; DECLARE A(2) BYTE; A(0) = 5; END;
EOF

t_err array-scalar-sub 255 "syntax error" <<'EOF'
DECLARE X BYTE
X = 1
DECLARE Y BYTE
Y = X(0)
EOF

t_err array-undecl-sub 255 "undeclared" <<'EOF'
DECLARE Y BYTE
Y = Z(0)
EOF

t_grep array-address "ld \(p\), hl" "add hl, de" <<'EOF'
DECLARE P ADDRESS
DECLARE A(4) ADDRESS
P = 1000
A(0) = P + P
EOF

t_err array-size-zero 255 "syntax error" <<'EOF'
DECLARE A(0) BYTE
EOF

t_err array-size-bad 255 "syntax error" <<'EOF'
DECLARE A(X) BYTE
EOF

t_err array-size-multi 255 "syntax error" <<'EOF'
DECLARE A(1 2) BYTE
EOF

t_err array-bare-read 255 "syntax error" <<'EOF'
DECLARE A(4) BYTE
DECLARE X BYTE
X = A
EOF

t_err array-bare-assign 255 "syntax error" <<'EOF'
DECLARE A(4) BYTE
A = 5
EOF

t_err array-length-undecl 255 "undeclared" <<'EOF'
DECLARE X BYTE
X = LENGTH(Z)
EOF

t_err array-too-big 255 ": too large" <<'EOF'
DECLARE A(256) BYTE
EOF

t_rom plm-full-image <<'EOF'
DECLARE I BYTE
DECLARE X BYTE
X = 0
DO I = 1 TO 10;
X = X + I;
END;
IF X = 55 THEN OUTPUT (191) = X ELSE OUTPUT (191) = 0
DISABLE;
ENABLE;
HALT;
EOF

# --- procedures, parameters and calls -----------------------

t_ok proc-void-call <<'EOF'
STORE: PROCEDURE;
RETURN;
END STORE;
CALL STORE;
EOF

t_grep proc-entry-and-call "Q_addu:" "ld \(hl\), e" "ld \(hl\), c" \
	"call Q_addu" <<'EOF'
ADDU: PROCEDURE(A, B) BYTE;
DECLARE A BYTE, B BYTE;
RETURN A - B;
END ADDU;
DECLARE X BYTE;
X = ADDU(10, 3);
EOF

t_grep proc-three-params "Q_sub3:" "pop af" "ld c, a" "ld e, a" <<'EOF'
SUB3: PROCEDURE(P, Q, R) BYTE;
DECLARE P BYTE, Q BYTE, R BYTE;
RETURN P - Q - R;
END SUB3;
DECLARE X BYTE;
X = SUB3(1, 2, 3);
EOF

t_order proc-args-left-to-right "ld a, 1" "ld a, 2" <<'EOF'
SUB3: PROCEDURE(P, Q, R) BYTE;
DECLARE P BYTE, Q BYTE, R BYTE;
RETURN P;
END SUB3;
DECLARE X BYTE;
X = SUB3(1, 2, 3);
EOF

t_ok proc-address-return <<'EOF'
ADDR: PROCEDURE(A) ADDRESS;
DECLARE A BYTE;
RETURN A;
END ADDR;
DECLARE X ADDRESS;
X = ADDR(5);
EOF

t_ok proc-nested-calls <<'EOF'
F: PROCEDURE(A) BYTE;
DECLARE A BYTE;
RETURN A + 1;
END F;
G: PROCEDURE(A) BYTE;
DECLARE A BYTE;
RETURN A + 2;
END G;
H: PROCEDURE(A, B) BYTE;
DECLARE A BYTE, B BYTE;
RETURN A + B;
END H;
DECLARE X BYTE;
X = H(F(1), G(2));
EOF

t_err proc-arity-low 255 "syntax error" <<'EOF'
ADDU: PROCEDURE(A, B) BYTE;
DECLARE A BYTE, B BYTE;
RETURN A;
END ADDU;
DECLARE X BYTE;
X = ADDU(1);
EOF

t_err proc-arity-high 255 "syntax error" <<'EOF'
ADDU: PROCEDURE(A) BYTE;
DECLARE A BYTE;
RETURN A;
END ADDU;
DECLARE X BYTE;
X = ADDU(1, 2);
EOF

t_err proc-void-in-expr 255 "syntax error" <<'EOF'
V: PROCEDURE;
RETURN;
END V;
DECLARE X BYTE;
X = V();
EOF

t_err proc-call-typed 255 "syntax error" <<'EOF'
ADDU: PROCEDURE(A) BYTE;
DECLARE A BYTE;
RETURN A;
END ADDU;
CALL ADDU(1);
EOF

t_err proc-param-undeclared 255 "syntax error" <<'EOF'
ADDU: PROCEDURE(A) BYTE;
RETURN A;
END ADDU;
EOF

t_err proc-param-order 255 "syntax error" <<'EOF'
ADDU: PROCEDURE(A, B) BYTE;
DECLARE B BYTE, A BYTE;
RETURN A;
END ADDU;
EOF

t_err proc-reserved-name 255 "syntax error" <<'EOF'
DOUBLE: PROCEDURE;
RETURN;
END DOUBLE;
EOF

# --- interrupt procedures -----------------------------------

t_grep intr-saves-registers "Q_tick:" "push hl" "push de" \
	"push bc" "push af" "pop af" "pop bc" "pop de" "pop hl" \
	"ei" <<'EOF'
TICK: PROCEDURE INTERRUPT 1;
DECLARE I BYTE;
I = 1;
END TICK;
EOF

t_ok intr-in-module <<'EOF'
M: DO;
TICK: PROCEDURE INTERRUPT 3;
DECLARE I BYTE;
I = 1;
END TICK;
END M;
EOF

t_err intr-with-params 255 "syntax error" <<'EOF'
T: PROCEDURE (A) INTERRUPT 1;
DECLARE A BYTE;
END T;
EOF

t_err intr-with-type 255 "syntax error" <<'EOF'
T: PROCEDURE BYTE INTERRUPT 1;
END T;
EOF

# a plain procedure must not save registers the way an
# interrupt handler does
t_nogrep proc-no-interrupt-save "push de" "^ei\$" <<'EOF'
F: PROCEDURE(A, B) BYTE;
DECLARE A BYTE, B BYTE;
RETURN A - B;
END F;
DECLARE X BYTE;
X = F(1, 2);
EOF

# a single argument is passed in C on both sides, as in
# PL/M-80, not in E
t_grep proc-one-param-in-c "Q_f:" "ld \(hl\), c" "ld c, a" <<'EOF'
F: PROCEDURE(A) BYTE;
DECLARE A BYTE;
RETURN A;
END F;
DECLARE X BYTE;
X = F(5);
EOF

# --- labels -------------------------------------------------

t_grep label-declared "L_x:" "jp L_x" <<'EOF'
DECLARE X LABEL;
GOTO X;
X: HALT;
EOF

# --- module wrapper -----------------------------------------

t_ok module-decl <<'EOF'
M: DO;
DECLARE X BYTE;
X = 1;
END M;
EOF

t_ok module-end-no-name <<'EOF'
M: DO;
DECLARE X BYTE;
END;
EOF

t_ok module-empty <<'EOF'
M: DO;
END M;
EOF

t_ok empty-block <<'EOF'
DO;
END;
EOF

t_ok module-with-procedure <<'EOF'
M: DO;
F: PROCEDURE (A) BYTE;
DECLARE A BYTE;
RETURN A + 1;
END F;
DECLARE X BYTE;
X = F(3);
END M;
EOF

# a label may sit on its own line, with its statement on the
# next one; the reference compiler accepts this form
t_grep label-on-own-line "L_x:" "jp L_x" "halt\$" <<'EOF'
DECLARE X LABEL;
GOTO X;
X:
HALT;
EOF

t_grep module-label-newline "L_m:" <<'EOF'
M:
DO;
DECLARE X BYTE;
X = 1;
END M;
EOF

# a newline between the procedure name and PROCEDURE is
# noise, as PL/M ignores line breaks inside a header
t_grep proc-header-newline "Q_f:" "call Q_f" <<'EOF'
M: DO;
F:
PROCEDURE (A) BYTE;
DECLARE A BYTE;
RETURN A + 1;
END F;
DECLARE F2 BYTE;
F2 = F(3);
END M;
EOF

# the reference compiler's own test program: module label
# and DO on separate lines, END without a name
t_ok module-own-line-test <<'EOF'
test:
do;
declare i byte;
declare j byte;
myfunc: procedure;
    return;
end myfunc;
end;
EOF

t_ok module-own-line-test2 <<'EOF'
TEST:
DO;
DECLARE I BYTE;
DECLARE J BYTE;
MYFUNC: PROCEDURE;
    RETURN;
END MYFUNC;
END;
EOF

# --- LITERALLY macros ---------------------------------------

t_grep literal-number "ld a, 100" <<'EOF'
DECLARE MAX LITERALLY '100';
DECLARE X BYTE;
X = MAX;
EOF

t_ok literal-expr <<'EOF'
DECLARE TWO LITERALLY '2';
DECLARE X BYTE;
X = TWO + 3;
EOF

t_ok literal-chain <<'EOF'
DECLARE A1 LITERALLY '5';
DECLARE B1 LITERALLY 'A1';
DECLARE X BYTE;
X = B1;
EOF

t_ok literal-array-size <<'EOF'
DECLARE MAX LITERALLY '4';
DECLARE A(MAX) BYTE;
A(0) = 1;
EOF

t_ok literal-data-value <<'EOF'
DECLARE N LITERALLY '7';
DECLARE D DATA (N, 2);
EOF

# --- DATA and INITIAL declarations --------------------------

t_ok data-decl <<'EOF'
DECLARE D DATA (1, 2, 3);
EOF

t_ok data-typed <<'EOF'
DECLARE D BYTE DATA (1, 2, 3);
EOF

t_ok data-sized <<'EOF'
DECLARE D (3) DATA (1, 2, 3);
EOF

t_ok initial-decl <<'EOF'
DECLARE D INITIAL (1, 2, 3);
EOF

t_ok initial-typed <<'EOF'
DECLARE D BYTE INITIAL (1, 2, 3);
EOF

t_ok initial-sized <<'EOF'
DECLARE D (3) INITIAL (1, 2, 3);
EOF

# --- source form --------------------------------------------

# A final line with no trailing newline must still compile.
printf 'DECLARE X BYTE\nX = 1' > "$TMP/noeol.in"
t_ok no-final-newline < "$TMP/noeol.in"

echo "----------------------------------------"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
