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

@implementation Shell (Lexer)
- (void) word
{
	register char c, c1;

	*(*argp)++ = *linep;

loop:
	switch(c = [self getCharacter]) {

	case ' ':
	case '\t':
		goto loop;

	case '\'':
		/* 'c' : single character value, no escapes */
		c = [self getRawCharacter];
		c1 = [self getRawCharacter];
		if(c1 != '\'')
			[self error: ERR_SYNTAX code: 255];
		if(*linep + 4 > *elinep)
			[self error: ERR_CHAR code: 255];
		(void) strcpy(*linep, [self integerToASCII: c&0177]);
		while(**linep)
			(*linep)++;
		goto pack;

	case '"':	/* "..." : \" quotes a quote */
		[self readQuoted: c];
		goto pack;

	case '&':
	case '|':
	case '=':
	case '+':
	case '-':
	case '*':
	case '/':
	case '%':
		*(*linep)++ = c;
		c1 = [self getCharacter];
		if(c1 == c)
			*(*linep)++ = c1;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case '!':
		*(*linep)++ = c;
		c1 = [self getCharacter];
		if(c1 == '=')
			*(*linep)++ = c1;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case '<':
	case '>':
		*(*linep)++ = c;
		c1 = [self getCharacter];
		if(c1 == '=' || (c == '<' && c1 == '>'))
			*(*linep)++ = c1;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case ':':
		*(*linep)++ = c;
		c1 = [self getCharacter];
		if(c1 == '=')
			*(*linep)++ = c1;
		else
			*peekc = c1;
		*(*linep)++ = '\0';
		return;

	case ';':
	case '(':
	case ')':
	case ',':
	case '^':
	case '\n':
		*(*linep)++ = c;
		*(*linep)++ = '\0';
		return;
	case '\\':
		if ((c=[self getRawCharacter])=='\n') goto loop;
		else {
			c |= QUOTE;
			break;
		}
	}

	*peekc = c;

pack:
	for(;;) {
		if ((c = [self getCharacter])=='\\') {
			if ((c=[self getRawCharacter])=='\n') c = ' ';
			else c |= QUOTE;
		}
		if(![self anyCharacter: c in: " '\"\t;&<>()|^\n:=!+-*/%,"]) {
			*(*linep)++ = c;
			continue;
		}
		*peekc = c;
		if([self anyCharacter: c in: "\"'"])
			goto loop;
		*(*linep)++ = '\0';
		return;
	}
}

/*
 * readQuoted
 *	a "..." string into the word buffer; every character
 *	keeps a QUOTE bit so later stages never mistake it
 *	for syntax; a newline inside is an error
 */
- (void) readQuoted: (int) q
{
	int c;

	c = q;
	while((c = [self getRawCharacter]) != q) {
		if(c == '\n')
			[self error: ERR_SYNTAX code: 255];
		if(q == '"' && c == '\\' &&
		    ((*peekc = [self getRawCharacter]) == '"')) {
			c = *peekc;
			*peekc = 0;
		}
		*(*linep)++ = c|QUOTE;
	}
}

/*
 * endOfFile
 *	end the program: an open DO..END group is a syntax
 *	error, else emit the halt and the ROM header
 */
- (void) endOfFile
{
	if([self doDepth: args end: *argp] > 0)
		[self error: ERR_SYNTAX code: 255];
	printf("\thalt\n");
	printf("\tseek 0x7ff0\n");
	/* name has two trailing spaces; checksum stays 0 */
	printf("\tdefb \"TMR SEGA  \",0,0,0,0,0,0x4c\n");
	exit(*errval);
}

/*	getCharacter strips star-slash comments, getRawCharacter
	does not, so quotes, escapes and drains read through it */
- (int) getCharacter
{
	register int c, c1;

	c = [self getRawCharacter];
	if(c != '/')
		return(c);
	c1 = [self getRawCharacter];
	if(c1 != '*') {
		*peekc = c1;
		return('/');
	}
star:
	while((c = [self readCharacter]) != '*')
		continue;
	if((c = [self readCharacter]) != '/') {
		*peekc = c;
		goto star;
	}
	return([self getRawCharacter]);
}

- (int) getRawCharacter
{
	register char c;

	if(*peekc) {
		c = *peekc;
		*peekc = 0;
		return(c);
	}
	if(*argp > *eargp) {
		*argp -= 10;
		while((c=[self getRawCharacter]) != '\n');
		*argp += 10;
		[self error: ERR_ARGS code: 255];
	}
	if(*linep > *elinep) {
		*linep -= 10;
		while((c=[self getRawCharacter]) != '\n');
		*linep += 10;
		[self error: ERR_CHAR code: 255];
	}
	c = [self readCharacter];
	return(c&0177);
}

- (int) readCharacter
{
	int rdstat;
	char cc;

	if((rdstat = read(0, &cc, 1)) != 1) {
		if(rdstat==0)
			[self endOfFile];
		else exit(255); /* error */
	}
	return(cc);
}
@end
