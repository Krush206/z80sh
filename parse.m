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
 *	syn1
 */
- (struct Tree *) syntax: (char **) p1 end: (char **) p2
{
	while(p1 != p2) {
		if([self anyCharacter: **p1 in: ";\n"])
			p1++;
		else
			return [self syn1: p1 end: p2];
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
	register char **ep;
	register int k;

	if(p1 == p2)
		return(0);
	k = [self srchx: *p1];
	if(k == TIF)
		return [self statement: p1 end: p2];
	if(k == TDO) {
		char **m;

		/* a DO range parses only through its matching END */
		m = [self matchEnd: p1 end: p2];
		if(m == 0)
			return(0);
		ep = p2;
		while(ep != m+1 && (*(ep-1))[1] == '\0' &&
		    (**(ep-1) == ';' || **(ep-1) == '\n'))
			ep--;
		if(ep != m+1)
			return(0);
		return [self statement: p1 end: m+1];
	}
	return(0);
}

/*
 * syn1
 *	syn2
 *	syn2 ; syntax
 *
 *	; and newline split at depth zero, where depth counts
 *	parens and DO..END pairs alike, so no DO group ever
 *	splits in the middle
 */
/*
 * splitList
 *	the TLST node for a syn1 split at p: the head runs
 *	through headparse, falling back to syn2, and the
 *	rest through syntax
 */
- (struct Tree *) splitList: (char **) p1 at: (char **) p end: (char **) p2
{
	register struct Tree *t, *t1;

	t = [self tree];
	t->DTYP = TLST;
	t->DLEF = [self headparse: p1 end: p];
	if(t->DLEF == 0)
		t->DLEF = [self syn2: p1 end: p];
	t1 = [self syntax: p+1 end: p2];
	if(t1 != 0)
		t->DRIT = t1;
	else
		t->DRIT = 0;
	return(t);
}

/*
 * syn1
 *	syn2
 *	syn2 ; syntax
 *
 *	; and newline split at depth zero, where depth counts
 *	parens and DO..END pairs alike, so no DO group ever
 *	splits in the middle
 */
- (struct Tree *) syn1: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	int l, dd;

	l = 0;
	dd = 0;
	if(p1 != p2) {
		t = [self headparse: p1 end: p2];
		if(t != 0)
			return(t);
	}
	for(p=p1; p!=p2; p++) {
		if(l == 0 && [self wordIs: *p name: "do"])
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
		return [self syn2: p1 end: p2];
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
 * statement
 *	if ( syn3 ) THEN syn1
 *	if ( syn3 ) THEN syn1 else syn1
 *	if syn3 THEN syn1 [ELSE syn1]
 *	doStatement, below
 *
 * bodies are single line ranges; syn1 parses them so they
 * nest, chain with ; and form DO..END groups; an else past
 * any nested ifs belongs to this if, after the C shell's
 * syn3; conditions run through syn3 rather than syn2 so
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
		t->DLEF = [self syn3: p1+2 end: rp];
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
			t->DRIT = [self syn1: bs end: ep];
			t->DSTR = [self syn1: ep+1 end: p2];
		}
		else
			t->DRIT = [self syn1: bs end: p2];
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
	t->DLEF = [self syn3: p1+1 end: tp];
	t->DSTR = 0;
	bs = tp+1;
	p = bs;
	ep = [self matchElse: p end: p2];
	if(ep != 0) {
		t->DRIT = [self syn1: bs end: ep];
		t->DSTR = [self syn1: ep+1 end: p2];
	}
	else
		t->DRIT = [self syn1: bs end: p2];
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
		stmts[k++] = [self syn1: seg end: q];
		seg = [self skipSep: q+1 end: p2];
		q = seg;
	}
	if(seg == p2)
		return(k);
	if(k == ARGSIZ) {
		[self error: ERR_LARGE code: 255];
		return(-1);
	}
	stmts[k++] = [self syn1: seg end: p2];
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
 * doStatement
 *	DO; syn1 END
 *	DO WHILE syn3; syn1 END
 *	DO variable = syn3 TO syn3; syn1 END
 *
 * the iterative form desugars to an assignment and a
 * WHILE loop over existing node types, so no new code
 * generation is needed for it; the loop variable must
 * already be declared, after PL/M-80
 */
