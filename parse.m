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
	{ "int", TDECL },
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
 * braceDepth
 *	unmatched { count in the word range; quoted braces
 *	carry QUOTE bits and never match; a null end means
 *	no words yet, which counts as balanced
 */
- (int) braceDepth: (char **) p1 end: (char **) p2
{
	register char **p;
	register int d;

	if(p2 == NULL)
		return(0);
	d = 0;
	for(p=p1; p!=p2; p++)
		if(*p != NULL) {
			if(strcmp(*p, "{") == 0)
				d++;
			else if(strcmp(*p, "}") == 0)
				d--;
		}
	return(d);
}

/*
 * headparse
 *	statement or { } block at p1, or 0 when p1 starts
 *	an expression; trailing ; and newlines past the
 *	closing } do not count, so block; rest splits right
 */
- (struct Tree *) headparse: (char **) p1 end: (char **) p2
{
	register char **ep;
	register char **qp;
	register struct Tree *t;
	register int k;

	if(p1 == p2)
		return(0);
	k = [self srchx: *p1];
	if(k == TIF || k == TWHILE)
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
	if(**p1 != '{' || (*p1)[1] != '\0')
		return(0);
	ep = p2;
	while(ep != p1+1 && (*(ep-1))[1] == '\0' &&
	    (**(ep-1) == ';' || **(ep-1) == '\n'))
		ep--;
	if(ep == p1+1 || **(ep-1) != '}' || (*(ep-1))[1] != '\0')
		return(0);
	if(p1+1 == ep-1) {
		t = [self tree];
		t->DTYP = TBLOCK;
		t->DLEF = 0;
		return(t);
	}
	qp = p1+1;
	while(qp != ep-1 && (*qp)[1] == '\0' &&
	    (**qp == ';' || **qp == '\n'))
		qp++;
	if(qp == ep-1) {
		t = [self tree];
		t->DTYP = TBLOCK;
		t->DLEF = 0;
		return(t);
	}
	t = [self tree];
	t->DTYP = TBLOCK;
	t->DLEF = [self syn1: qp end: ep-1];
	return(t);
}

/*
 * syn1
 *	syn2
 *	syn2 ; syntax
 *
 *	; and newline split at depth zero, where depth counts
 *	parens, braces and DO..END pairs alike, so neither a
 *	block nor a DO group ever splits in the middle
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
		if(l == 0) {
			if([self wordIs: *p name: "do"])
				dd++;
			else if([self wordIs: *p name: "end"])
				dd--;
		}
		switch(**p) {

		case '(':
			l++;
			continue;

		case ')':
			l--;
			continue;

		case '{':
			l++;
			continue;

		case '}':
			l--;
			continue;

		case ';':
		case '\n':
			if(l == 0 && dd == 0) {
				register struct Tree *t1;

				t = [self tree];
				t->DTYP = TLST;
				t->DLEF = [self headparse: p1 end: p];
				if(t->DLEF == 0)
					t->DLEF = [self syn2: p1 end: p];
				if((t1 = [self syntax: p+1 end: p2]))
					t->DRIT = t1;
				else
					t->DRIT = 0;
				return(t);
			}
		}
	}
	if(l == 0 && dd == 0)
		return [self syn2: p1 end: p2];
	(*error)++;
	return(0);
}

/*
 * statement
 *	if ( syn3 ) [THEN] syn1
 *	if ( syn3 ) [THEN] syn1 else syn1
 *	if syn3 THEN syn1 [ELSE syn1]
 *	while ( syn3 ) [THEN] syn1
 *	doStatement, below
 *
 * bodies are single line ranges; syn1 parses them so they
 * nest, chain with ; and form { } blocks; an else past any
 * nested ifs belongs to this if, after the C shell's syn3;
 * conditions run through syn3 rather than syn2 so that a
 * PL/M = inside one compares instead of assigning
 */
- (struct Tree *) statement: (char **) p1 end: (char **) p2
{
	register char **p;
	register char **rp;
	register char **ep;
	char **tp;
	char **bs;
	register struct Tree *t;
	int l, k, nest, dd;

	k = [self srchx: *p1];
	if(k == TDO)
		return [self doStatement: p1 end: p2];
	if(p2 >= p1+2 && strcmp(*(p1+1), "(") == 0) {
		l = 0;
		rp = 0;
		for(p=p1+1; p!=p2; p++) {
			if(strcmp(*p, "(") == 0)
				l++;
			else if(strcmp(*p, ")") == 0) {
				l--;
				if(l == 0) {
					rp = p;
					break;
				}
			}
		}
		if(rp == 0) {
			(*error)++;
			return(0);
		}
		t = [self tree];
		if(k == TWHILE) {
			t->DTYP = TWHILE;
			t->DLEF = [self syn3: p1+2 end: rp];
			p = rp+1;
			if(p != p2 && [self wordIs: *p name: "then"])
				p++;
			t->DRIT = [self syn1: p end: p2];
			return(t);
		}
		if(k != TIF) {
			(*error)++;
			return(0);
		}
		t->DTYP = TIF;
		t->DLEF = [self syn3: p1+2 end: rp];
		t->DSTR = 0;
		p = rp+1;
		if(p != p2 && [self wordIs: *p name: "then"])
			p++;
		bs = p;
		nest = 0;
		l = 0;
		dd = 0;
		ep = 0;
		for(; p!=p2; p++) {
			if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0)
				l++;
			else if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0)
				l--;
			else if(l == 0) {
				if([self wordIs: *p name: "do"])
					dd++;
				else if([self wordIs: *p name: "end"])
					dd--;
				else if(dd == 0 && [self wordIs: *p name: "if"])
					nest++;
				else if(dd == 0 && [self wordIs: *p name: "else"]) {
					if(nest == 0) {
						ep = p;
						break;
					}
					nest--;
				}
			}
		}
		if(ep != 0) {
			t->DRIT = [self syn1: bs end: ep];
			t->DSTR = [self syn1: ep+1 end: p2];
		}
		else
			t->DRIT = [self syn1: bs end: p2];
		return(t);
	}
	if(k != TIF) {
		(*error)++;
		return(0);
	}
	l = 0;
	dd = 0;
	tp = 0;
	for(p=p1+1; p!=p2; p++) {
		if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0) {
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
		(*error)++;
		return(0);
	}
	t = [self tree];
	t->DTYP = TIF;
	t->DLEF = [self syn3: p1+1 end: tp];
	t->DSTR = 0;
	bs = tp+1;
	p = bs;
	nest = 0;
	l = 0;
	dd = 0;
	ep = 0;
	for(; p!=p2; p++) {
		if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0)
			l++;
		else if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0)
			l--;
		else if(l == 0) {
			if([self wordIs: *p name: "do"])
				dd++;
			else if([self wordIs: *p name: "end"])
				dd--;
			else if(dd == 0 && [self wordIs: *p name: "if"])
				nest++;
			else if(dd == 0 && [self wordIs: *p name: "else"]) {
				if(nest == 0) {
					ep = p;
					break;
				}
				nest--;
			}
		}
	}
	if(ep != 0) {
		t->DRIT = [self syn1: bs end: ep];
		t->DSTR = [self syn1: ep+1 end: p2];
	}
	else
		t->DRIT = [self syn1: bs end: p2];
	return(t);
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
	int l;

	m = [self matchEnd: p1 end: p2];
	if(m == 0) {
		(*error)++;
		return(0);
	}
	ep = p2;
	while(ep != m+1 && (*(ep-1))[1] == '\0' &&
	    (**(ep-1) == ';' || **(ep-1) == '\n'))
		ep--;
	if(ep != m+1) {
		(*error)++;
		return(0);
	}
	t = [self tree];
	p = p1+1;
	if(p != m && [self wordIs: *p name: "while"]) {
		l = 0;
		semi = 0;
		for(q=p+1; q!=m; q++) {
			if(strcmp(*q, "(") == 0 || strcmp(*q, "{") == 0) {
				l++;
				continue;
			}
			if(strcmp(*q, ")") == 0 || strcmp(*q, "}") == 0) {
				l--;
				continue;
			}
			if(l == 0 && strcmp(*q, ";") == 0) {
				semi = q;
				break;
			}
		}
		if(semi == 0) {
			(*error)++;
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
		l = 0;
		topos = 0;
		for(q=p+2; q!=m; q++) {
			if(strcmp(*q, "(") == 0 || strcmp(*q, "{") == 0) {
				l++;
				continue;
			}
			if(strcmp(*q, ")") == 0 || strcmp(*q, "}") == 0) {
				l--;
				continue;
			}
			if(l == 0 && [self wordIs: *q name: "to"]) {
				topos = q;
				break;
			}
		}
		l = 0;
		semi = 0;
		if(topos != 0)
			for(q=topos+1; q!=m; q++) {
				if(strcmp(*q, "(") == 0 || strcmp(*q, "{") == 0) {
					l++;
					continue;
				}
				if(strcmp(*q, ")") == 0 || strcmp(*q, "}") == 0) {
					l--;
					continue;
				}
				if(l == 0 && strcmp(*q, ";") == 0) {
					semi = q;
					break;
				}
			}
		if(topos == 0 || semi == 0) {
			(*error)++;
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

	case '{':
		l++;
		continue;

	case '}':
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
	(*error)++;
	return(0);
}

/*
 * syn3
 *	syn4
 *	syn3 || syn4
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '|':
		if(l == 0 && (*p)[1] == '|')
			q = p;
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
	(*error)++;
	return(0);
}

/*
 * syn4
 *	syn5
 *	syn4 && syn5
 *	syn4 AND syn5
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '&':
		if(l == 0 && (*p)[1] == '&')
			q = p;
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
		t->DRIT = [self syn5: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self syn5: p1 end: p2];
	(*error)++;
	return(0);
}

/*
 * syn5
 *	synxor
 *	syn5 | synxor
 *
 * single '|' is bitwise or now that commands are gone
 */
- (struct Tree *) syn5: (char **) p1 end: (char **) p2
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '|':
		if(l == 0 && (*p)[1] != '|')
			q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = TOR;
		t->DLEF = [self syn5: p1 end: q];
		t->DRIT = [self synxor: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self synxor: p1 end: p2];
	(*error)++;
	return(0);
}

/*
 * synxor
 *	syn6
 *	synxor ^ syn6
 *	synxor XOR syn6
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '^':
		if(l == 0 && (*p)[1] == '\0')
			q = p;
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
		t->DRIT = [self syn6: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self syn6: p1 end: p2];
	(*error)++;
	return(0);
}

/*
 * syn6
 *	syneq
 *	syn6 & syneq
 *
 * single '&' is bitwise and; trailing background '&'
 * has no meaning without commands
 */
- (struct Tree *) syn6: (char **) p1 end: (char **) p2
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '&':
		if(l == 0 && (*p)[1] != '&')
			q = p;
		continue;
	}
	if(q != 0) {
		t = [self tree];
		t->DTYP = TAND;
		t->DLEF = [self syn6: p1 end: q];
		t->DRIT = [self syneq: q+1 end: p2];
		return(t);
	}
	if(l == 0)
		return [self syneq: p1 end: p2];
	(*error)++;
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
 *	syneq == synrel
 *	syneq != synrel
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '=':
		if(l == 0 && ((*p)[1] == '=' || (*p)[1] == '\0')) {
			q = p;
			qc = **p;
		}
		continue;

	case '!':
		if(l == 0 && (*p)[1] == '=') {
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
	(*error)++;
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

	case '{':
		l++;
		continue;

	case '}':
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
	(*error)++;
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

	case '{':
		l++;
		continue;

	case '}':
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
		if(l == 0) {
			k2 = [self srchx: *p];
			if(k2 == TADD || k2 == TSUB) {
				q = p;
				qc = (k2 == TADD) ? '+' : '-';
			}
		}
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
	(*error)++;
	return(0);
}

