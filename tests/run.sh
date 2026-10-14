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

# --- full image ----------------------------------------------

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

echo "----------------------------------------"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
