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

static char subchar = '$';

@implementation Shell (Lexer)
- (void) word
{
	register char c, c1;
	register int dolflag;

	*(*argp)++ = *linep;

loop:
	switch(c = [self getCharacter: DOLREPL]) {

	case ' ':
	case '\t':
		goto loop;

	case '\'':	/* '...' : what you see is what you get */
	case '"':	/* "..." : \", \$, $ substitution */
		c1 = c;
		dolflag = (c == '"' && !*dolp) ? DOLREPQ : !DOLREPL;
		while((c=[self getCharacter: dolflag]) != c1) {
			if(c == '\n') {
				(*error)++;
				*peekc = c;
				return;
			}
			if (c1 == '"' &&
			    c == '\\' &&
			    ((*peekc = [self getCharacter: !DOLREPL]) == '$' ||
			     *peekc == '"')) {
				c = *peekc;
				*peekc = 0;
			}
			*(*linep)++ = c|QUOTE;
		}
		goto pack;

	case '&':
	case '|':
	case '=':
		*(*linep)++ = c;
		c1 = [self getCharacter: DOLREPL];
		if(c1 == c)
			*(*line)++ = c1;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case '<':
	case '>':
		*(*linep)++ = c;
		c1 = [self getCharacter: DOLREPL];
		if(c1 == '=')
			*(*linep)++ = c;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case ';':
	case '(':
	case ')':
	case '^':
	case '\n':
		*(*linep)++ = c;
		*(*linep)++ = '\0';
		return;
	case '\\':
		if ((c=[self getCharacter: !DOLREPL])=='\n') goto loop;
		else {
			c |= QUOTE;
			break;
		}
	}

	*peekc = c;

pack:
	for(;;) {
		if ((c = [self getCharacter: DOLREPL])=='\\') {
			if ((c=[self getCharacter: !DOLREPL])=='\n') c = ' ';
			else c |= QUOTE;
		}
		if([self anyCharacter: c in: " '\"\t;&<>()|^\n:"]) {
			*peekc = c;
			if([self anyCharacter: c in: "\"'"])
				goto loop;
			if(c == ':')
				*(*linep)++ = [self getCharacter: !DOLREPL];
			*(*linep)++ = '\0';
			return;
		}
		*(*linep)++ = c;
	}
}

- (void) setVariable: (int) i value: (char *) na
{
	register char *st, *np;
	char c;

	st = seta[i];
	np = na;
	if(np == NULL)
		goto null;
	for (;;) {
		c = *np++ & 0177;
		*st++ = c;
		if(c=='\n' || c=='\0') break;
	}
	if(c=='\n') st++;
null:
	*st = '\0';
}

/*	flag: !DOLREPL ==> no substitution, DOLREPL ==> substitute,
	DOLREPQ ==> quoted substitution: "$1" = value of $1 for sure */
- (int) getCharacter: (int) flag
{
	register char c;

	if(*peekc) {
		c = *peekc;
		*peekc = 0;
		return(c);
	}
	if(*argp > *eargp) {
		*argp -= 10;
		while((c=[self getCharacter: !DOLREPL]) != '\n');
		*argp += 10;
		[self error: ERR_ARGS code: 255];
		(*gflg)++;
		return(c);
	}
	if(*linep > *elinep) {
		*linep -= 10;
		while((c=[self getCharacter: !DOLREPL]) != '\n');
		*linep += 10;
		[self error: ERR_CHAR code: 255];
		(*gflg)++;
		return(c);
	}
getd:
	if(*dolp) {
		if ((c = *(*dolp)++)) {
			if (flag == DOLREPQ)
				c |= QUOTE;
			return c;
		}
		if (*idolp && ++(*idolp) < *dolc) {
			*dolp = (*dolv)[*idolp];
			return(' ');
		}
		*dolp = 0;
	}
	c = [self readCharacter];
	if(c == subchar && flag) {
		c = [self readCharacter];
		if(c>='0' && c<='9') {
			if(c-'0' < *dolc)
				*dolp = (*dolv)[c-'0'];
			goto getd;
		}
		else if(c>='a' && c<='z') {
			*dolp = seta[c-'a'];
			goto getd;
		}
		else if(c == '$') {
			*dolp = pidp;
			goto getd;
		}
		/* $* = $1 $2 .... */
		else if (c == '*') {
			if (*dolc > 1) {
				*idolp = 1;
				*dolp = (*dolv)[1];
			}
			goto getd;
		}
		else
			if(c != '\n')  c = [self readCharacter];
	}
	return(c&0177);
}

- (int) readCharacter
{
	int rdstat;
	char cc;
	register int c;

	if (*arginp) {
		if (**arginp == 1)
			exit(*errval);
		if ((c = *(*arginp)++) == 0) {
			**arginp = 1;
			c = '\n';
		}
		return(c);
	}
	if (*onelflg==1)
		exit(255);
	if((rdstat = read(0, &cc, 1)) != 1) {
		if(rdstat==0) exit(*errval); /* end of file*/
		else exit(255); /* error */
	}
	if (cc=='\n' && *onelflg)
		(*onelflg)--;
	return(cc);
}
@end