/*
 * synmul
 *	synun
 *	synmul * synun
 *	synmul / synun
 *	synmul % synun
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case '*':
	case '/':
	case '%':
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
	(*error)++;
	return(0);
}

/*
 * synun
 *	syn7
 *	- synun
 *	+ synun
 *	! synun
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
		if(strcmp(*p1, "!") == 0) {
			t = [self tree];
			t->DTYP = TEQU;
			t->DLEF = [self synun: p1+1 end: p2];
			t1 = [self tree];
			t1->DTYP = TNUM;
			t1->DARR[0] = "0";
			t->DRIT = t1;
			return(t);
		}
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
 *	unmatched DO count in the word range, the DO..END
 *	twin of braceDepth above; paren and brace interiors
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
		if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0) {
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
		if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0) {
			l++;
			continue;
		}
		if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0) {
			l--;
			continue;
		}
		if(l != 0)
			continue;
		if([self wordIs: *p name: "do"])
			dd++;
		else if([self wordIs: *p name: "end"]) {
			dd--;
			if(dd == 0)
				return(p);
		}
	}
	return(0);
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
		if(l == 0) {
			if(lp != 0)
				(*error)++;
			lp = p+1;
		}
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
		if(n == 1) {
			k = [self srchx: p1[0]];
			if(k == TINPUT || k == TOUTPUT) {
				t = [self tree];
				t->DTYP = k;
				t->DLEF = [self syn2: lp end: rp];
				return(t);
			}
		}
		if(n != 0)
			(*error)++;
		t = [self tree];
		t->DTYP = TPAR;
		t->DSTR = [self syn1: lp end: rp];
		return(t);
	}
	if(n == 0) {
		(*error)++;
		return(0);
	}
	switch(k = [self srchx: p1[0]]) {

	case TDECL:
		if([self wordIs: p1[0] name: "declare"]) {
			/* DECLARE name BYTE, DECLARE name ADDRESS */
			if(n != 3) {
				(*error)++;
				return(0);
			}
			if([self srchx: p1[1]] != -1 || ![self nameOk: p1[1]]) {
				(*error)++;
				return(0);
			}
			t = [self tree];
			if([self wordIs: p1[2] name: "byte"])
				t->DTYP = TDECL;
			else if([self wordIs: p1[2] name: "address"])
				t->DTYP = TADDR;
			else {
				(*error)++;
				return(0);
			}
			t->DARR[0] = p1[1];
			return(t);
		}
		if(n != 2) {
			(*error)++;
			return(0);
		}
		if([self srchx: p1[1]] != -1 || ![self nameOk: p1[1]]) {
			(*error)++;
			return(0);
		}
		t = [self tree];
		t->DTYP = TDECL;
		t->DARR[0] = p1[1];
		return(t);

	case TADDR:
		if(n != 2) {
			(*error)++;
			return(0);
		}
		if([self srchx: p1[1]] != -1 || ![self nameOk: p1[1]]) {
			(*error)++;
			return(0);
		}
		t = [self tree];
		t->DTYP = TADDR;
		t->DARR[0] = p1[1];
		return(t);

	case TDISABLE:
	case TENABLE:
	case THALT:
		if(n != 1) {
			(*error)++;
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
		(*error)++;
		return(0);
	}
	if((p1[0][0] >= '0' && p1[0][0] <= '9') ||
	    (p1[0][0] == '-' && p1[0][1] >= '0' && p1[0][1] <= '9')) {
		char *a, *b;

		/* $ signs read for show in numbers are dropped */
		a = p1[0];
		b = p1[0];
		while(*a) {
			if(*a != '$')
				*b++ = *a;
			a++;
		}
		*b = '\0';
		t = [self tree];
		t->DTYP = TNUM;
		t->DARR[0] = p1[0];
		return(t);
	}
	if([self anyCharacter: p1[0][0] in: "=|&^<>!+-*/%~{}"]) {
		(*error)++;
		return(0);
	}
	if(n != 1) {
		(*error)++;
		return(0);
	}
	p1[n++] = 0;
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
