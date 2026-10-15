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
 * the keywords for the parser, after the C shell's srchn
 * table from init.c; each row adds a keyword by spelling
 * and node type, handled where srchx is consulted below;
 * rows stay in alphabetical order for the binary search;
 * spellings are lower case and matched case-insensitively
 * with $ signs ignored, after PL/M-80; every row maps to
 * a token with real parser support, no placeholders
 */
static struct Keyword keyw[] = {
	{ "address", TADDR },
	{ "and", TAND2 },
	{ "byte", TBYTE },
	{ "call", TCALL },
	{ "case", TCASE },
	{ "data", TDATA },
	{ "dec", TDEC },
	{ "declare", TDECL },
	{ "disable", TDISABLE },
	{ "do", TDO },
	{ "double", TDOUBLE },
	{ "else", TELSE },
	{ "enable", TENABLE },
	{ "end", TEND },
	{ "go", TGO },
	{ "goto", TGOTO },
	{ "halt", THALT },
	{ "high", THIGH },
	{ "if", TIF },
	{ "initial", TINITIAL },
	{ "input", TINPUT },
	{ "interrupt", TINTERRUPT },
	{ "label", TLABEL },
	{ "last", TLAST },
	{ "length", TLENGTH },
	{ "literally", TLITERAL },
	{ "low", TLOW },
	{ "minus", TSUB },
	{ "mod", TMOD },
	{ "not", TNOT },
	{ "or", TOR2 },
	{ "output", TOUTPUT },
	{ "plus", TADD },
	{ "procedure", TPROCEDURE },
	{ "return", TRETURN },
	{ "rol", TROL },
	{ "ror", TROR },
	{ "scl", TSCL },
	{ "scr", TSCR },
	{ "shl", TSHL },
	{ "shr", TSHR },
	{ "then", TTHEN },
	{ "time", TTIME },
	{ "to", TTO },
	{ "while", TWHILE },
	{ "xor", TXOR }
};

@implementation Shell (Parser)
/*
 * syntax
 *	empty
 *	synstmt
 */
- (struct Tree *) syntax: (char **) p1 end: (char **) p2
{
	while(p1 != p2) {
		if([self anyCharacter: **p1 in: ";\n"])
			p1++;
		else
			return [self synstmt: p1 end: p2];
	}
	return(0);
}

/*
 * headparse
 *	statement or DO..END group at p1, or 0 when p1 starts
 *	an expression; trailing ; and newlines past the
 *	closing END do not count, so group; rest splits right
 */
- (struct Tree *) headparse: (char **) p1 end: (char **) p2
{
	register int k;

	if(p1 == p2)
		return(0);
	/* name: PROCEDURE ... END name; spans statements; the
	   statements after END name run on as the rest of the
	   list, as they do at the top level */
	if([self procName: p1 end: p2] != 0) {
		char **m, **r;
		struct Tree *def, *rest, *both;

		def = [self statement: p1 end: p2];
		m = [self matchProc: p1 end: p2];
		r = p2;
		if(m != 0) {
			r = m + 1;
			if(r != p2 && [self nameEq: *r other: *p1])
				r++;
		}
		rest = [self syntax: r end: p2];
		if(rest == 0)
			return(def);
		both = [self tree];
		both->DTYP = TLST;
		both->DLEF = def;
		both->DRIT = rest;
		return(both);
	}
	/* label: statement — plain or structured */
	if(p2 >= p1+2 && strcmp(*(p1+1), ":") == 0 &&
	    [self srchx: *p1] == -1 && [self nameOk: *p1]) {
		struct Tree *lab, *body, *both;

		lab = [self tree];
		lab->DTYP = TLDEF;
		lab->DARR[0] = *p1;
		body = [self synstmt: p1+2 end: p2];
		both = [self tree];
		both->DTYP = TLST;
		both->DLEF = lab;
		both->DRIT = body;
		return(both);
	}
	k = [self srchx: *p1];
	if(k == TIF)
		return [self statement: p1 end: p2];
	if(k == TCALL || k == TRETURN || k == TGOTO || k == TGO) {
		char **sp;

		/* statement() parses a lone statement range; with
		   more statements following, step back and let
		   synstmt split the list first */
		for(sp = p1; sp != p2; sp++)
			if(**sp == ';' || **sp == '\n')
				return(0);
		return [self statement: p1 end: p2];
	}
	if(k == TDO) {
		char **m;

		/* a DO range parses only through its matching END,
		   which may carry the module name (END name;) */
		m = [self matchEnd: p1 end: p2];
		if(m == 0)
			return(0);
		if([self endPast: m end: p2] == 0)
			return(0);
		return [self statement: p1 end: m+1];
	}
	return(0);
}

/*
 * synstmt
 *	synasg
 *	synasg ; syntax
 *
 *	; and newline split at depth zero, where depth counts
 *	parens and DO..END pairs alike, so no DO group ever
 *	splits in the middle
 */
/*
 * splitList
 *	the TLST node for a synstmt split at p: the head runs
 *	through headparse, falling back to synasg, and the
 *	rest through syntax
 */
- (struct Tree *) splitList: (char **) p1 at: (char **) p end: (char **) p2
{
	register struct Tree *t, *t1;

	t = [self tree];
	t->DTYP = TLST;
	t->DLEF = [self headparse: p1 end: p];
	if(t->DLEF == 0)
		t->DLEF = [self synasg: p1 end: p];
	t1 = [self syntax: p+1 end: p2];
	if(t1 != 0)
		t->DRIT = t1;
	else
		t->DRIT = 0;
	return(t);
}

/*
 * synstmt
 *	synasg
 *	synasg ; syntax
 *
 *	; and newline split at depth zero, where depth counts
 *	parens and DO..END pairs alike, so no DO group ever
 *	splits in the middle
 */
