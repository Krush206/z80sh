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

@implementation Shell (Semantic)
- (void) compileTree: (struct Tree *) t
{
    if (t == 0)
	    return;
    if(*orgflg == 0) {
        printf("\torg %d\n", ORGADR);
        (*orgflg)++;
    }

    switch(t->DTYP) {

        case TNUM:
            // Load literal 8-bit number directly into accumulator
            printf("\tld a, %s\n", t->DARR[0]);
            break;

        case TVAR:
            if([self lookupName: t->DARR[0]] < 0) {
                [self printString: t->DARR[0]];
                [self error: ERR_UNDECL code: 255];
                (*error)++;
                longjmp(*jmp, 1);
            }
            // Load 8-bit variable value into accumulator
            printf("\tld a, (%s)\n", t->DARR[0]);
            break;

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

        case TDECL:
            /* Reserve one byte of space for the declared variable */
            [self declareName: t->DARR[0] type: TDECL];
            printf("%s:\tdefs 1\n", t->DARR[0]);
            break;

        case TADDR:
            /* Reserve two bytes of space for the declared address */
            [self declareName: t->DARR[0] type: TADDR];
            printf("%s:\tdefs 2\n", t->DARR[0]);
            break;

        case TASG: {
            register char *na;
            register int lt;

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
            if(lt != TVAR && lt != TDECL && lt != TADDR) {
                [self error: ERR_SYNTAX code: 255];
                (*error)++;
                longjmp(*jmp, 1);
            }
            na = t->DLEF->DARR[0];
            if(lt == TDECL || lt == TADDR) {
                /* A declaration on the left reserves its space first */
                [self compileTree: t->DLEF];
            }
            else if([self lookupName: na] < 0) {
                [self printString: na];
                [self error: ERR_UNDECL code: 255];
                (*error)++;
                longjmp(*jmp, 1);
            }
            // Evaluate expression value on the right branch
            [self compileTree: t->DRIT];
            // Store the accumulator value into the variable on the left
            printf("\tld (%s), a\n", na);
            if(lt == TADDR) {
                /* addresses hold two bytes; the high one is zero */
                printf("\txor a\n");
                printf("\tld (%s+1), a\n", na);
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

        default:
            fprintf(stderr, "Unknown AST node type: %d\n", t->DTYP);
            break;
    }
}

- (void) compileAddress: (struct Tree *) t
{
	/* hl holds the pointer value of t, which is a TDEREF node */
	[self compileTree: t->DLEF];
	printf("\tld l, a\n");
	printf("\tld h, 0\n");
}

- (void) declareName: (char *) na type: (int) t
{
	register char *s, *d;

	if([self lookupName: na] >= 0) {
		[self printString: na];
		[self error: ERR_REDECL code: 255];
		(*error)++;
		longjmp(*jmp, 1);
	}
	if(*symc == SYMSIZ) {
		[self error: ERR_LARGE code: 255];
		(*error)++;
		longjmp(*jmp, 1);
	}
	s = na;
	d = symnam[*symc];
	while(*s) {
		if(d >= symnam[*symc] + SYMNAMSIZ - 1) {
			[self error: ERR_LARGE code: 255];
			(*error)++;
			longjmp(*jmp, 1);
		}
		*d++ = *s++;
	}
	*d = '\0';
	symtyp[*symc] = t;
	(*symc)++;
}

- (int) lookupName: (char *) na
{
	register int i;

	for(i=0; i<*symc; i++)
		if(strcmp(symnam[i], na) == 0)
			return(symtyp[i]);
	return(-1);
}
@end
