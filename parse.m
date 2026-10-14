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
	{ "declare", TDECL },
	{ "disable", TDISABLE },
	{ "do", TDO },
	{ "else", TELSE },
	{ "enable", TENABLE },
	{ "end", TEND },
	{ "halt", THALT },
	{ "if", TIF },
	{ "input", TINPUT },
	{ "minus", TSUB },
	{ "mod", TMOD },
	{ "not", TNOT },
	{ "or", TOR2 },
	{ "output", TOUTPUT },
	{ "plus", TADD },
	{ "then", TTHEN },
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
 */
- (struct Tree *) syn3: (char **) p1 end: (char **) p2
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
		if(l == 0 && [self srchx: *p] == TOR2)
			q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = TOR2;
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
 *	synxor
 *	syn4 AND synxor
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
		t->DRIT = [self synxor: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synxor: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
}

/*
 * synxor
 *	syneq
 *	synxor XOR syneq
 */
- (struct Tree *) synxor: (char **) p1 end: (char **) p2
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
		if(l == 0 && [self srchx: *p] == TXOR)
			q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = TXOR;
		t->DLEF = [self synxor: p1 end: q];
		t->DRIT = [self syneq: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self syneq: p1 end: p2];
	[self error: ERR_SYNTAX code: 255];
	return(0);
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
 *	NOT synun
 *
 * unary minus is 0 - x, logical not is x == 0, so no
 * new node types are needed for them
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
		if([self wordIs: *p1 name: "not"]) {
			t = [self tree];
			t->DTYP = TEQU;
			t->DLEF = [self synun: p1+1 end: p2];
			t1 = [self tree];
			t1->DTYP = TNUM;
			t1->DARR[0] = "0";
			t->DRIT = t1;
			return(t);
		}
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
 * call
 *	an INPUT or OUTPUT node around the argument syntax
 */
- (struct Tree *) call: (int) k args: (char **) lp end: (char **) rp
{
	struct Tree *t;

	t = [self tree];
	t->DTYP = k;
	t->DLEF = [self syn2: lp end: rp];
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
			p1[n++] = *p;
	}
	if(lp != 0) {
		if(n == 1)
			k = [self srchx: p1[0]];
		else
			k = -1;
		if(k == TINPUT || k == TOUTPUT)
			return [self call: k args: lp end: rp];
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
	switch(k = [self srchx: p1[0]]) {

	case TDECL:
		/* DECLARE name BYTE, DECLARE name ADDRESS */
		if(n != 3) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		if([self srchx: p1[1]] != -1 || ![self nameOk: p1[1]]) {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t = [self tree];
		if([self wordIs: p1[2] name: "byte"])
			t->DTYP = TDECL;
		else if([self wordIs: p1[2] name: "address"])
			t->DTYP = TADDR;
		else {
			[self error: ERR_SYNTAX code: 255];
			return(0);
		}
		t->DARR[0] = p1[1];
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
		[self error: ERR_SYNTAX code: 255];
		return(0);
	}
	if((p1[0][0] >= '0' && p1[0][0] <= '9') ||
	    (p1[0][0] == '-' && p1[0][1] >= '0' && p1[0][1] <= '9')) {
		/* $ signs read for show in numbers are dropped */
		[self stripDollar: p1[0]];
		t = [self tree];
		t->DTYP = TNUM;
		t->DARR[0] = p1[0];
		return(t);
	}
	if([self anyCharacter: p1[0][0] in: "=|&^<>!+-*/%~{}"]) {
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
		t->DARR[l] = p1[l];
	return(t);
}

- (struct Tree *) tree
{
	if(*treec == TRESIZ) {
		[self error: "Command line overflow" code: 255];
		exit(255);
	}
	return(&trebuf[(*treec)++]);
}
@end
