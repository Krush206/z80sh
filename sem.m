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

@implementation Shell (Semantic)
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

        case TNUM:
            // Load literal 8-bit number directly into accumulator
            printf("\tld a, %s\n", t->DARR[0]);
            break;

        case TVAR: {
            register int i;

            i = [self lookupName: t->DARR[0]];
            if(i < 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_UNDECL code: 255];
                exit(255);
            }
            // Load 8-bit variable value into accumulator
            printf("\tld a, (%s)\n", symlab[i]);
            break;
        }

        case TADD:
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
                exit(255);
            }
            if(lt == TDECL || lt == TADDR) {
                /* A declaration on the left reserves its space first */
                [self compileTree: t->DLEF];
            }
            i = [self lookupName: t->DLEF->DARR[0]];
            if(i < 0) {
                [self printString: t->DLEF->DARR[0]];
                [self error: ERR_UNDECL code: 255];
                exit(255);
            }
            // Evaluate expression value on the right branch
            [self compileTree: t->DRIT];
            // Store the accumulator value into the variable on the left
            printf("\tld (%s), a\n", symlab[i]);
            if(lt == TADDR) {
                /* addresses hold two bytes; the high one is zero */
                printf("\txor a\n");
                printf("\tld (%s+1), a\n", symlab[i]);
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
            lf = (*lblc)++;
            ln = (*lblc)++;
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
            lt = (*lblc)++;
            ln = (*lblc)++;
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
            lf = (*lblc)++;
            ln = (*lblc)++;
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

            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tcp b\n");
            lt = (*lblc)++;
            ln = (*lblc)++;
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
            printf("\tor a\n");
            lt = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr nz, L%d\n", lt);
            [self compileTree: t->DRIT];
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
            printf("\tor a\n");
            lf = (*lblc)++;
            ln = (*lblc)++;
            printf("\tjr z, L%d\n", lf);
            [self compileTree: t->DRIT];
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
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\tor b\n");
            break;

        case TXOR:
            [self compileTree: t->DRIT];
            printf("\tpush af\n");
            [self compileTree: t->DLEF];
            printf("\tpop bc\n");
            printf("\txor b\n");
            break;

        case TAND:
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

        case TDEREF:
            [self compileAddress: t];
            printf("\tld a, (hl)\n");
            break;

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
            exit(255);
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
            fprintf(stderr, "Unknown AST node type: %d\n", t->DTYP);
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

- (void) compileAddress: (struct Tree *) t
{
	/* hl holds the pointer value of t, which is a TDEREF node */
	[self compileTree: t->DLEF];
	printf("\tld l, a\n");
	printf("\tld h, 0\n");
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
			exit(255);
		}
	if(*symc == SYMSIZ) {
		[self error: ERR_LARGE code: 255];
		exit(255);
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
			exit(255);
		}
		*d++ = (char) c;
	}
	*d = '\0';
	symtyp[*symc] = t;
	symlev[*symc] = *scope;
	size = (t == TADDR) ? 2 : 1;
	if(*ramc + size > STACKP) {
		/* keep clear of the stack base and the reserved top eight */
		[self error: ERR_LARGE code: 255];
		exit(255);
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
@end
