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

# --- classic engine behaviour --------------------------------

t_ok classic-arith <<'EOF'
int a = 2
int b = 3
int c = a + b * 4 - a / b % 3
EOF

t_ok classic-stmts <<'EOF'
int x = 3
while (x) {
x = x - 1;
}
if (x == 0) {
x = 42;
} else {
x = 7;
}
EOF

t_ok classic-c-operators <<'EOF'
int x = 1
int y = 2
if (x == 1 && y != 2 || x < 3) x = 9
EOF

t_ok classic-scope <<'EOF'
int x = 1
{
int x = 2
int y = x
}
int z = x
EOF

t_ok classic-deref <<'EOF'
address p
int v = 65
*p = v
int w = *p
EOF

t_ok classic-io <<'EOF'
int x = input (220)
output (191) = x
EOF

t_ok classic-unspaced <<'EOF'
int x=5
int y=x*2+1
EOF

t_grep classic-char-literal "ld a, 65" <<'EOF'
int c = 'A'
EOF

t_err classic-redeclared 255 "redeclared" <<'EOF'
int x = 1
int x = 2
EOF

t_err classic-undeclared 255 "undeclared" <<'EOF'
int y = z
EOF

t_err classic-unclosed-brace 255 "syntax error" <<'EOF'
{
int x = 1;
EOF

# --- PL/M case-insensitivity and $ handling ------------------

t_grep plm-uppercase "ld a, 5" "ld \(x\), a" <<'EOF'
INT X = 5
X = X + 1
IF (X == 6) OUTPUT (191) = X
EOF

t_grep plm-dollar-declare "linecount:.equ" <<'EOF'
DECLARE LINE$COUNT BYTE
LineCount = 5
LINE$COUNT = LINECOUNT + 1
EOF

t_err plm-dollar-dup 255 "redeclared" <<'EOF'
int a$b = 1
int ab = 2
EOF

t_err plm-case-dup 255 "redeclared" <<'EOF'
int x = 1
INT X = 2
EOF

t_grep plm-declare-forms "i:.equ" "x:.equ" <<'EOF'
DECLARE I ADDRESS
DECLARE X BYTE
X = 1
EOF

t_grep plm-number-dollar "ld a, 10$" <<'EOF'
int a = 1$0
EOF

t_grep plm-number-hex "ld a, 0FFH" "ld a, 101B" <<'EOF'
int h = 0FFH
int b = 101B
EOF

# --- PL/M word operators and comparisons --------------------

t_ok plm-word-operators <<'EOF'
int a = 1 AND 0
int o = 1 OR 0
int x = 1 XOR 1
int m = 7 MOD 3
int p = 1 PLUS 2
int s = 5 MINUS 2
int n = NOT 0
EOF

t_grep plm-and-is-logical "or a" "jr z" <<'EOF'
int a = 1 AND 0
EOF

t_grep plm-or-is-logical "or a" "jr nz" <<'EOF'
int o = 1 OR 0
EOF

t_grep plm-bitwise-and-or "and b" "or b" <<'EOF'
int a = 5 & 3
int o = 5 | 3
EOF

t_grep plm-not-compares "cp b" <<'EOF'
int n = NOT 0
EOF

t_grep plm-equals-compares "cp b" <<'EOF'
int x = 5
int y = 5
IF X = Y THEN X = 1
EOF

t_grep plm-not-equals "jr nz" <<'EOF'
int x = 5
int y = 6
IF (x <> y) x = 2
EOF

t_err plm-reserved-name 255 "syntax error" <<'EOF'
int and = 1
EOF

# --- PL/M statements -----------------------------------------

t_ok plm-if-then-else <<'EOF'
int x = 1
IF X = 1 THEN X = 2 ELSE X = 3
if (x == 2) then x = 4
EOF

t_ok plm-if-same-line-else <<'EOF'
int x = 5
IF X = 5 THEN OUTPUT (191) = X ELSE OUTPUT (191) = 0
EOF

t_ok plm-if-brace-wrapped-else <<'EOF'
int x = 5
{
IF X = 5 THEN X = 1;
ELSE X = 2;
}
EOF

t_ok plm-nested-if <<'EOF'
int x = 1
int y = 2
IF X = 1 THEN IF Y = 2 THEN X = 3 ELSE X = 4 ELSE X = 5
EOF

t_err plm-if-without-then 255 "syntax error" <<'EOF'
int x = 1
IF X = 1 X = 2
EOF

t_ok plm-do-block <<'EOF'
int x = 0
DO;
X = 1;
X = X + 1;
END;
EOF

t_ok plm-do-while <<'EOF'
int x = 3
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
int x = 0
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
int x = 1
do while x
x = 2;
end;
EOF

t_err plm-bare-end 255 "syntax error" <<'EOF'
end
EOF

t_err plm-bare-to 255 "syntax error" <<'EOF'
to
EOF

t_grep plm-disable-enable-halt "di$" "ei$" "halt$" <<'EOF'
DISABLE;
ENABLE;
HALT;
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
