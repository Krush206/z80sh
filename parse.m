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
 * rows stay in alphabetical order for the binary search
 */
static struct Keyword keyw[] = {
	{ "address", TADDR },
	{ "else", TELSE },
	{ "if", TIF },
	{ "int", TDECL },
	{ "while", TWHILE }
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
 */
- (struct Tree *) syn1: (char **) p1 end: (char **) p2
{
	register char **p;
	register struct Tree *t;
	int l;

	l = 0;
	if(p1 != p2) {
		t = [self headparse: p1 end: p2];
		if(t != 0)
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

	case '{':
		l++;
		continue;

	case '}':
		l--;
		continue;

	case ';':
	case '\n':
		if(l == 0) {
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
	if(l == 0)
		return [self syn2: p1 end: p2];
	(*error)++;
	return(0);
}

/*
 * statement
 *	if ( syn2 ) syn1
 *	if ( syn2 ) syn1 else syn1
 *	while ( syn2 ) syn1
 *
 * bodies are single line ranges; syn1 parses them so they
 * nest, chain with ; and form { } blocks; an else past any
 * nested ifs belongs to this if, after the C shell's syn3
 */
- (struct Tree *) statement: (char **) p1 end: (char **) p2
{
	register char **p;
	register char **rp;
	register char **ep;
	register struct Tree *t;
	int l, k, nest;

	if(p2 < p1+2 || strcmp(*(p1+1), "(") != 0) {
		(*error)++;
		return(0);
	}
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
	k = [self srchx: *p1];
	if(k == TWHILE) {
		t->DTYP = TWHILE;
		t->DLEF = [self syn2: p1+2 end: rp];
		t->DRIT = [self syn1: rp+1 end: p2];
		return(t);
	}
	t->DTYP = TIF;
	t->DLEF = [self syn2: p1+2 end: rp];
	t->DSTR = 0;
	nest = 0;
	l = 0;
	ep = 0;
	for(p=rp+1; p!=p2; p++) {
		if(strcmp(*p, "(") == 0 || strcmp(*p, "{") == 0)
			l++;
		else if(strcmp(*p, ")") == 0 || strcmp(*p, "}") == 0)
			l--;
		else if(l == 0 && strcmp(*p, "if") == 0)
			nest++;
		else if(l == 0 && strcmp(*p, "else") == 0) {
			if(nest == 0) {
				ep = p;
				break;
			}
			nest--;
		}
	}
	if(ep != 0) {
		t->DRIT = [self syn1: rp+1 end: ep];
		t->DSTR = [self syn1: ep+1 end: p2];
	}
	else
		t->DRIT = [self syn1: rp+1 end: p2];
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
 *	or '+' coming right after one of these is unary
 */
- (int) isOperator: (char *) w
{
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
	return(0);
}

/*
 * syneq
 *	synrel
 *	syneq == synrel
 *	syneq != synrel
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
		if(l == 0 && (*p)[1] == '=') {
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
 *
 * a '+' or '-' after another operator or opener is unary,
 * so it is left for synun instead of splitting here
 */
- (struct Tree *) synadd: (char **) p1 end: (char **) p2
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

	case '+':
	case '-':
		if(l == 0 && (*p)[1] == '\0' && p != p1 && ![self isOperator: *(p-1)]) {
			q = p;
			qc = **p;
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
 *	keyw table; after the C shell's srchx()
 */
- (int) srchx: (char *) cp
{
	register int first, last, middle, compare;

	first = 0;
	last = sizeof keyw / sizeof *keyw - 1;
	while(first <= last) {
		middle = first + (last - first) / 2;
		compare = strcmp(cp, keyw[middle].kname);
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
	case TADDR:
		if(n != 2) {
			(*error)++;
			return(0);
		}
		t = [self tree];
		t->DTYP = k;
		t->DARR[0] = p1[1];
		return(t);

	case TIF:
	case TWHILE:
	case TELSE:
		(*error)++;
		return(0);
	}
	if((p1[0][0] >= '0' && p1[0][0] <= '9') ||
	    (p1[0][0] == '-' && p1[0][1] >= '0' && p1[0][1] <= '9')) {
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
		[self printString: "Command line overflow\n"];
		(*error)++;
		longjmp(*jmp, 1);
	}
	return(&trebuf[(*treec)++]);
}
@end
