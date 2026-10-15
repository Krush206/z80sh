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

@implementation Shell (Miscellaneous)
- (void) printString: (const char *) as
{
	register const char *s;

	s = as;
	while(*s)
		[self putCharacter: *s++];
}

- (void) putCharacter: (int) c
{
	char cc;

	cc = c;
	write(2, &cc, (size_t) 1);
}

- (int) anyCharacter: (int) c in: (const char *) as
{
	register const char *s;

	s = as;
	while(*s)
		if(*s++ == c)
			return(1);
	return(0);
}

- (void) error: (const char *) s code: (int) code
{
	[self printString: s];
	[self printString: "\n"];
	lseek(0, (off_t) 0, SEEK_END);
	exit(code);
}

- (char *) integerToASCII: (int) n
{
	register int i;
	register char *cp;
	static char str[NUMSIZ];

	i = n;
	cp = &str[sizeof str - 2];
	for (;;) {
		*cp = i % 10 + '0';
		i /= 10;
		if(i == 0)
			return cp;
		cp--;
	}
	return NULL;
}

- (int *) getTreeCount
{
	static int ret;

	return treec = &ret;
}

- (int *) getErrorValue
{
	static int ret;

	return errval = &ret;
}

- (char **) getLinePointer
{
	static char *ret;

	return linep = &ret;
}

- (char **) getEndLinePointer
{
	static char *ret;

	return elinep = &ret;
}

- (char ***) getArgumentPointer
{
	static char **ret;

	return argp = &ret;
}

- (char ***) getEndArgumentPointer
{
	static char **ret;

	return eargp = &ret;
}

- (int *) getPeekCharacter
{
	static int ret;

	return peekc = &ret;
}

- (int *) getLabelCount
{
	static int ret;

	return lblc = &ret;
}

- (int *) getSymbolCount
{
	static int ret;

	return symc = &ret;
}

- (int *) getScope
{
	static int ret;

	return scope = &ret;
}

- (int *) getRamPointer
{
	static int ret = RAMSTART;

	return ramc = &ret;
}

- (int *) getOrgFlag
{
	static int ret;

	return orgflg = &ret;
}

- (int *) getOrgAddress
{
	static int ret = -1;

	return orgadr = &ret;
}

- (int *) getCartEnable
{
	static int ret;

	return carten = &ret;
}

- (int *) getMacroCount
{
	static int ret;

	return macc = &ret;
}

- (int *) getLabCount
{
	static int ret;

	return labc = &ret;
}

- (int *) getProcCount
{
	static int ret;

	return prcc = &ret;
}

- (int *) getInProc
{
	static int ret;

	return inProc = &ret;
}
@end
