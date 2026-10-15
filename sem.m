/*
 * Copyright (C) Caldera International Inc.  2001-2002.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code and documentation must retain the above
 *    copyright notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *      This product includes software developed or owned by Caldera
 *      International, Inc.
 * 4. Neither the name of Caldera International, Inc. nor the names of other
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * USE OF THE SOFTWARE PROVIDED FOR UNDER THIS LICENSE BY CALDERA
 * INTERNATIONAL, INC. AND CONTRIBUTORS ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL CALDERA INTERNATIONAL, INC. BE LIABLE FOR ANY DIRECT,
 * INDIRECT INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#import "sh.h"

/*
 * nameEqual
 *	true when the stored name a and the source name b
 *	spell the same identifier: case-insensitive with
 *	$ signs dropped, after PL/M-80
 */
static int nameEqual(const char *a, const char *b)
{
	unsigned char c, d;

	if(a == 0 || b == 0)
		return(0);
	for(;;) {
		c = (unsigned char) *a;
		if(c == '$') {
			a++;
			continue;
		}
		d = (unsigned char) *b;
		if(d == '$') {
			b++;
			continue;
		}
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(d >= 'A' && d <= 'Z')
			d = d + 'a' - 'A';
		if(c != d)
			return(0);
		if(c == '\0')
			return(1);
		a++;
		b++;
	}
}

/*
 * leadingDecls
 *	fill dst with the leading DECLARE leaves of a
 *	procedure body in source order, at most max; the
 *	parameter declarations open the body, so the walk
 *	stops at the first statement that is not a DECLARE
 */
static int leadingDecls(struct Tree *body, struct Tree **dst, int max)
{
	struct Tree *w, *s, *leaf;
	int n;

	n = 0;
	for(w = body; w != 0 && n < max; w = w->DRIT) {
		s = w->DTYP == TLST ? w->DLEF : w;
		while(s != 0 && n < max) {
			if(s->DTYP == TDECL)
				leaf = s;
			else if(s->DTYP == TLST && s->DLEF != 0 &&
			    s->DLEF->DTYP == TDECL)
				leaf = s->DLEF;
			else
				return(n);
			dst[n++] = leaf;
			s = s->DTYP == TDECL ? 0 : s->DRIT;
		}
	}
	return(n);
}

@implementation Shell (Semantic)
/*
 * symbolType
 *	the declared type of symbol i: TADDR counts as 16-bit
 *	ADDRESS, every other entry is a BYTE
 */
- (int) symbolType: (int) i
{
	return symtyp[i] == TADDR ? 1 : 0;
}

/*
 * exprType
 *	0 when the tree evaluates to a BYTE (left in A), 1
 *	when it is an ADDRESS value (left in HL); after the
 *	PL/M-80 promotion rules, with MUL/DIV/MOD keeping
 *	their operands' width here
 */
- (int) exprType: (struct Tree *) t
{
	int i;

	if(t == NULL)
		return(0);
	switch(t->DTYP) {
	case TNUM:
		if([self numberValue: t->DARR[0]] > 255)
			return(1);
		return(0);
	case TVAR:
	case TDECL:
	case TADDR:
		i = [self lookupName: t->DARR[0]];
		if(i < 0)
			return(0);
		return [self symbolType: i];
	case TSUBSCRIPT:
		i = [self procIndex: t->DARR[0]];
		if(i >= 0)
			return prcret[i] == 2;
		i = [self lookupName: t->DARR[0]];
		if(i < 0)
			return(0);
		return [self symbolType: i];
	case TDOUBLE:
		return(1);
	case TPAR:
		return [self exprType: t->DSTR];
	case TASG:
		return [self exprType: t->DLEF];
	case TADD:
	case TSUB:
	case TOR:
	case TXOR:
	case TAND:
	case TOR2:
	case TAND2:
		if([self exprType: t->DLEF] || [self exprType: t->DRIT])
			return(1);
		return(0);
	case TMUL:
	case TDIV:
	case TMOD:
		if([self exprType: t->DLEF] || [self exprType: t->DRIT])
			return(1);
		return(0);
	default:
		return(0);
	}
}

/*
 * toHL
 *	widen the byte in A into HL with a zero high byte
 */
- (void) toHL
{
	printf("\tld l, a\n");
	printf("\tld h, 0\n");
}

/*
 * compile16
 *	leave the value of t in HL; byte trees widen with
 *	high-order zeroes, after PL/M-80
 */
- (void) compile16: (struct Tree *) t
{
	int i;

	if(t == NULL) {
		printf("\tld hl, 0\n");
		return;
	}
	switch(t->DTYP) {
	case TNUM:
		if([self numberValue: t->DARR[0]] > 255) {
			printf("\tld hl, %s\n", t->DARR[0]);
			return;
		}
		printf("\tld a, %s\n", t->DARR[0]);
		[self toHL];
		return;
	case TVAR:
	case TDECL:
	case TADDR:
		i = [self lookupName: t->DARR[0]];
		if(i < 0) {
			[self printString: t->DARR[0]];
			[self error: ERR_UNDECL code: 255];
		}
		if([self symbolType: i]) {
			printf("\tld hl, (%s)\n", symlab[i]);
			return;
		}
		printf("\tld a, (%s)\n", symlab[i]);
		[self toHL];
		return;
	default:
		[self compileTree: t];
		if(![self exprType: t])
			[self toHL];
		return;
	}
}