- (struct Tree *) synstmt: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	int l, dd;

	l = 0;
	dd = 0;
	/* leading separators carry no statement */
	while(p1 != p2 && (**p1 == ';' || **p1 == '\n'))
		p1++;
	if(p1 != p2) {
		t = [self headparse: p1 end: p2];
		if(t != 0)
			return(t);
	}
	for(p=p1; p!=p2; p++) {
		if(l == 0 && ([self wordIs: *p name: "do"] ||
		    [self wordIs: *p name: "procedure"]))
			dd++;
		else if(l == 0 && [self wordIs: *p name: "end"])
			dd--;
		if((**p == ';' || **p == '\n') && l == 0 && dd == 0)
			return [self splitList: p1 at: p end: p2];
		switch(**p) {

		case '(':
			l++;
			continue;

		case ')':
			l--;
			continue;
		}
	}
	if(l == 0 && dd == 0)
		return [self synasg: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * matchParen
 *	the close paren matching the open at p1, or 0 when
 *	the range holds none
 */
- (char **) matchParen: (char **) p1 end: (char **) p2
{
	register char **p;
	register int l;

	l = 0;
	for(p = p1; p != p2; p++) {
		if(strcmp(*p, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") != 0)
			continue;
		l--;
		if(l != 0)
			continue;
		return(p);
	}
	return(0);
}

/*
 * matchElse
 *	the ELSE closing an IF body at p1, or 0 when the
 *	range holds none; nested IFs and DO..END groups
 *	are skipped
 */
- (char **) matchElse: (char **) p1 end: (char **) p2
{
	char **p;
	int l, dd, nest;

	l = 0;
	dd = 0;
	nest = 0;
	for(p = p1; p != p2; p++) {
		if(strcmp(*p, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *p name: "do"]) {
			dd++;
			continue;
		}
		if([self wordIs: *p name: "end"]) {
			dd--;
			continue;
		}
		if(dd != 0)
			continue;
		if([self wordIs: *p name: "if"]) {
			nest++;
			continue;
		}
		if(![self wordIs: *p name: "else"])
			continue;
		if(nest != 0) {
			nest--;
			continue;
		}
		return(p);
	}
	return(0);
}

/*
 * procName
 *	the PROCEDURE word of the name: PROCEDURE header at p1,
 *	or 0 when p1 does not start one; a newline between the
 *	colon and PROCEDURE is noise, since PL/M ignores line
 *	breaks inside a header
 */
- (char **) procName: (char **) p1 end: (char **) p2
{
	char **h;

	if(p2 < p1+2 || ![self nameOk: *p1] || [self srchx: *p1] != -1 ||
	    strcmp(*(p1+1), ":") != 0)
		return(0);
	h = p1 + 2;
	while(h != p2 && **h == '\n')
		h++;
	if(h == p2 || ![self wordIs: *h name: "procedure"])
		return(0);
	return(h);
}

/*
 * statement
 *	if ( synor ) THEN synstmt
 *	if ( synor ) THEN synstmt else synstmt
 *	if synor THEN synstmt [ELSE synstmt]
 *	doStatement, below
 *
 * bodies are single line ranges; synstmt parses them so they
 * nest, chain with ; and form DO..END groups; an else past
 * any nested ifs belongs to this if, after the C shell's
 * synor; conditions run through synor rather than synasg so
 * that a PL/M = inside one compares instead of assigning
 */
- (struct Tree *) procDef: (char **) p1 end: (char **) p2
{
	register struct Tree *t;
	char **m, **e, **q, **lp, **rp, **bs;
	int n;

	/* trailing separators past END name are noise */
	e = p2;
	while(e != p1+3 && (*(e-1))[1] == '\0' &&
	    (**(e-1) == ';' || **(e-1) == '\n'))
		e--;
	m = [self matchProc: p1 end: e];
	if(m == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	/* optional parameter list right after PROCEDURE; a
	   newline after the colon or PROCEDURE is noise */
	q = [self procName: p1 end: m] + 1;
	while(q != m && **q == '\n')
		q++;
	lp = 0;
	rp = 0;
	if(q != m && strcmp(*q, "(") == 0) {
		lp = q+1;
		rp = [self matchParen: q end: m];
		if(rp == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		q = rp+1;
	}
	while(q != m && **q == '\n')
		q++;
	/* optional BYTE or ADDRESS result type */
	t = [self tree];
	t->DTYP = TPROCEDURE;
	t->DARR[0] = *p1;
	t->DARR[1] = 0;
	t->DINT = 0;
	if(q != m && ([self wordIs: *q name: "byte"] ||
	    [self wordIs: *q name: "address"])) {
		t->DARR[1] = *q;
		q++;
	}
	/* optional INTERRUPT n; such a procedure is void and
	   takes no parameters, as in PL/M-80 */
	if(q != m && [self wordIs: *q name: "interrupt"]) {
		if(lp != 0 || t->DARR[1] != 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		q++;
		if(q == m) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t->DINT = *q;
		q++;
	}
	if(q == m || strcmp(*q, ";") != 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	/* the body follows the header's closing ; */
	bs = q+1;
	n = 0;
	if(lp != 0) {
		char **seg, **pp;

		seg = lp;
		for(pp = lp; ; pp++) {
			if(pp != rp && strcmp(*pp, ",") != 0)
				continue;
			if(pp != seg+1 || ![self nameOk: *seg] ||
			    [self srchx: *seg] != -1) {
				[self error: ERR_SYNTAX code: 255];
				return(0);
			}
			if(n == MAXPARS) {
				[self error: ERR_LARGE code: 255];
				return(0);
			}
			t->DARR[3 + n++] = *seg;
			if(pp == rp)
				break;
			seg = pp+1;
		}
	}
	t->DARR[2] = strdup([self integerToASCII: n]);
	/* the body ends at END, the optional name follows */
	if(m+1 != e && ![self nameEq: *(m+1) other: *p1]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DLEF = [self synstmt: bs end: m];
	return(t);
}

/*
 * statement
 *	if ( synor ) THEN synstmt
 *	if ( synor ) THEN synstmt else synstmt
 *	if synor THEN synstmt [ELSE synstmt]
 *	doStatement, below
 *
 * bodies are single line ranges; synstmt parses them so they
 * nest, chain with ; and form DO..END groups; an else past
 * any nested ifs belongs to this if, after the C shell's
 * synor; conditions run through synor rather than synasg so
 * that a PL/M = inside one compares instead of assigning
 */
- (struct Tree *) statement: (char **) p1 end: (char **) p2
{
	register char **p;
	register char **rp;
	register char **ep;
	char **tp;
	char **bs;
	register struct Tree *t;
	int l, k, dd;

	k = [self srchx: *p1];
	if(k == TDO)
		return [self doStatement: p1 end: p2];
	if([self procName: p1 end: p2] != 0)
		return [self procDef: p1 end: p2];
	if(k == TCALL)
		return [self callStmt: p1 end: p2];
	if(k == TRETURN) {
		/* RETURN; / RETURN expr; — trailing ; dropped */
		while(p2 != p1 && (*(p2-1))[1] == '\0' &&
		    (**(p2-1) == ';' || **(p2-1) == '\n'))
			p2--;
		t = [self tree];
		t->DTYP = TRETURN;
		if(p2 > p1+1)
			t->DLEF = [self synasg: p1+1 end: p2];
		else
			t->DLEF = 0;
		return(t);
	}
	if(k == TGOTO || (k == TGO && p2 >= p1+3 &&
	    [self wordIs: *(p1+1) name: "to"])) {
		char **np;

		/* GOTO label / GO TO label; trailing separators
		   from the enclosing statement list do not count */
		while(p2 != p1 && (*(p2-1))[1] == '\0' &&
		    (**(p2-1) == ';' || **(p2-1) == '\n'))
			p2--;
		np = (k == TGOTO) ? p1+1 : p1+2;
		if(p2 != np+1 || ![self nameOk: *np] ||
		    [self srchx: *np] != -1) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t = [self tree];
		t->DTYP = TGOTO;
		t->DARR[0] = *np;
		return(t);
	}
	if(p2 >= p1+2 && strcmp(*(p1+1), "(") == 0) {
		rp = [self matchParen: p1+1 end: p2];
		if(rp == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t = [self tree];
		if(k != TIF) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t->DTYP = TIF;
		t->DLEF = [self synor: p1+2 end: rp];
		t->DSTR = 0;
		p = rp+1;
		if(p == p2 || ![self wordIs: *p name: "then"]) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		p++;
		bs = p;
		ep = [self matchElse: p end: p2];
		if(ep != 0) {
			t->DRIT = [self synstmt: bs end: ep];
			t->DSTR = [self synstmt: ep+1 end: p2];
		}
		else
			t->DRIT = [self synstmt: bs end: p2];
		return(t);
	}
	if(k != TIF) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	l = 0;
	dd = 0;
	tp = 0;
	for(p=p1+1; p!=p2; p++) {
		if(strcmp(*p, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *p name: "do"]) {
			dd++;
			continue;
		}
		if([self wordIs: *p name: "end"]) {
			dd--;
			continue;
		}
		if(dd == 0 && [self wordIs: *p name: "then"]) {
			tp = p;
			break;
		}
	}
	if(tp == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t = [self tree];
	t->DTYP = TIF;
	t->DLEF = [self synor: p1+1 end: tp];
	t->DSTR = 0;
	bs = tp+1;
	p = bs;
	ep = [self matchElse: p end: p2];
	if(ep != 0) {
		t->DRIT = [self synstmt: bs end: ep];
		t->DSTR = [self synstmt: ep+1 end: p2];
	}
	else
		t->DRIT = [self synstmt: bs end: p2];
	return(t);
}

/*
 * findSemi
 *	the first ; at depth zero in the range, or 0 when
 *	there is none
 */
- (char **) findSemi: (char **) p1 end: (char **) p2
{
	char **q;
	int l;

	l = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || strcmp(*q, ";") != 0)
			continue;
		return(q);
	}
	return(0);
}

/*
 * findTo
 *	the TO closing an iterative DO head, or 0 when the
 *	range holds none
 */
- (char **) findTo: (char **) p1 end: (char **) p2
{
	char **q;
	int l;

	l = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || ![self wordIs: *q name: "to"])
			continue;
		return(q);
	}
	return(0);
}

/*
 * skipSep
 *	first non-separator word in the range, or the end
 */
- (char **) skipSep: (char **) p1 end: (char **) p2
{
	char **p;

	for(p = p1; p != p2; p++) {
		if(strcmp(*p, ";") != 0 && strcmp(*p, "\n") != 0)
			return(p);
	}
	return(p2);
}

/*
 * splitCase
 *	each DO CASE branch parsed into stmts, returning the
 *	count or -1 after reporting overflow; separators in
 *	nested groups never split
 */
- (int) splitCase: (char **) p1 end: (char **) p2 into: (struct Tree **) stmts
{
	char **q, **seg;
	int k, l, dd;

	k = 0;
	seg = [self skipSep: p1 end: p2];
	l = 0;
	dd = 0;
	q = seg;
	while(q != p2) {
		if(strcmp(*q, "(") == 0) {
			l++;
			q++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			q++;
			continue;
		}
		if(l != 0) {
			q++;
			continue;
		}
		if([self wordIs: *q name: "do"]) {
			dd++;
			q++;
			continue;
		}
		if([self wordIs: *q name: "end"]) {
			dd--;
			q++;
			continue;
		}
		if(dd != 0 || (strcmp(*q, ";") != 0 &&
		    strcmp(*q, "\n") != 0)) {
			q++;
			continue;
		}
		if(k == ARGSIZ) {
			[self error: ERR_LARGE code: 255];
			return(-1);
		}
		stmts[k++] = [self synstmt: seg end: q];
		seg = [self skipSep: q+1 end: p2];
		q = seg;
	}
	if(seg == p2)
		return(k);
	if(k == ARGSIZ) {
		[self error: ERR_LARGE code: 255];
		return(-1);
	}
	stmts[k++] = [self synstmt: seg end: p2];
	return(k);
}

/*
 * findAssign
 *	the first := at depth zero in the range, or 0 when
 *	there is none
 */
- (char **) findAssign: (char **) p1 end: (char **) p2
{
	char **q;
	int l;

	l = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || strcmp(*q, ":=") != 0)
			continue;
		return(q);
	}
	return(0);
}

/*
 * callStmt
 *	CALL name; or CALL name(expr, ...); — a TCALL node
 *	with one TLST per argument expression in DLEF
 */
- (struct Tree *) callStmt: (char **) p1 end: (char **) p2
{
	register struct Tree *t;
	char **q, **lp, **rp;

	t = [self tree];
	t->DTYP = TCALL;
	/* trailing separators past the call tail are noise */
	while(p2 != p1 && (*(p2-1))[1] == '\0' &&
	    (**(p2-1) == ';' || **(p2-1) == '\n'))
		p2--;
	q = p1+1;
	if(q == p2 || [self srchx: *q] != -1 || ![self nameOk: *q]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DARR[0] = *q;
	q++;
	lp = 0;
	if(q != p2 && strcmp(*q, "(") == 0) {
		rp = [self matchParen: q end: p2];
		if(rp == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		lp = q+1;
		q = rp+1;
	}
	if(q != p2) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DLEF = 0;
	if(lp != 0)
		t->DLEF = [self argList: lp end: rp];
	return(t);
}

/*
 * argList
 *	split the argument range lp..rp into a source-order
 *	TLST chain, one synasg per argument; a comma inside
 *	nested parens does not separate, and an empty range
 *	has no arguments
 */
- (struct Tree *) argList: (char **) lp end: (char **) rp
{
	struct Tree *head, *tail, **link;
	char **seg, **q;
	int l;

	if(lp == rp)
		return(0);
	head = 0;
	link = &head;
	seg = lp;
	l = 0;
	for(q = lp; q != rp; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || strcmp(*q, ",") != 0)
			continue;
		tail = [self tree];
		tail->DTYP = TLST;
		tail->DLEF = [self synasg: seg end: q];
		tail->DRIT = 0;
		*link = tail;
		link = &tail->DRIT;
		seg = q+1;
	}
	tail = [self tree];
	tail->DTYP = TLST;
	tail->DLEF = [self synasg: seg end: rp];
	tail->DRIT = 0;
	*link = tail;
	return(head);
}

/*
 * literalDecl
 *	DECLARE name LITERALLY 'text': record a parse-time
 *	macro; it declares no storage and emits no code
 */
- (struct Tree *) literalDecl: (char *) na value: (char *) val
{
	struct Tree *t;
	char *d;
	unsigned char c;

	if(*macc == MACSIZ) {
		[self error: ERR_LARGE code: 255];
	}
	d = macnam[*macc];
	while(*na) {
		c = (unsigned char) *na++;
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(d >= macnam[*macc] + SYMNAMSIZ - 1)
			[self error: ERR_LARGE code: 255];
		*d++ = (char) c;
	}
	*d = '\0';
	d = macval[*macc];
	while((c = (unsigned char) *val++) != 0) {
		if(d >= macval[*macc] + MACVSIZ - 1)
			[self error: ERR_LARGE code: 255];
		*d++ = (char)(c & 0177);
	}
	*d = '\0';
	maclev[*macc] = *scope;
	(*macc)++;
	t = [self tree];
	t->DTYP = TNOP;
	return(t);
}

/*
 * macroValue
 *	the text of the innermost LITERALLY macro named na,
 *	or 0 when the name is not a macro
 */
- (char *) macroValue: (char *) na
{
	int i;

	for(i = *macc - 1; i >= 0; i--)
		if([self nameEq: macnam[i] other: na])
			return macval[i];
	return(0);
}

/*
 * resolveMacro
 *	follow a chain of LITERALLY macros from the word w
 *	to its final text; a non-macro word is returned as is
 */
- (char *) resolveMacro: (char *) w
{
	char *v;
	int guard;

	guard = 0;
	while(guard++ < MACSIZ && (v = [self macroValue: w]) != 0)
		w = v;
	return(w);
}

/*
 * doStatement
 *	DO; synstmt END
 *	DO WHILE synor; synstmt END
 *	DO variable = synor TO synor; synstmt END
 *
 * the iterative form desugars to an assignment and a
 * WHILE loop over existing node types, so no new code
 * generation is needed for it; the loop variable must
 * already be declared, after PL/M-80
 */
- (struct Tree *) doStatement: (char **) p1 end: (char **) p2
{
	char **p;
	char **m, **q, **semi, **topos;
	char *var;
	struct Tree *t, *e1, *e2, *body;
	struct Tree *v1, *v2, *v3, *v4, *n1;
	struct Tree *init, *cond, *incr, *incv, *loop, *lbody, *root;
	struct Tree *sel, *tail, *cmp, *num, *br;
	struct Tree *stmts[ARGSIZ];
	int k, i;

	m = [self matchEnd: p1 end: p2];
	if(m == 0 || [self endPast: m end: p2] == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t = [self tree];
	p = p1+1;
	if(p != m && [self wordIs: *p name: "while"]) {
		semi = [self findSemi: p+1 end: m];
		if(semi == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t->DTYP = TWHILE;
		t->DLEF = [self synor: p+1 end: semi];
		q = semi+1;
		while(q != m && (strcmp(*q, ";") == 0 || strcmp(*q, "\n") == 0))
			q++;
		t->DRIT = 0;
		if(q != m)
			t->DRIT = [self synstmt: q end: m];
		return(t);
	}
	if(p != m && [self wordIs: *p name: "case"]) {
		semi = [self findSemi: p+1 end: m];
		if(semi == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		sel = [self synor: p+1 end: semi];
		k = [self splitCase: semi+1 end: m into: stmts];
		if(k < 0)
			return(0);
		tail = 0;
		i = k;
		while(i > 0) {
			i--;
			cmp = [self tree];
			cmp->DTYP = TEQU;
			cmp->DLEF = sel;
			num = [self tree];
			num->DTYP = TNUM;
			num->DARR[0] = strdup([self integerToASCII: i]);
			cmp->DRIT = num;
			br = [self tree];
			br->DTYP = TIF;
			br->DLEF = cmp;
			br->DRIT = stmts[i];
			br->DSTR = tail;
			tail = br;
		}
		t->DTYP = TBLOCK;
		t->DLEF = tail;
		return(t);
	}
	if(p != m && strcmp(*p, ";") != 0 && strcmp(*p, "\n") != 0 &&
	    [self srchx: *p] == -1 && [self nameOk: *p] &&
	    p+1 != m && strcmp(*(p+1), "=") == 0) {
		var = *p;
		topos = [self findTo: p+2 end: m];
		if(topos == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		semi = [self findSemi: topos+1 end: m];
		if(semi == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		e1 = [self synor: p+2 end: topos];
		e2 = [self synor: topos+1 end: semi];
		q = semi+1;
		while(q != m && (strcmp(*q, ";") == 0 || strcmp(*q, "\n") == 0))
			q++;
		body = 0;
		if(q != m)
			body = [self synstmt: q end: m];
		v1 = [self tree];
		v1->DTYP = TVAR;
		v1->DARR[0] = var;
		v2 = [self tree];
		v2->DTYP = TVAR;
		v2->DARR[0] = var;
		v3 = [self tree];
		v3->DTYP = TVAR;
		v3->DARR[0] = var;
		v4 = [self tree];
		v4->DTYP = TVAR;
		v4->DARR[0] = var;
		n1 = [self tree];
		n1->DTYP = TNUM;
		n1->DARR[0] = "1";
		init = [self tree];
		init->DTYP = TASG;
		init->DLEF = v1;
		init->DRIT = e1;
		cond = [self tree];
		cond->DTYP = TLEQ;
		cond->DLEF = v2;
		cond->DRIT = e2;
		incv = [self tree];
		incv->DTYP = TADD;
		incv->DLEF = v3;
		incv->DRIT = n1;
		incr = [self tree];
		incr->DTYP = TASG;
		incr->DLEF = v4;
		incr->DRIT = incv;
		lbody = [self tree];
		lbody->DTYP = TLST;
		lbody->DLEF = body;
		lbody->DRIT = incr;
		loop = [self tree];
		loop->DTYP = TWHILE;
		loop->DLEF = cond;
		loop->DRIT = lbody;
		root = [self tree];
		root->DTYP = TLST;
		root->DLEF = init;
		root->DRIT = loop;
		return(root);
	}
	while(p != m && (strcmp(*p, ";") == 0 || strcmp(*p, "\n") == 0))
		p++;
	t->DTYP = TBLOCK;
	t->DLEF = 0;
	if(p != m)
		t->DLEF = [self synstmt: p end: m];
	return(t);
}

/*
 * synasg
 *	synor
 *	synor = synasg
 *
 * assignment is the loosest expression level and the only
 * right associative one, so it splits at the first '='
 */
- (struct Tree *) synasg: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	int l;

	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	case '=':
		if(l == 0 && (*p)[1] != '=') {
			t = [self tree];
			t->DTYP = TASG;
			t->DLEF = [self synor: p1 end: p];
			t->DRIT = [self synasg: p+1 end: p2];
			return(t);
		}
	}
	if(l == 0)
		return [self synor: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synor
 *	synand
 *	synor OR synand
 *	synor XOR synand
 *
 * OR and XOR share the lowest level, after PL/M-80
 */
- (struct Tree *) synor: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l, qc, k2;

	l = 0;
	q = 0;
	qc = 0;
	q = [self findAssign: p1 end: p2];
	if(q != 0) {
		t = [self tree];
		t->DTYP = TASG;
		t->DLEF = [self synor: p1 end: q];
		t->DRIT = [self synasg: q+1 end: p2];
		return(t);
	}
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	default:
		if(l != 0)
			continue;
		k2 = [self srchx: *p];
		if(k2 != TOR2 && k2 != TXOR)
			continue;
		qc = k2;
		q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = qc;
		t->DLEF = [self synor: p1 end: q];
		t->DRIT = [self synand: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synand: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synand
 *	synnot
 *	synand AND synnot
 */
- (struct Tree *) synand: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l;

	l = 0;
	q = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	default:
		if(l == 0 && [self srchx: *p] == TAND2)
			q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = TAND2;
		t->DLEF = [self synand: p1 end: q];
		t->DRIT = [self synnot: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synnot: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synnot
 *	syneq
 *	NOT synnot
 *
 * NOT binds below relations, so NOT a = b reads NOT (a = b);
 * like the old tight NOT it tests x == 0, needing no new
 * node type
 */
- (struct Tree *) synnot: (char **) p1 end: (char **) p2
{
	struct Tree *t, *t1;

	if(p1 == p2 || ![self wordIs: *p1 name: "not"])
		return [self syneq: p1 end: p2];
	t = [self tree];
	t->DTYP = TEQU;
	t->DLEF = [self synnot: p1+1 end: p2];
	t1 = [self tree];
	t1->DTYP = TNUM;
	t1->DARR[0] = "0";
	t->DRIT = t1;
	return(t);
}

/*
 * isOperator
 *	true if w is an operator word or an opener; a '-'
 *	or '+' coming right after one of these is unary;
 *	word operators count, after PL/M-80
 */
- (int) isOperator: (char *) w
{
	int k;

	switch(*w) {

	case '=':
	case '|':
	case '&':
	case '^':
	case '<':
	case '>':
	case '!':
	case '+':
	case '-':
	case '*':
	case '/':
	case '%':
	case '(':
		return(1);
	}
	k = [self srchx: w];
	if(k == TAND2 || k == TOR2 || k == TXOR || k == TNOT ||
	    k == TADD || k == TSUB || k == TMOD)
		return(1);
	return(0);
}

/*
 * syneq
 *	synrel
 *	syneq = synrel
 *	syneq <> synrel
 *
 * a lone = compares here; the assignment level above
 * takes statement-level = first, so the two never clash
 */
- (struct Tree *) syneq: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l, qc;

	l = 0;
	q = 0;
	qc = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	case '=':
		if(l == 0 && (*p)[1] == '\0') {
			q = p;
			qc = **p;
		}
		continue;

	case '<':
		if(l == 0 && (*p)[1] == '>') {
			q = p;
			qc = '!';
		}
		continue;
	}
	if(q != 0) {
		t = [self tree];
		if(qc == '=')
			t->DTYP = TEQU;
		else
			t->DTYP = TNEQ;
		t->DLEF = [self syneq: p1 end: q];
		t->DRIT = [self synrel: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synrel: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synrel
 *	synadd
 *	synrel < synadd
 *	synrel <= synadd
 *	synrel > synadd
 *	synrel >= synadd
 *
 * the four relational operators share one level
 */
- (struct Tree *) synrel: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l, qc, qe;

	l = 0;
	q = 0;
	qc = 0;
	qe = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	case '<':
	case '>':
		if(l == 0) {
			q = p;
			qc = **p;
			qe = (*p)[1] == '=';
		}
		continue;
	}
	if(q != 0) {
		t = [self tree];
		if(qc == '<')
			t->DTYP = qe ? TLEQ : TLSS;
		else
			t->DTYP = qe ? TGEQ : TGTR;
		t->DLEF = [self synrel: p1 end: q];
		t->DRIT = [self synadd: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synadd: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synadd
 *	synmul
 *	synadd + synmul
 *	synadd - synmul
 *	synadd PLUS synmul
 *	synadd MINUS synmul
 *
 * a '+' or '-' after another operator or opener is unary,
 * so it is left for synun instead of splitting here
 */
- (struct Tree *) synadd: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l, qc, k2;

	l = 0;
	q = 0;
	qc = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	case '+':
	case '-':
		if(l == 0 && (*p)[1] == '\0' && p != p1 && ![self isOperator: *(p-1)]) {
			q = p;
			qc = **p;
		}
		continue;

	default:
		if(l != 0)
			continue;
		k2 = [self srchx: *p];
		if(k2 != TADD && k2 != TSUB)
			continue;
		q = p;
		qc = (k2 == TADD) ? '+' : '-';
		continue;
	}
	if(q != 0) {
		t = [self tree];
		if(qc == '+')
			t->DTYP = TADD;
		else
			t->DTYP = TSUB;
		t->DLEF = [self synadd: p1 end: q];
		t->DRIT = [self synmul: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synmul: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synmul
 *	synun
 *	synmul * synun
 *	synmul / synun
 *	synmul MOD synun
 */
- (struct Tree *) synmul: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	char **q;
	int l, qc;

	l = 0;
	q = 0;
	qc = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;


	case '*':
	case '/':
		if(l == 0 && (*p)[1] == '\0' && p != p1 && ![self isOperator: *(p-1)]) {
			q = p;
			qc = **p;
		}
		continue;

	default:
		if(l == 0 && [self srchx: *p] == TMOD) {
			q = p;
			qc = '%';
		}
		continue;
	}
	if(q != 0) {
		t = [self tree];
		if(qc == '*')
			t->DTYP = TMUL;
		else if(qc == '/')
			t->DTYP = TDIV;
		else
			t->DTYP = TMOD;
		t->DLEF = [self synmul: p1 end: q];
		t->DRIT = [self synun: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synun: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synun
 *	synprim
 *	- synun
 *	+ synun
 *	* synun
 *
 * unary minus is 0 - x, so no new node type is needed;
 * NOT lives at its own level in synnot
 */
- (struct Tree *) synun: (char **) p1 end: (char **) p2
{
	register struct Tree *t;
	register struct Tree *t1;

	if(p1 != p2) {
		if(strcmp(*p1, "-") == 0) {
			t = [self tree];
			t->DTYP = TSUB;
			t1 = [self tree];
			t1->DTYP = TNUM;
			t1->DARR[0] = "0";
			t->DLEF = t1;
			t->DRIT = [self synun: p1+1 end: p2];
			return(t);
		}
		if(strcmp(*p1, "+") == 0)
			return [self synun: p1+1 end: p2];
		if(strcmp(*p1, "*") == 0) {
			t = [self tree];
			t->DTYP = TDEREF;
			t->DLEF = [self synun: p1+1 end: p2];
			return(t);
		}
	}
	return [self synprim: p1 end: p2];
}

/*
 * srchx
 *	the node type for the keyword cp, or -1 when cp is
 *	no keyword; a binary search over the alphabetical
 *	keyw table; after the C shell's srchx(); matching is
 *	case-insensitive with $ signs dropped, after PL/M-80,
 *	so INPUT, Input and IN$PUT all find the same row
 */
- (int) srchx: (char *) cp
{
	register int first, last, middle, compare;
	char cb[64];
	char *s;
	unsigned char c;
	int n;

	s = cp;
	n = 0;
	while(*s) {
		c = (unsigned char) *s++;
		if(c == '$')
			continue;
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(n >= 63)
			return(-1);
		cb[n++] = (char) c;
	}
	cb[n] = '\0';
	first = 0;
	last = sizeof keyw / sizeof *keyw - 1;
	while(first <= last) {
		middle = first + (last - first) / 2;
		compare = strcmp(cb, keyw[middle].kname);
		if(compare == 0)
			return(keyw[middle].ktype);
		if(compare < 0)
			last = middle - 1;
		else
			first = middle + 1;
	}
	return(-1);
}

/*
 * nameEq
 *	true when the words a and b spell the same name,
 *	case-insensitive with $ signs ignored
 */
- (int) nameEq: (char *) a other: (char *) b
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
 * matchProc
 *	the END word closing the PROCEDURE at p1, or 0 when
 *	the range holds none; nested DO..END groups skip
 */
- (char **) matchProc: (char **) p1 end: (char **) p2
{
	char **q;
	int l, dd;

	l = 0;
	dd = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *q name: "do"] ||
		    [self wordIs: *q name: "procedure"]) {
			dd++;
			continue;
		}
		if(dd != 0 && [self wordIs: *q name: "end"]) {
			dd--;
			if(dd == 0)
				return(q);
		}
	}
	return(0);
}

/*
 * wordIs
 *	true when the lexer word w spells the lower case
 *	name s under the same canonicalization srchx uses;
 *	quoted characters carry QUOTE bits and never match
 */
- (int) wordIs: (char *) w name: (const char *) s
{
	unsigned char c;

	if(w == 0 || s == 0)
		return(0);
	for(;;) {
		c = (unsigned char) *w;
		if(c == '$') {
			w++;
			continue;
		}
		if(c >= 'A' && c <= 'Z')
			c = c + 'a' - 'A';
		if(c != (unsigned char) *s)
			return(0);
		if(c == '\0')
			return(1);
		w++;
		s++;
	}
}

/*
 * nameOk
 *	true when na can be a declared name: a leading
 *	alphabetic, after PL/M-80 identifiers; the rest of
 *	the word is checked where it is used
 */
- (int) nameOk: (char *) na
{
	char c;

	if(na == 0)
		return(0);
	c = *na;
	if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
		return(1);
	return(0);
}

/*
 * doDepth
 *	unmatched block count in the word range; DO groups
 *	and PROCEDURE definitions both need an END, so both
 *	count; paren interiors do not count, and quoted
 *	words never match
 */
- (int) doDepth: (char **) p1 end: (char **) p2
{
	char **p;
	int d;
	int l;

	if(p2 == NULL)
		return(0);
	d = 0;
	l = 0;
	for(p=p1; p!=p2; p++) {
		if(*p == NULL)
			continue;
		if(strcmp(*p, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *p name: "do"] ||
		    [self wordIs: *p name: "procedure"])
			d++;
		else if([self wordIs: *p name: "end"])
			d--;
	}
	return(d);
}

/*
 * labelHang
 *	1 when the word range ends with a label (name :) whose
 *	statement must follow on the next line; name: alone is
 *	not a statement, so the reader keeps the line open
 */
- (int) labelHang: (char **) p1 end: (char **) p2
{
	char **p;

	if(p2 == NULL)
		return(0);
	p = p2;
	while(p != p1 && strcmp(*(p-1), "\n") == 0)
		p--;
	if(p - p1 < 2)
		return(0);
	return(strcmp(*(p-1), ":") == 0 && [self nameOk: *(p-2)] &&
	    [self srchx: *(p-2)] == -1);
}

/*
 * matchEnd
 *	the END word closing the DO at p1, or 0 when the
 *	range holds none; nested DO..END pairs are skipped
 */
- (char **) matchEnd: (char **) p1 end: (char **) p2
{
	char **p;
	int dd;
	int l;

	dd = 0;
	l = 0;
	for(p=p1; p!=p2; p++) {
		if(*p == NULL)
			continue;
		if(strcmp(*p, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *p name: "do"] ||
		    [self wordIs: *p name: "procedure"]) {
			dd++;
			continue;
		}
		if(![self wordIs: *p name: "end"])
			continue;
		dd--;
		if(dd != 0)
			continue;
		return(p);
	}
	return(0);
}

/*
 * endPast
 *	the position just past the END at m, its optional
 *	module name and the trailing ; and newlines, or 0
 *	when other tokens follow; M: DO .. END M; is the
 *	module wrapper the reference compiler expects
 */
- (char **) endPast: (char **) m end: (char **) p2
{
	char **ep;

	ep = p2;
	while(ep != m+1 && (*(ep-1))[1] == '\0' &&
	    (**(ep-1) == ';' || **(ep-1) == '\n'))
		ep--;
	if(ep != m+1 && [self nameOk: *(ep-1)] &&
	    [self srchx: *(ep-1)] == -1)
		ep--;
	while(ep != m+1 && (*(ep-1))[1] == '\0' &&
	    (**(ep-1) == ';' || **(ep-1) == '\n'))
		ep--;
	if(ep != m+1)
		return(0);
	return(ep);
}

/*
 * findComma
 *	first comma at depth zero in the range, or 0 when
 *	there is none
 */
- (char **) findComma: (char **) p1 end: (char **) p2
{
	char **q;
	int l;

	l = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || strcmp(*q, ",") != 0)
			continue;
		return(q);
	}
	return(0);
}

/*
 * findPlus
 *	first + or PLUS at depth zero in the range, or 0
 */
- (char **) findPlus: (char **) p1 end: (char **) p2
{
	char **q;
	int l;

	l = 0;
	for(q = p1; q != p2; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if((**q == '+' && (*q)[1] == '\0') ||
		    [self wordIs: *q name: "plus"])
			return(q);
	}
	return(0);
}

/*
 * call
 *	an INPUT or OUTPUT node around the argument syntax
 */
- (struct Tree *) call: (int) k args: (char **) lp end: (char **) rp
{
	struct Tree *t;

	t = [self tree];
	t->DTYP = k;
	if([self findComma: lp end: rp] != 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DLEF = [self synasg: lp end: rp];
	return(t);
}

/*
 * call2
 *	a two-argument built-in node split on the depth-zero
 *	comma, so nested calls keep working
 */
- (struct Tree *) call2: (int) k args: (char **) lp end: (char **) rp
{
	struct Tree *t;
	char **q;

	t = [self tree];
	t->DTYP = k;
	q = [self findComma: lp end: rp];
	if(q == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DLEF = [self synasg: lp end: q];
	if([self findComma: q+1 end: rp] != 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DRIT = [self synasg: q+1 end: rp];
	return(t);
}

/*
 * callDec
 *	DEC(a + b) or DEC(a PLUS b) as an addition subtree
 *	ready for the decimal adjust
 */
- (struct Tree *) callDec: (char **) lp end: (char **) rp
{
	struct Tree *t, *add;
	char **q;

	t = [self tree];
	t->DTYP = TDEC;
	q = [self findPlus: lp end: rp];
	if(q == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	add = [self tree];
	add->DTYP = TADD;
	add->DLEF = [self synadd: lp end: q];
	add->DRIT = [self synmul: q+1 end: rp];
	t->DLEF = add;
	return(t);
}

/*
 * stripDollar
 *	drop the $ signs read for show in a number, in place
 */
- (void) stripDollar: (char *) s
{
	char *a, *b;

	a = s;
	b = s;
	while(*a != '\0') {
		if(*a == '$') {
			a++;
			continue;
		}
		*b = *a;
		b++;
		a++;
	}
	*b = '\0';
}

/*
 * numberValue
 *	the machine value of a PL/M numeric word, or -1 when
 *	it is not one; radix suffixes B O Q D H and $ signs
 *	are honored, after the constants rules
 */
- (int) numberValue: (char *) s
{
	char buf[64];
	char c;
	int n, radix, v, i, d;

	n = 0;
	for(i = 0; s[i] != '\0'; i++) {
		if(s[i] == '$')
			continue;
		if(n >= 63)
			return(-1);
		buf[n++] = s[i];
	}
	buf[n] = '\0';
	if(n == 0)
		return(-1);
	c = buf[n-1];
	if(c >= 'a' && c <= 'z')
		c = c - 'a' + 'A';
	radix = 10;
	if(c == 'H')
		radix = 16;
	else if(c == 'B')
		radix = 2;
	else if(c == 'O' || c == 'Q')
		radix = 8;
	if(c == 'B' || c == 'O' || c == 'Q' ||
	    c == 'D' || c == 'H') {
		n--;
		buf[n] = '\0';
		if(n == 0)
			return(-1);
	}
	if(buf[0] < '0' || buf[0] > '9')
		return(-1);
	v = 0;
	for(i = 0; i < n; i++) {
		c = buf[i];
		if(c >= '0' && c <= '9')
			d = c - '0';
		else if(c >= 'a' && c <= 'f')
			d = c - 'a' + 10;
		else if(c >= 'A' && c <= 'F')
			d = c - 'A' + 10;
		else
			d = -1;
		if(d < 0 || d >= radix)
			return(-1);
		v = v * radix + d;
		if(v > 0xFFFF)
			return(-1);
	}
	return(v);
}

/*
 * groupDecl
 *	DECLARE (a, b, ...) type as chained declaration
 *	nodes; every item must be one plain name
 */
- (struct Tree *) groupDecl: (char **) p1 args: (char **) lp end: (char **) rp
{
	struct Tree *t, *rest, *d;
	char *names[ARGSIZ];
	char **q, **seg;
	int k, l, type;

	type = TDECL;
	if([self wordIs: p1[1] name: "address"])
		type = TADDR;
	else if(![self wordIs: p1[1] name: "byte"]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	k = 0;
	seg = lp;
	l = 0;
	for(q = lp; q != rp; q++) {
		if(strcmp(*q, "(") == 0) {
			l++;
			continue;
		}
		if(strcmp(*q, ")") == 0) {
			l--;
			continue;
		}
		if(l != 0 || strcmp(*q, ",") != 0)
			continue;
		if(q == seg || q != seg+1 ||
		    [self srchx: *seg] != -1 || ![self nameOk: *seg]) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		if(k == ARGSIZ) {
			[self error: ERR_LARGE code: 255];
			return(0);
		}
		names[k++] = *seg;
		seg = q+1;
	}
	if(seg == rp || rp != seg+1 ||
	    [self srchx: *seg] != -1 || ![self nameOk: *seg]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if(k == ARGSIZ) {
		[self error: ERR_LARGE code: 255];
		return(0);
	}
	names[k++] = *seg;
	t = 0;
	while(k > 0) {
		k--;
		d = [self tree];
		d->DTYP = type;
		d->DARR[0] = names[k];
		if(t == 0)
			t = d;
		else {
			rest = [self tree];
			rest->DTYP = TLST;
			rest->DLEF = d;
			rest->DRIT = t;
			t = rest;
		}
	}
	return(t);
}

/*
 * arrayDecl
 *	DECLARE name (size) BYTE as a TARRAY node; ADDRESS
 *	arrays need 16-bit values and stay an error
 */
- (struct Tree *) arrayDecl: (char **) p1 args: (char **) lp end: (char **) rp
{
	struct Tree *t;
	int size, elsz;

	if(![self wordIs: p1[2] name: "byte"] &&
	    ![self wordIs: p1[2] name: "address"]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if(rp != lp+1) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	lp[0] = [self resolveMacro: *lp];
	size = [self numberValue: *lp];
	if(size < 1) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	elsz = [self wordIs: p1[2] name: "address"] ? 2 : 1;
	if(size > 255 || size * elsz > RAMSIZE) {
		[self error: ERR_LARGE code: 255];
		return(0);
	}
	t = [self tree];
	t->DTYP = TARRAY;
	t->DARR[0] = p1[1];
	t->DARR[1] = *lp;
	if(elsz == 2)
		t->DARR[2] = "address";
	return(t);
}

/*
 * stringBytes
 *	emit a quoted word (QUOTE-flagged characters from
 *	the lexer) as a list of byte values
 */
- (void) stringBytes: (char *) s
{
	unsigned char c;
	int first;

	first = 1;
	while((c = (unsigned char) *s++) != 0) {
		c &= 0177;
		if(!first)
			printf(",");
		printf("%d", c);
		first = 0;
	}
}

/*
 * collectValues
 *	depth-zero comma split between lp and rp; each
 *	one-word constant lands in out[]; strings arrive
 *	QUOTE-flagged; returns the count
 */
- (int) collectValues: (char **) lp end: (char **) rp into: (char **) dst
{
	char **q, **c;
	int n;

	n = 0;
	for(c = lp; ; ) {
		q = [self findComma: c end: rp];
		if(q == 0)
			q = rp;
		if(q == c) {
			[self error: ERR_SYNTAX code: 255];
			return(-1);
		}
		if(q - c != 1) {
			[self error: ERR_SYNTAX code: 255];
			return(-1);
		}
		if(n == ARGSIZ) {
			[self error: ERR_LARGE code: 255];
			return(-1);
		}
		dst[n++] = [self resolveMacro: *c];
		if(q == rp)
			return(n);
		c = q+1;
	}
}

/*
 * dataDecl
 *	DECLARE name [BYTE] DATA (const, ...) as a TDATA
 *	node; every data constant goes in DARR[1..]
 */
- (struct Tree *) dataDecl: (char **) p1 args: (char **) lp end: (char **) rp
{
	struct Tree *t;
	int n;

	t = [self tree];
	t->DTYP = TDATA;
	t->DARR[0] = p1[1];
	n = [self collectValues: lp end: rp into: t->DARR + 1];
	if(n < 0)
		return(0);
	return(t);
}

/*
 * initialDecl
 *	DECLARE name [(n)] type INITIAL (const, ...) as
 *	TINITIAL; DARR holds name, size word, type word,
 *	item-count word, then each preset constant
 */
- (struct Tree *) initialDecl: (char **) p1 count: (int) n args: (char **) lp end: (char **) rp args2: (char **) lp2 end: (char **) rp2
{
	struct Tree *t;
	int i, m;

	t = [self tree];
	t->DTYP = TINITIAL;
	t->DARR[0] = p1[1];
	i = 1;
	if(lp == 0)
		t->DARR[i++] = 0;
	else
		t->DARR[i++] = [self resolveMacro: *lp];
	if(n >= 4) {
		if([self wordIs: p1[n-2] name: "byte"])
			t->DARR[i++] = 0;
		else if([self wordIs: p1[n-2] name: "address"])
			t->DARR[i++] = "address";
		else {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
	}
	else
		t->DARR[i++] = 0;
	m = [self collectValues: lp2 end: rp2 into: t->DARR + 4];
	if(m < 0)
		return(0);
	t->DARR[i] = strdup([self integerToASCII: m]);
	return(t);
}

/*
 * subscript
 *	name(index) as a TSUBSCRIPT node; declaredness is
 *	checked at compile time, like TVAR, so declaring
 *	and using in one batch keeps working
 */
- (struct Tree *) subscript: (char *) na args: (char **) lp end: (char **) rp
{
	struct Tree *t;

	t = [self tree];
	t->DTYP = TSUBSCRIPT;
	t->DARR[0] = na;
	t->DLEF = [self argList: lp end: rp];
	return(t);
}

/*
 * arrayInfo
 *	LENGTH(name) or LAST(name); the count is known at
 *	compile time, like TVAR lookup
 */
- (struct Tree *) arrayInfo: (int) k args: (char **) lp end: (char **) rp
{
	struct Tree *t;

	if(rp != lp+1 || ![self nameOk: *lp]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t = [self tree];
	t->DTYP = k;
	t->DARR[0] = *lp;
	return(t);
}

/*
 * synprim
 *	( synstmt )
 *	keyword
 *	literal
 *	variable
 */
- (struct Tree *) synprim: (char **) p1 end: (char **) p2
{
	register char **p;
	char **lp, **rp, **lp2, **rp2;
	register struct Tree *t;
	char *w[ARGSIZ];
	int n, l, k;

	lp = 0;
	rp = 0;
	lp2 = 0;
	rp2 = 0;
	n = 0;
	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		if(l == 0) {
			if(lp == 0)
				lp = p+1;
			else if(lp2 == 0)
				lp2 = p+1;
			else
				[self error: ERR_SYNTAX code: 255];
		}
		l++;
		continue;

	case ')':
		l--;
		if(l == 0 && rp != 0)
			rp2 = p;
		if(l == 0 && rp == 0)
			rp = p;
		continue;

	default:
		if(l == 0 && **p != '\n')
			w[n++] = *p;
	}
	if(lp != 0) {
		if(n == 1)
			k = [self srchx: w[0]];
		else
			k = -1;
		if(k == TINPUT || k == TOUTPUT || k == TLOW ||
		    k == THIGH || k == TDOUBLE || k == TTIME)
			return [self call: k args: lp end: rp];
		if(k == TSHL || k == TSHR || k == TROL ||
		    k == TROR || k == TSCL || k == TSCR)
			return [self call2: k args: lp end: rp];
		if(k == TDEC)
			return [self callDec: lp end: rp];
		if(n == 1 && (k == TLENGTH || k == TLAST))
			return [self arrayInfo: k args: lp end: rp];
		if(n == 1 && k == -1)
			return [self subscript: w[0] args: lp end: rp];
		if(n == 3 && [self srchx: w[0]] == TDECL &&
		    ([self wordIs: w[2] name: "byte"] ||
		     [self wordIs: w[2] name: "address"]))
			return [self arrayDecl: w args: lp end: rp];
		if(n == 2 && [self srchx: w[0]] == TDECL)
			return [self groupDecl: w args: lp end: rp];
		if(n >= 3 && [self srchx: w[0]] == TDECL &&
		    [self wordIs: w[n-1] name: "data"]) {
			if(lp2 != 0)
				return [self dataDecl: w args: lp2 end: rp2];
			return [self dataDecl: w args: lp end: rp];
		}
		if(n >= 3 && [self srchx: w[0]] == TDECL &&
		    [self wordIs: w[n-1] name: "initial"]) {
			if(lp2 != 0)
				return [self initialDecl: w count: n
				    args: lp end: rp args2: lp2 end: rp2];
			return [self initialDecl: w count: n
			    args: 0 end: 0 args2: lp end: rp];
		}
		if(n != 0)
			[self error: ERR_SYNTAX code: 255];
		t = [self tree];
		t->DTYP = TPAR;
		t->DSTR = [self synstmt: lp end: rp];
		return(t);
	}
	if(n == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	/* a single word that names a LITERALLY macro stands
	   for its text; chains of macros resolve in place */
	if(n == 1)
		w[0] = [self resolveMacro: w[0]];
	switch(k = [self srchx: w[0]]) {

	case TDECL:
		/* DECLARE name LITERALLY 'text' defines a macro */
		if(n == 4 && [self wordIs: w[2] name: "literally"]) {
			if([self srchx: w[1]] != -1 ||
			    ![self nameOk: w[1]]) {
				[self error: ERR_SYNTAX code: 255];
				return(0);
			}
			return [self literalDecl: w[1] value: w[3]];
		}
		/* DECLARE name BYTE, DECLARE name ADDRESS, and
		   the comma-split DECLARE a type, b type, ... */
		if(n > 3) {
			struct Tree *seg[ARGSIZ], *dl;
			int i, nc, isbyte;

			nc = 0;
			for(i = 1; i < n; ) {
				if(i + 1 >= n || ![self nameOk: w[i]] ||
				    [self srchx: w[i]] != -1 ||
				    strcmp(w[i], ",") == 0) {
					[self error: ERR_SYNTAX code: 255];
					return(0);
				}
				isbyte = [self wordIs: w[i+1] name: "byte"];
				if(!isbyte &&
				    ![self wordIs: w[i+1] name: "address"]) {
					[self error: ERR_SYNTAX code: 255];
					return(0);
				}
				if(nc == ARGSIZ) {
					[self error: ERR_LARGE code: 255];
					return(0);
				}
				dl = [self tree];
				dl->DTYP = isbyte ? TDECL : TADDR;
				dl->DARR[0] = w[i];
				seg[nc++] = dl;
				i += 2;
				if(i == n)
					break;
				if(strcmp(w[i], ",") != 0) {
					[self error: ERR_SYNTAX code: 255];
					return(0);
				}
				i++;
			}
			dl = 0;
			while(nc > 0) {
				nc--;
				t = [self tree];
				t->DTYP = TLST;
				t->DLEF = seg[nc];
				t->DRIT = dl;
				dl = t;
			}
			return(dl);
		}
		if(n != 3) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		if([self srchx: w[1]] != -1 || ![self nameOk: w[1]]) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t = [self tree];
		if([self wordIs: w[2] name: "byte"])
			t->DTYP = TDECL;
		else if([self wordIs: w[2] name: "address"])
			t->DTYP = TADDR;
		else if([self wordIs: w[2] name: "label"]) {
			/* a label declares no storage: its address
			   is the statement that carries the name */
			t->DTYP = TNOP;
			t->DARR[0] = w[1];
			return(t);
		}
		else {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t->DARR[0] = w[1];
		return(t);

	case TADDR:
		[self error: ERR_SYNTAX code: 255];
		return(0);

	case TDISABLE:
	case TENABLE:
	case THALT:
		if(n != 1) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t = [self tree];
		t->DTYP = k;
		return(t);

	case TIF:
	case TWHILE:
	case TELSE:
	case TDO:
	case TEND:
	case TCASE:
	case TTHEN:
	case TTO:
	case TNOT:
	case TBYTE:
	case TAND2:
	case TOR2:
	case TXOR:
	case TMOD:
	case TADD:
	case TSUB:
	case TSHL:
	case TSHR:
	case TROL:
	case TROR:
	case TSCL:
	case TSCR:
	case TTIME:
	case TDEC:
	case TLOW:
	case THIGH:
	case TDOUBLE:
	case TLENGTH:
	case TLAST:
	case TGOTO:
	case TGO:
	case TLABEL:
	case TCALL:
	case TPROCEDURE:
	case TRETURN:
	case TDATA:
	case TINITIAL:
	case TLITERAL:
	case TINTERRUPT:
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if((w[0][0] >= '0' && w[0][0] <= '9') ||
	    (w[0][0] == '-' && w[0][1] >= '0' && w[0][1] <= '9')) {
		if(n != 1) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		/* $ signs read for show in numbers are dropped */
		[self stripDollar: w[0]];
		t = [self tree];
		t->DTYP = TNUM;
		t->DARR[0] = w[0];
		return(t);
	}
	if([self anyCharacter: w[0][0] in: ",=|&^<>!+-*/%~{}:"]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if(n != 1) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t = [self tree];
	t->DTYP = TVAR;
	for(l=0; l<n; l++)
		t->DARR[l] = w[l];
	return(t);
}

- (struct Tree *) tree
{
	if(*treec == TRESIZ) {
		[self error: "Command line overflow" code: 255];
	}
	return(&trebuf[(*treec)++]);
}
@end
