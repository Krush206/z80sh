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
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;

	case ';':
	case '\n':
		if(l == 0) {
			register struct Tree *t1;

			t = [self tree];
			t->DTYP = TLST;
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
 * syn2
 *	syn3
 *	syn3 & syn2
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

	case '&':
		if(l == 0) {
			t = [self tree];
			t->DTYP = TAND; // Set to Async / Background token
			if((*p)[1] == '&')
				t->DTYP = TAND2;
			t->DLEF = [self syn3: p1 end: p];
			t->DRIT = [self syn2: p+1 end: p2];
			return(t);
		}
	}
	if(l == 0)
		return [self syn3: p1 end: p2]; // Fixed: fall through down to syn3
	(*error)++;
	return(0);
}

/*
 * syn3
 *	syn4
 *	syn4 | syn3
 */
- (struct Tree *) syn3: (char **) p1 end: (char **) p2
{
	register char **p;
	register int l;
	register struct Tree *t;

	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;

	case '|':
		if(l == 0) {
			t = [self tree];
			t->DTYP = TOR;
			if((*p)[1] == '|')
				t->DTYP = TOR2;
			t->DLEF = [self syn4: p1 end: p];      // Evaluates high precedence left
			t->DRIT = [self syn3: p+1 end: p2];    // Evaluates pipeline right
			return(t);
		}
	}
	return [self syn4: p1 end: p2]; // Fixed: Falls back to syn4 to avoid infinite loops
}

/*
 * syn4
 *	syn5
 *	syn5 = syn4
 */
- (struct Tree *) syn4: (char **) p1 end: (char **) p2
{
	register char **p;
	register int l;
	register struct Tree *t;

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
		if(l == 0) {
			t = [self tree];
			t->DTYP = TASG;
			if((*p)[1] == '=')
				t->DTYP = TEQU;
			t->DLEF = [self syn5: p1 end: p];
			t->DRIT = [self syn4: p+1 end: p2];
			return(t);
		}
	}
	return [self syn5: p1 end: p2]; // Fixed: Falls back to syn5
}

/*
 * syn5
 *	syn6
 *	syn6 > syn5
 */
- (struct Tree *) syn5: (char **) p1 end: (char **) p2
{
	register char **p;
	register int l;
	register struct Tree *t;

	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;

	case '>':
		if(l == 0) {
			t = [self tree];
			t->DTYP = TGTR;
			if((*p)[1] == '=')
				t->DTYP = TGEQ;
			t->DLEF = [self syn6: p1 end: p];
			t->DRIT = [self syn5: p+1 end: p2];
			return(t);
		}
	}
	return [self syn6: p1 end: p2]; // Fixed: Falls back to syn6
}

/*
 * syn6
 *	syn7
 *	syn7 < syn6
 */
- (struct Tree *) syn6: (char **) p1 end: (char **) p2
{
	register char **p;
	register int l;
	register struct Tree *t;

	l = 0;
	for(p=p1; p!=p2; p++)
	switch(**p) {

	case '(':
		l++;
		continue;

	case ')':
		l--;
		continue;

	case '<':
		if(l == 0) {
			t = [self tree];
			t->DTYP = TLSS;
			if((*p)[1] == '=')
				t->DTYP = TLEQ;
			t->DLEF = [self syn7: p1 end: p];
			t->DRIT = [self syn6: p+1 end: p2];
			return(t);
		}
	}
	return [self syn7: p1 end: p2]; // Fixed: Falls back to syn7
}

/*
 * syn7
 *	( syn1 )      <-- Routes back up to top-level expression blocks
 *	keyword       <-- Int intercept for data declarations ("int x")
 *	literal       <-- Number constants ("5")
 *	variable      <-- Identifiers ("counter")
 */
- (struct Tree *) syn7: (char **) p1 end: (char **) p2
{
	register char **p;
	char **lp, **rp;
	register struct Tree *t;
	int n, l, c;

	lp = 0;
	rp = 0;
	n = 0;
	l = 0;

	for(p=p1; p!=p2; p++) {
		char *token = *p;
		switch(c = *token) {

		case '(':
			if(l == 0) {
				if(lp != 0) (*error)++;
				lp = p+1;
			}
			l++;
			continue;

		case ')':
			l--;
			if(l == 0) rp = p;
			continue;

		default:
			if(l == 0)
				p1[n++] = token;
		}
	}

	// Handle bracket sub-expressions: ( expression )
	if(lp != 0) {
		if(n != 0) (*error)++;
		t = [self tree];
		t->DTYP = TPAR;
		t->DSTR = (struct Tree *)[self syn1: lp end: rp];
		return(t);
	}

	if(n == 0) (*error)++;

	// Keyword allocation layer (e.g., "int x")
	if (strcmp(p1[0], "int") == 0) {
		if (n < 2) {
			(*error)++;
			return(0);
		}
		t = [self tree];
		t->DTYP = TDECL;
		t->DARR[0] = p1[1]; // Store variable name directly
		return(t);
	}

	// Literal Numeric Constants (e.g., "5")
	if (p1[0][0] >= '0' && p1[0][0] <= '9') {
		t = [self tree];
		t->DTYP = TNUM;
		t->DARR[0] = p1[0];
		return(t);
	}

	// Default fallback: Variable evaluation lookup
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