- (struct Tree *) doStatement: (char **) p1 end: (char **) p2
{
	char **p;
	char **m, **q, **semi, **topos, **ep;
	char *var;
	struct Tree *t, *e1, *e2, *body;
	struct Tree *v1, *v2, *v3, *v4, *n1;
	struct Tree *init, *cond, *incr, *incv, *loop, *lbody, *root;
	struct Tree *sel, *tail, *cmp, *num, *br;
	struct Tree *stmts[ARGSIZ];
	int k, i;

	m = [self matchEnd: p1 end: p2];
	if(m == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	ep = p2;
	while(ep != m+1 && (*(ep-1))[1] == '\0' &&
	    (**(ep-1) == ';' || **(ep-1) == '\n'))
		ep--;
	if(ep != m+1) {
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
		t->DLEF = [self syn3: p+1 end: semi];
		q = semi+1;
		while(q != m && (strcmp(*q, ";") == 0 || strcmp(*q, "\n") == 0))
			q++;
		t->DRIT = [self syn1: q end: m];
		return(t);
	}
	if(p != m && [self wordIs: *p name: "case"]) {
		semi = [self findSemi: p+1 end: m];
		if(semi == 0) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		sel = [self syn3: p+1 end: semi];
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
		e1 = [self syn3: p+2 end: topos];
		e2 = [self syn3: topos+1 end: semi];
		q = semi+1;
		while(q != m && (strcmp(*q, ";") == 0 || strcmp(*q, "\n") == 0))
			q++;
		body = [self syn1: q end: m];
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
	t->DLEF = [self syn1: p end: m];
	return(t);
}

/*
 * syn2
 *	syn3
 *	syn3 = syn2
 *
 * assignment is the loosest expression level and the only
 * right associative one, so it splits at the first '='
 */
- (struct Tree *) syn2: (char **) p1 end: (char **) p2
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
			t->DLEF = [self syn3: p1 end: p];
			t->DRIT = [self syn2: p+1 end: p2];
			return(t);
		}
	}
	if(l == 0)
		return [self syn3: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * syn3
 *	syn4
 *	syn3 OR syn4
 *	syn3 XOR syn4
 *
 * OR and XOR share the lowest level, after PL/M-80
 */
- (struct Tree *) syn3: (char **) p1 end: (char **) p2
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
		t->DLEF = [self syn3: p1 end: q];
		t->DRIT = [self syn2: q+1 end: p2];
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
		t->DLEF = [self syn3: p1 end: q];
		t->DRIT = [self syn4: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self syn4: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * syn4
 *	synnot
 *	syn4 AND synnot
 */
- (struct Tree *) syn4: (char **) p1 end: (char **) p2
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
		t->DLEF = [self syn4: p1 end: q];
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
 *	syn7
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
	return [self syn7: p1 end: p2];
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
 *	unmatched DO count in the word range; paren interiors
 *	do not count, and quoted words never match
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
		if([self wordIs: *p name: "do"])
			d++;
		else if([self wordIs: *p name: "end"])
			d--;
	}
	return(d);
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
		if([self wordIs: *p name: "do"]) {
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
	t->DLEF = [self syn2: lp end: rp];
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
	t->DLEF = [self syn2: lp end: q];
	if([self findComma: q+1 end: rp] != 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t->DRIT = [self syn2: q+1 end: rp];
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
	int size;

	if([self wordIs: p1[2] name: "address"]) {
		[self error: "ADDRESS arrays need 16-bit values" code: 255];
		return(0);
	}
	if(![self wordIs: p1[2] name: "byte"]) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if(rp != lp+1) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	size = [self numberValue: *lp];
	if(size < 1) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	t = [self tree];
	t->DTYP = TARRAY;
	t->DARR[0] = p1[1];
	t->DARR[1] = *lp;
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
	t->DLEF = [self syn2: lp end: rp];
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
 * syn7
 *	( syn1 )
 *	keyword
 *	literal
 *	variable
 */
- (struct Tree *) syn7: (char **) p1 end: (char **) p2
{
	register char **p;
	char **lp, **rp;
	register struct Tree *t;
	char *w[ARGSIZ];
	int n, l, k;

	lp = 0;
	rp = 0;
	n = 0;
	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		if(l == 0 && lp != 0)
			[self error: ERR_SYNTAX code: 255];
		if(l == 0)
			lp = p+1;
		l++;
		continue;

	case ')':
		l--;
		if(l == 0)
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
		if(n == 3 && [self srchx: w[0]] == TDECL)
			return [self arrayDecl: w args: lp end: rp];
		if(n == 2 && [self srchx: w[0]] == TDECL)
			return [self groupDecl: w args: lp end: rp];
		if(n != 0)
			[self error: ERR_SYNTAX code: 255];
		t = [self tree];
		t->DTYP = TPAR;
		t->DSTR = [self syn1: lp end: rp];
		return(t);
	}
	if(n == 0) {
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	switch(k = [self srchx: w[0]]) {

	case TDECL:
		/* DECLARE name BYTE, DECLARE name ADDRESS */
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