/*
 * pair16
 *	the left and right children of a 16-bit binary node
 *	into HL and DE
 */
- (void) pair16: (struct Tree *) t
{
	[self compile16: t->DRIT];
	printf("\tpush hl\n");
	[self compile16: t->DLEF];
	printf("\tpop de\n");
}

/*
 * compileShift
 *	8-bit rotate/shift by count, zero count keeps value
 */
- (void) compileShift: (struct Tree *) t op: (const char *) op
{
    int lp, dn;

    /* count to B, value to C, op once per count */
    [self compileTree: t->DRIT];
    printf("\tpush af\n");
    [self compileTree: t->DLEF];
    printf("\tld c, a\n");
    printf("\tpop af\n");
    printf("\tld b, a\n");
    printf("\tld a, b\n");
    printf("\tor a\n");
    lp = (*lblc)++;
    dn = (*lblc)++;
    printf("\tjr z, L%d\n", dn);
    printf("L%d:\n", lp);
    printf("\t%s\n", op);
    printf("\tdec b\n");
    printf("\tjr nz, L%d\n", lp);
    printf("L%d:\n", dn);
    printf("\tld a, c\n");
}

- (void) compileTree: (struct Tree *) t
{
    if (t == 0)
	    return;
    if(*orgflg == 0) {
        printf("\torg %d\n", ORGADR);
        (*orgflg)++;
        [self prologue];
    }

    switch(t->DTYP) {

        case TNOP:
            /* parameter declaration absorbed into the
               procedure entry; nothing to compile */
            break;

        case TNUM:
            // 16-bit literals land in HL, the rest in A
            if([self numberValue: t->DARR[0]] > 255)
                printf("\tld hl, %s\n", t->DARR[0]);
            else
                printf("\tld a, %s\n", t->DARR[0]);
            break;

        case TVAR: {
            register int i;

            i = [self lookupName: t->DARR[0]];
            if(i < 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_UNDECL code: 255];
            }
            if([self arraySize: i] > 0) {
                [self error: ERR_SYNTAX code: 255];
            }
            // Address values load into HL, bytes into A
            if([self symbolType: i])
                printf("\tld hl, (%s)\n", symlab[i]);
            else
                printf("\tld a, (%s)\n", symlab[i]);
            break;
        }

        case TADD:
            if([self exprType: t]) {
                [self pair16: t];
                printf("\tadd hl, de\n");
                break;
            }
            // 1. Evaluate Right branch
            [self compileTree: t->DRIT];
            // 2. Push result to stack
            printf("\tpush af\n");
            // 3. Evaluate Left branch
            [self compileTree: t->DLEF];
            // 4. Pop Right result into temporary register B
            printf("\tpop bc\n");  // (b gets register 'a' value)
            // 5. Add them together
            printf("\tadd a, b\n");
            break;

        case TSUB:
            if([self exprType: t]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\tsub e\n");
                printf("\tld l, a\n");
                printf("\tld a, h\n");
                printf("\tsbc a, d\n");
                printf("\tld h, a\n");
                break;
            }
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tsub b\n");  // A = A - B
            break;

        case TDECL: {
            register int i;

            /* Name a byte of RAM for the declared variable */
            i = [self declareName: t->DARR[0] type: TDECL];
            printf("%s:\tequ 0x%X\n", symlab[i], symadr[i]);
            break;
        }

        case TADDR: {
            register int i;

            /* Name two bytes of RAM for the declared address */
            i = [self declareName: t->DARR[0] type: TADDR];
            printf("%s:\tequ 0x%X\n", symlab[i], symadr[i]);
            break;
        }

        case TARRAY: {
            int i;

            /* Name RAM for every array element */
            if(t->DARR[2] != 0)
                i = [self declareArray: t->DARR[0] type: TADDR
                    size: [self numberValue: t->DARR[1]]];
            else
                i = [self declareArray: t->DARR[0] type: TDECL
                    size: [self numberValue: t->DARR[1]]];
            printf("%s:\tequ 0x%X\n", symlab[i], symadr[i]);
            break;
        }

        case TDATA: {
            int i, n, sz, lb;

            /* ROM storage constant: name gets the ROM
               label and a size so M(i) subscripts work */
            i = [self declareName: t->DARR[0] type: TDATA];
            n = 1;
            while(t->DARR[n] != 0)
                n++;
            sz = n - 1;
            symsiz[i] = sz;
            lb = (*lblc)++;
            printf("\tjp L%d\n", lb);
            printf("%s:\tdefb ", symlab[i]);
            for(n = 1; t->DARR[n] != 0; n++) {
                if(t->DARR[n][0] & QUOTE)
                    [self stringBytes: t->DARR[n]];
                else
                    printf("%s", t->DARR[n]);
                if(t->DARR[n+1] != 0)
                    printf(",");
            }
            printf("\n");
            printf("L%d:\n", lb);
            break;
        }

        case TINITIAL: {
            int i, n, sz, count, lb, lb2, ty, emitted;
            char *w, *s;

            /* preset bytes copied from ROM into the
               freshly allocated RAM at program load */
            ty = (t->DARR[2] != 0) ? 1 : 0;
            if(t->DARR[1] != 0) {
                n = [self numberValue: t->DARR[1]];
                i = [self declareArray: t->DARR[0]
                    type: (ty ? TADDR : TDECL) size: n];
            }
            else {
                n = 1;
                i = [self declareName: t->DARR[0]
                    type: (ty ? TADDR : TDECL)];
            }
            sz = n * (ty ? 2 : 1);
            printf("%s:\tequ 0x%X\n", symlab[i], symadr[i]);
            count = [self numberValue: t->DARR[3]];
            lb = (*lblc)++;
            lb2 = (*lblc)++;
            printf("\tld hl, DBL%d\n", lb);
            printf("\tld de, %s\n", symlab[i]);
            printf("\tld bc, %d\n", sz);
            printf("\tldir\n");
            printf("\tjp L%d\n", lb2);
            printf("DBL%d:\n", lb);
            printf("\tdefb ");
            emitted = 0;
            for(n = 0; n < count; n++) {
                w = t->DARR[4 + n];
                if(w == 0)
                    break;
                if(w[0] & QUOTE) {
                    for(s = w; (*s & 0177) != 0; s++) {
                        if(emitted > 0)
                            printf(",");
                        printf("%d", *s & 0177);
                        emitted++;
                    }
                }
                else if(ty) {
                    /* address constants go low then high */
                    if(emitted > 0)
                        printf(",");
                    printf("%d", [self numberValue: w] & 255);
                    if(emitted + 1 < sz)
                        printf(",");
                    printf("%d", [self numberValue: w] >> 8);
                    emitted += 2;
                }
                else {
                    if(emitted > 0)
                        printf(",");
                    printf("%s", w);
                    emitted++;
                }
            }
            while(emitted < sz) {
                printf(emitted > 0 ? ",0" : "0");
                emitted++;
            }
            printf("\n");
            printf("L%d:\n", lb2);
            break;
        }

        case TASG: {
            register int i, lt;

            lt = t->DLEF->DTYP;
            if(lt == TDEREF) {
                /* store through a pointer */
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileAddress: t->DLEF];
                printf("\tpop af\n");
                printf("\tld (hl), a\n");
                break;
            }
            if(lt == TSUBSCRIPT) {
                /* store into an array element */
                i = [self lookupName: t->DLEF->DARR[0]];
                if(i < 0) {
                    [self printString: t->DLEF->DARR[0]];
                    [self error: ERR_UNDECL code: 255];
                }
                if([self symbolType: i]) {
                    [self compile16: t->DRIT];
                    printf("\tpush hl\n");
                    [self compileIndex: t->DLEF];
                    printf("\tpop de\n");
                    printf("\tld (hl), e\n");
                    printf("\tinc hl\n");
                    printf("\tld (hl), d\n");
                }
                else {
                    [self compileTree: t->DRIT];
                    printf("\tpush af\n");
                    [self compileIndex: t->DLEF];
                    printf("\tpop af\n");
                    printf("\tld (hl), a\n");
                }
                break;
            }
            if(lt == TOUTPUT) {
                /* PL/M OUTPUT(port) = value; the port is the
                   operand of the TOUTPUT node on the left */
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF->DLEF];
                printf("\tld c, a\n");
                printf("\tld b, c\n");
                printf("\tpop af\n");
                printf("\tout (c), a\n");
                printf("\tnop\n");
                break;
            }
            if(lt != TVAR && lt != TDECL && lt != TADDR) {
                [self error: ERR_SYNTAX code: 255];
            }
            if(lt == TDECL || lt == TADDR) {
                /* A declaration on the left reserves its space first */
                [self compileTree: t->DLEF];
            }
            i = [self lookupName: t->DLEF->DARR[0]];
            if(i < 0) {
                [self printString: t->DLEF->DARR[0]];
                [self error: ERR_UNDECL code: 255];
            }
            if([self arraySize: i] > 0) {
                [self error: ERR_SYNTAX code: 255];
            }
            // Evaluate expression value on the right branch
            if([self symbolType: i]) {
                /* address variable: store the whole HL pair */
                [self compile16: t->DRIT];
                printf("\tld (%s), hl\n", symlab[i]);
            }
            else {
                [self compileTree: t->DRIT];
                if([self exprType: t->DRIT])
                    printf("\tld a, l\n");
                // Store the accumulator value into the variable
                printf("\tld (%s), a\n", symlab[i]);
            }
            break;
        }

        case TLST:
            // Command/expression list: compile left side, then right side
            [self compileTree: t->DLEF];
            if (t->DRIT)
                [self compileTree: t->DRIT];
            break;

        case TPAR:
            // Parenthesized sub-expression: compile the inner tree
            [self compileTree: t->DSTR];
            break;

        case TEQU: {
            register int lt, ln;

            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\txor e\n");
                printf("\tld b, a\n");
                printf("\tld a, h\n");
                printf("\txor d\n");
                printf("\tor b\n");
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            lt = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr z, L%d\n", lt);
            printf("\tld a, 0\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lt);
            printf("\tld a, 1\n");
            printf("L%d:\n", ln);
            break;
        }

        case TNEQ: {
            register int lt, ln;

            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\txor e\n");
                printf("\tld b, a\n");
                printf("\tld a, h\n");
                printf("\txor d\n");
                printf("\tor b\n");
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            lt = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr nz, L%d\n", lt);
            printf("\tld a, 0\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lt);
            printf("\tld a, 1\n");
            printf("L%d:\n", ln);
            break;
        }

        case TGTR: {
            register int lf, ln;

            lf = (*lblc)++;
            ln = (*lblc)++;
            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, h\n");
                printf("\tcp d\n");
                printf("\tjr nz, L%d\n", ln);
                printf("\tld a, l\n");
                printf("\tcp e\n");
                printf("L%d:\n", ln);
                ln = (*lblc)++;
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            printf("\tjr z, L%d\n", lf);
            printf("\tjr c, L%d\n", lf);
            printf("\tld a, 1\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lf);
            printf("\tld a, 0\n");
            printf("L%d:\n", ln);
            break;
        }

        case TLSS: {
            register int lt, ln;

            lt = (*lblc)++;
            ln = (*lblc)++;
            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, h\n");
                printf("\tcp d\n");
                printf("\tjr nz, L%d\n", ln);
                printf("\tld a, l\n");
                printf("\tcp e\n");
                printf("L%d:\n", ln);
                ln = (*lblc)++;
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            printf("\tjr c, L%d\n", lt);
            printf("\tld a, 0\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lt);
            printf("\tld a, 1\n");
            printf("L%d:\n", ln);
            break;
        }

        case TGEQ: {
            register int lf, ln;

            lf = (*lblc)++;
            ln = (*lblc)++;
            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, h\n");
                printf("\tcp d\n");
                printf("\tjr nz, L%d\n", ln);
                printf("\tld a, l\n");
                printf("\tcp e\n");
                printf("L%d:\n", ln);
                ln = (*lblc)++;
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            printf("\tjr c, L%d\n", lf);
            printf("\tld a, 1\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lf);
            printf("\tld a, 0\n");
            printf("L%d:\n", ln);
            break;
        }

        case TLEQ: {
            register int lt, ln;

            lt = (*lblc)++;
            ln = (*lblc)++;
            if([self exprType: t->DLEF] || [self exprType: t->DRIT]) {
                [self pair16: t];
                printf("\tld a, h\n");
                printf("\tcp d\n");
                printf("\tjr nz, L%d\n", ln);
                printf("\tld a, l\n");
                printf("\tcp e\n");
                printf("L%d:\n", ln);
                ln = (*lblc)++;
            }
            else {
                [self compileTree: t->DRIT];
                printf("\tpush af\n");
                [self compileTree: t->DLEF];
                printf("\tpop bc\n");
                printf("\tcp b\n");
            }
            printf("\tjr c, L%d\n", lt);
            printf("\tjr z, L%d\n", lt);
            printf("\tld a, 0\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lt);
            printf("\tld a, 1\n");
            printf("L%d:\n", ln);
            break;
        }

        case TOR2: {
            register int lt, ln;

            [self compileTree: t->DLEF];
            if([self exprType: t->DLEF]) {
                printf("\tld a, l\n");
                printf("\tor h\n");
            }
            else
                printf("\tor a\n");
            lt = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr nz, L%d\n", lt);
            [self compileTree: t->DRIT];
            if([self exprType: t->DRIT]) {
                printf("\tld a, l\n");
                printf("\tor h\n");
            }
            else
                printf("\tor a\n");
            printf("\tjr nz, L%d\n", lt);
            printf("\tld a, 0\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lt);
            printf("\tld a, 1\n");
            printf("L%d:\n", ln);
            break;
        }

        case TAND2: {
            register int lf, ln;

            [self compileTree: t->DLEF];
            if([self exprType: t->DLEF]) {
                printf("\tld a, l\n");
                printf("\tor h\n");
            }
            else
                printf("\tor a\n");
            lf = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr z, L%d\n", lf);
            [self compileTree: t->DRIT];
            if([self exprType: t->DRIT]) {
                printf("\tld a, l\n");
                printf("\tor h\n");
            }
            else
                printf("\tor a\n");
            printf("\tjr z, L%d\n", lf);
            printf("\tld a, 1\n");
            printf("\tjr L%d\n", ln);
            printf("L%d:\n", lf);
            printf("\tld a, 0\n");
            printf("L%d:\n", ln);
            break;
        }

        case TOR:
            if([self exprType: t]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\tor e\n");
                printf("\tld l, a\n");
                printf("\tld a, h\n");
                printf("\tor d\n");
                printf("\tld h, a\n");
                break;
            }
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tor b\n");
            break;

        case TXOR:
            if([self exprType: t]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\txor e\n");
                printf("\tld l, a\n");
                printf("\tld a, h\n");
                printf("\txor d\n");
                printf("\tld h, a\n");
                break;
            }
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\txor b\n");
            break;

        case TAND:
            if([self exprType: t]) {
                [self pair16: t];
                printf("\tld a, l\n");
                printf("\tand e\n");
                printf("\tld l, a\n");
                printf("\tld a, h\n");
                printf("\tand d\n");
                printf("\tld h, a\n");
                break;
            }
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tand b\n");
            break;

        case TMUL: {
            register int lp, sk;

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tld c, a\n");
            printf("\txor a\n");
            printf("\tld e, 8\n");
            lp = (*lblc)++;
            sk = (*lblc)++;
            printf("L%d:\n", lp);
            printf("\tsrl b\n");
            printf("\tjr nc, L%d\n", sk);
            printf("\tadd a, c\n");
            printf("L%d:\n", sk);
            printf("\tsla c\n");
            printf("\tdec e\n");
            printf("\tjr nz, L%d\n", lp);
            break;
        }

        case TDIV: {
            register int lp, dn;

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tld c, a\n");
            printf("\tld e, 0\n");
            printf("\tld a, b\n");
            printf("\tor a\n");
            lp = (*lblc)++;
            dn = (*lblc)++;
            printf("\tjr z, L%d\n", dn);
            printf("L%d:\n", lp);
            printf("\tld a, c\n");
            printf("\tsub b\n");
            printf("\tjr c, L%d\n", dn);
            printf("\tld c, a\n");
            printf("\tinc e\n");
            printf("\tjr L%d\n", lp);
            printf("L%d:\n", dn);
            printf("\tld a, e\n");
            break;
        }

        case TMOD: {
            register int lp, dn;

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tld c, a\n");
            printf("\tld e, 0\n");
            printf("\tld a, b\n");
            printf("\tor a\n");
            lp = (*lblc)++;
            dn = (*lblc)++;
            printf("\tjr z, L%d\n", dn);
            printf("L%d:\n", lp);
            printf("\tld a, c\n");
            printf("\tsub b\n");
            printf("\tjr c, L%d\n", dn);
            printf("\tld c, a\n");
            printf("\tinc e\n");
            printf("\tjr L%d\n", lp);
            printf("L%d:\n", dn);
            printf("\tld a, c\n");
            break;
        }

        case TIF: {
            register int le, ln;

            [self compileTree: t->DLEF];
            printf("\tor a\n");
            if(t->DSTR != 0) {
                le = (*lblc)++;
                ln = (*lblc)++;
                printf("\tjr z, L%d\n", le);
                [self compileTree: t->DRIT];
                printf("\tjr L%d\n", ln);
                printf("L%d:\n", le);
                [self compileTree: t->DSTR];
                printf("L%d:\n", ln);
            }
            else {
                ln = (*lblc)++;
                printf("\tjr z, L%d\n", ln);
                [self compileTree: t->DRIT];
                printf("L%d:\n", ln);
            }
            break;
        }

        case TWHILE: {
            register int lb, ln;

            lb = (*lblc)++;
            ln = (*lblc)++;
            printf("L%d:\n", lb);
            [self compileTree: t->DLEF];
            printf("\tor a\n");
            printf("\tjr z, L%d\n", ln);
            [self compileTree: t->DRIT];
            printf("\tjr L%d\n", lb);
            printf("L%d:\n", ln);
            break;
        }

        case TLENGTH:
        case TLAST: {
            int i, n;

            i = [self lookupName: t->DARR[0]];
            if(i < 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_UNDECL code: 255];
            }
            n = [self arraySize: i];
            if(n <= 0) {
                [self error: ERR_SYNTAX code: 255];
            }
            if(t->DTYP == TLAST)
                n--;
            printf("\tld a, %d\n", n);
            break;
        }

        case TDEREF:
            [self compileAddress: t];
            printf("\tld a, (hl)\n");
            break;

        case TLDEF:
            /* label prefix: just mark the address */
            [self emitLabel: t->DARR[0]];
            printf(":\n");
            break;

        case TGOTO:
            printf("\tjp ");
            [self emitLabel: t->DARR[0]];
            printf("\n");
            break;

        case TCALL: {
            int pi;

            pi = [self procIndex: t->DARR[0]];
            /* CALL only invokes a void procedure, after PL/M-80 */
            if(pi >= 0 && prcret[pi] != 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_SYNTAX code: 255];
            }
            [self emitCall: t];
            break;
        }

        case TRETURN: {
            int pi;

            pi = *inProc - 1;
            if(pi < 0) {
                [self error: ERR_SYNTAX code: 255];
            }
            if(t->DLEF != 0) {
                if(prcret[pi] == 0) {
                    [self error: ERR_SYNTAX code: 255];
                }
                if(prcret[pi] == 2)
                    [self compile16: t->DLEF];
                else {
                    [self compileTree: t->DLEF];
                    if([self exprType: t->DLEF])
                        printf("\tld a, l\n");
                }
            }
            else if(prcret[pi] != 0) {
                [self error: ERR_SYNTAX code: 255];
            }
            printf("\tret\n");
            break;
        }

        case TPROCEDURE:
            [self defineProc: t];
            break;

        case TSUBSCRIPT: {
            int i;

            i = [self procIndex: t->DARR[0]];
            if(i >= 0) {
                if(prcret[i] == 0) {
                    [self printString: t->DARR[0]];
                    [self error: ERR_SYNTAX code: 255];
                }
                [self emitCall: t];
                break;
            }
            i = [self lookupName: t->DARR[0]];
            if(i < 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_UNDECL code: 255];
            }
            [self compileIndex: t];
            if([self symbolType: i]) {
                /* address array element is a 16-bit value */
                printf("\tld a, (hl)\n");
                printf("\tinc hl\n");
                printf("\tld h, (hl)\n");
                printf("\tld l, a\n");
            }
            else
                printf("\tld a, (hl)\n");
            break;
        }

        case TINPUT:
            /* PL/M INPUT(port): byte value from the port */
            [self compileTree: t->DLEF];
            printf("\tld c, a\n");
            printf("\tld b, c\n");
            printf("\tin a, (c)\n");
            printf("\tnop\n");
            break;

        case TOUTPUT:
            /* write-only; OUTPUT(port) needs = value */
            [self error: ERR_SYNTAX code: 255];
            break;

        case TSHL:
            [self compileShift: t op: "ld a, c\n\tsla a\n\tld c, a"];
            break;

        case TSHR:
            [self compileShift: t op: "ld a, c\n\tsra a\n\tld c, a"];
            break;

        case TROL:
            [self compileShift: t op: "ld a, c\n\trlca\n\tld c, a"];
            break;

        case TROR:
            [self compileShift: t op: "ld a, c\n\trrca\n\tld c, a"];
            break;

        case TSCL:
            /* carry starts clear and joins the rotate */
            [self compileShift: t op: "rl c"];
            break;

        case TSCR:
            [self compileShift: t op: "rr c"];
            break;

        case TTIME: {
            int lp, il, dn;

            /* about 100us per unit at 3.58MHz: 21 inner
               iterations near 16 cycles, plus the outer */
            [self compileTree: t->DLEF];
            printf("\tld b, a\n");
            lp = (*lblc)++;
            il = (*lblc)++;
            dn = (*lblc)++;
            printf("\tld a, b\n");
            printf("\tor a\n");
            printf("\tjr z, L%d\n", dn);
            printf("L%d:\n", lp);
            printf("\tld c, 21\n");
            printf("L%d:\n", il);
            printf("\tdec c\n");
            printf("\tjr nz, L%d\n", il);
            printf("\tdec b\n");
            printf("\tjr nz, L%d\n", lp);
            printf("L%d:\n", dn);
            break;
        }

        case TDEC:
            /* decimal-adjust the addition below */
            [self compileTree: t->DLEF];
            printf("\tdaa\n");
            break;

        case TLOW:
            /* low byte of an address value, after PL/M-80 */
            if([self exprType: t->DLEF]) {
                [self compileTree: t->DLEF];
                printf("\tld a, l\n");
            }
            else
                [self compileTree: t->DLEF];
            break;

        case THIGH:
            /* high byte of an address value; bytes have none */
            if([self exprType: t->DLEF]) {
                [self compileTree: t->DLEF];
                printf("\tld a, h\n");
            }
            else {
                [self compileTree: t->DLEF];
                printf("\tld a, 0\n");
            }
            break;

        case TDOUBLE:
            /* byte widened into an address value */
            [self compileTree: t->DLEF];
            if(![self exprType: t->DLEF]) {
                printf("\tld l, a\n");
                printf("\tld h, 0\n");
            }
            break;

        case TDISABLE:
            printf("\tdi\n");
            break;

        case TENABLE:
            printf("\tei\n");
            break;

        case THALT:
            printf("\thalt\n");
            break;

        case TBLOCK: {
            register int n, lv, ra;

            /* block scope: locals vanish at the closing } */
            lv = *scope;
            n = *symc;
            ra = *ramc;
            (*scope)++;
            [self compileTree: t->DLEF];
            *symc = n;
            *ramc = ra;
            *scope = lv;
            break;
        }

        default:
            [self error: "unknown syntax tree node" code: 255];
            break;
    }
}

- (void) prologue
{
	/* vectors, boot and silence, after the reference manual */
	printf("\tjp start\n");
	printf("\tdefs 0x35\n");
	printf("\tret\n");
	printf("\tdefs 0x2D\n");
	printf("\tretn\n");
	printf("start:\n");
	printf("\tdi\n");
	printf("\tim 1\n");
	printf("\tld sp, 0x%X\n", STACKP);
	printf("\tld hl, 0x%X\n", RAMSTART);
	printf("\tld de, 0x%X\n", RAMSTART + 1);
	printf("\tld bc, 0x%X\n", RAMSIZE - 1);
	printf("\tld (hl), 0\n");
	printf("\tldir\n");
	printf("\tld a, 0x9F\n");
	printf("\tout (0x7F), a\n");
	printf("\tld a, 0xBF\n");
	printf("\tout (0x7F), a\n");
	printf("\tld a, 0xDF\n");
	printf("\tout (0x7F), a\n");
	printf("\tld a, 0xFF\n");
	printf("\tout (0x7F), a\n");
}

- (void) compileIndex: (struct Tree *) t
{
    int i;

    /* hl aims at the array element; a holds the index;
       address arrays index by two bytes per element */
    i = [self lookupName: t->DARR[0]];
    if(i < 0) {
        [self printString: t->DARR[0]];
        [self error: ERR_UNDECL code: 255];
    }
    if([self arraySize: i] <= 0) {
        [self error: ERR_SYNTAX code: 255];
    }
    if(t->DLEF == 0 || t->DLEF->DRIT != 0) {
        [self error: ERR_SYNTAX code: 255];
    }
    [self compileTree: t->DLEF->DLEF];
    printf("\tld e, a\n");
    printf("\tld hl, %s\n", symlab[i]);
    printf("\tld d, 0\n");
    printf("\tadd hl, de\n");
    if([self symbolType: i])
        printf("\tadd hl, de\n");
}

- (void) emitLabel: (char *) na
{



	/* canonical assembler name for a PL/M label:
	   lower case, $ removed, L_ prefix keeps them off
	   the user namespace */
	char c;

	printf("L_");
	while((c = *na++) != 0) {
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		putchar(c);
	}
}

/*
 * procIndex
 *	the slot of a defined procedure named na, or -1
 */
- (int) procIndex: (char *) na
{
	int i;

	for(i = *prcc - 1; i >= 0; i--)
		if(nameEqual(prcnam[i], na))
			return(i);
	return(-1);
}

/*
 * emitArgs
 *	evaluate the argument chain into the callee's
 *	registers: byte values, last in E, prior in C,
 *	earlier pushed left-to-right
 */
- (void) emitArgs: (struct Tree *) list
{
	struct Tree *av[MAXPARS];
	struct Tree *p;
	int n, i;

	n = 0;
	for(p = list; p != 0; p = p->DRIT) {
		if(n == MAXPARS) {
			[self error: ERR_LARGE code: 255];
		}
		av[n++] = p->DLEF;
	}
	/* evaluate every argument left to right, keeping the
	   results on the stack: a later argument that is itself
	   a call would otherwise clobber C or E */
	for(i = 0; i < n; i++) {
		[self compileTree: av[i]];
		if([self exprType: av[i]])
			printf("\tld a, l\n");
		printf("\tpush af\n");
	}
	/* a lone argument goes to C; with two or more the last
	   is E and the one before it C, after PL/M-80; earlier
	   ones stay on the stack for the callee to pop, arg0
	   deepest */
	if(n == 1)
		printf("\tpop af\n\tld c, a\n");
	else if(n >= 2) {
		printf("\tpop af\n\tld e, a\n");
		printf("\tpop af\n\tld c, a\n");
	}
}

/*
 * emitCall
 *	call a defined procedure; its result type comes
 *	from the procedure table so expression sites can
 *	place A or HL
 */
- (void) emitCall: (struct Tree *) t
{
	int pi, n;
	struct Tree *p;
	char *s;

	pi = [self procIndex: t->DARR[0]];
	if(pi < 0) {
		[self printString: t->DARR[0]];
		[self error: ERR_UNDECL code: 255];
	}
	n = 0;
	for(p = t->DLEF; p != 0; p = p->DRIT)
		n++;
	if(n != prcnpar[pi]) {
		[self printString: t->DARR[0]];
		[self error: ERR_SYNTAX code: 255];
	}
	[self emitArgs: t->DLEF];
	s = prcnam[pi];
	printf("\tcall Q_");
	while(*s != 0) {
		putchar(*s++);
	}
	printf("\n");
}

/*
 * defineProc
 *	a procedure definition: register it, skip over its
 *	body, declare the params in header order, emit the
 *	entry stores, compile the body, then return
 */
- (void) defineProc: (struct Tree *) t
{
	int pi, npar, np, ret, i, n, lv, skip, ip;
	struct Tree *decls[MAXPARS];
	char *s, *d;

	if(*prcc == PROCSIZ) {
		[self error: ERR_LARGE code: 255];
	}
	pi = (*prcc)++;
	s = t->DARR[0];
	d = prcnam[pi];
	while(*s != 0) {
		char c;

		c = *s++;
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		*d++ = c;
	}
	*d = '\0';
	npar = [self numberValue: t->DARR[2]];
	ret = 0;
	if(t->DARR[1] != 0) {
		s = t->DARR[1];
		ret = 1;
		if(*s == 'a' || *s == 'A')
			ret = 2;
	}
	prcnpar[pi] = npar;
	prcret[pi] = ret;
	/* interrupt procedures are void and parameterless and
	   save every register across the handler */
	ip = t->DINT != 0;
	/* params take their own static storage, as in PL/M-80;
	   their names leave scope with the body, but the RAM
	   stays allocated so no enclosing variable overlays it */
	lv = *scope;
	n = *symc;
	(*scope)++;
	*inProc = pi + 1;
	skip = (*lblc)++;
	printf("\tjp L%d\n", skip);
	printf("Q_%s:\n", prcnam[pi]);
	if(ip) {
		printf("\tpush hl\n");
		printf("\tpush de\n");
		printf("\tpush bc\n");
		printf("\tpush af\n");
	}
	/*
	 * The body's leading DECLAREs allocate the params in
	 * header order; mark them TNOP so the body compile
	 * below does not allocate them twice.
	 */
	np = leadingDecls(t->DLEF, decls, npar);
	if(np != npar) {
		[self printString: t->DARR[0]];
		[self error: ERR_SYNTAX code: 255];
	}
	for(i = 0; i < npar; i++) {
		if(!nameEqual(decls[i]->DARR[0], t->DARR[3 + i])) {
			[self printString: t->DARR[0]];
			[self error: ERR_SYNTAX code: 255];
		}
		prcadr[pi][i] = [self declareName: decls[i]->DARR[0]
		    type: TDECL];
		printf("%s:\tequ 0x%X\n", symlab[prcadr[pi][i]],
		    symadr[prcadr[pi][i]]);
		decls[i]->DTYP = TNOP;
	}
	/* entry stores: a lone parameter arrives in C; with two
	   or more the last is in E and the one before it in C;
	   the rest are popped back off the stack */
	if(npar == 1) {
		i = prcadr[pi][0];
		printf("\tld hl, %s\n", symlab[i]);
		printf("\tld (hl), c\n");
	}
	if(npar >= 2) {
		i = prcadr[pi][npar - 1];
		printf("\tld hl, %s\n", symlab[i]);
		printf("\tld (hl), e\n");
		i = prcadr[pi][npar - 2];
		printf("\tld hl, %s\n", symlab[i]);
		printf("\tld (hl), c\n");
	}
	if(npar >= 3) {
		printf("\tpop de\n");
		for(i = npar - 3; i >= 0; i--) {
			printf("\tpop bc\n");
			printf("\tld hl, %s\n", symlab[prcadr[pi][i]]);
			printf("\tld (hl), c\n");
		}
		printf("\tpush de\n");
	}
	[self compileTree: t->DLEF];
	if(ip) {
		printf("\tpop af\n");
		printf("\tpop bc\n");
		printf("\tpop de\n");
		printf("\tpop hl\n");
		printf("\tei\n");
	}
	printf("\tret\n");
	printf("L%d:\n", skip);
	*inProc = 0;
	*symc = n;
	*scope = lv;
}

- (void) compileAddress: (struct Tree *) t
{
	/* hl holds the pointer value of t, which is a TDEREF node;
	   the pointer is now a real 16-bit value */
	if([self exprType: t->DLEF]) {
		[self compileTree: t->DLEF];
	}
	else {
		[self compileTree: t->DLEF];
		printf("\tld l, a\n");
		printf("\tld h, 0\n");
	}
}

- (int) declareName: (char *) na type: (int) t
{
	register char *s, *d;
	register int i, size;
	unsigned char c;

	for(i = *symc - 1; i >= 0 && symlev[i] == *scope; i--)
		if(nameEqual(symnam[i], na)) {
			[self printString: na];
			[self error: ERR_REDECL code: 255];
		}
	if(*symc == SYMSIZ) {
		[self error: ERR_LARGE code: 255];
	}
	/* stored names are canonical: lower case, $ signs dropped,
	   so emitted labels assemble and lookups match any spelling */
	s = na;
	d = symnam[*symc];
	while(*s) {
		c = (unsigned char) *s++;
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(d >= symnam[*symc] + SYMNAMSIZ - 1) {
			[self error: ERR_LARGE code: 255];
		}
		*d++ = (char) c;
	}
	*d = '\0';
	symtyp[*symc] = t;
	symlev[*symc] = *scope;
	symsiz[*symc] = 0;
	size = (t == TADDR) ? 2 : 1;
	if(*ramc + size > STACKP) {
		/* keep clear of the stack base and the reserved top eight */
		[self error: ERR_LARGE code: 255];
	}
	symadr[*symc] = *ramc;
	*ramc += size;
	if(*scope == 0)
		(void) strcpy(symlab[*symc], symnam[*symc]);
	else {
		(void) strcpy(symlab[*symc], symnam[*symc]);
		(void) strcat(symlab[*symc], "_");
		(void) strcat(symlab[*symc], [self integerToASCII: (*lblc)++]);
	}
	return((*symc)++);
}

- (int) declareArray: (char *) na type: (int) t size: (int) n
{
	char *s, *d;
	int i, size;
	unsigned char c;

	for(i = *symc - 1; i >= 0 && symlev[i] == *scope; i--)
		if(nameEqual(symnam[i], na)) {
			[self printString: na];
			[self error: ERR_REDECL code: 255];
		}
	if(*symc == SYMSIZ) {
		[self error: ERR_LARGE code: 255];
	}
	s = na;
	d = symnam[*symc];
	while(*s) {
		c = (unsigned char) *s++;
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(d >= symnam[*symc] + SYMNAMSIZ - 1) {
			[self error: ERR_LARGE code: 255];
		}
		*d++ = (char) c;
	}
	*d = '\0';
	symtyp[*symc] = t;
	symlev[*symc] = *scope;
	symsiz[*symc] = n;
	if(n > 255) {
		/* subscripts are bytes, so larger arrays
		   strand their LENGTH past ld a */
		[self error: ERR_LARGE code: 255];
	}
	size = (t == TADDR) ? 2 * n : n;
	if(*ramc + size > STACKP) {
		/* keep clear of the stack base and the reserved top eight */
		[self error: ERR_LARGE code: 255];
	}
	symadr[*symc] = *ramc;
	*ramc += size;
	if(*scope == 0)
		(void) strcpy(symlab[*symc], symnam[*symc]);
	else {
		(void) strcpy(symlab[*symc], symnam[*symc]);
		(void) strcat(symlab[*symc], "_");
		(void) strcat(symlab[*symc], [self integerToASCII: (*lblc)++]);
	}
	return((*symc)++);
}

- (int) lookupName: (char *) na
{
	register int i;

	for(i = *symc - 1; i >= 0; i--)
		if(nameEqual(symnam[i], na))
			return(i);
	return(-1);
}

- (int) arraySize: (int) i
{
	return symsiz[i];
}
@end
