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

int
main(int c, char *av[])
{
	return [Shell argumentCount: c argumentVector: av];
}

@implementation Shell
+ (int) argumentCount: (int) c argumentVector: (char **) av
{
	register id sh;
	register char **v;
	int f;

	sh = [self new];
	(void) [sh getTreeCount];
	(void) [sh getErrorValue];
	(void) [sh getLinePointer];
	(void) [sh getEndLinePointer];
	(void) [sh getArgumentPointer];
	(void) [sh getEndArgumentPointer];
	(void) [sh getPeekCharacter];
	(void) [sh getLabelCount];
	(void) [sh getSymbolCount];
	(void) [sh getScope];
	(void) [sh getRamPointer];
	(void) [sh getOrgFlag];
	(void) [sh getOrgEnable];
	(void) [sh getCartEnable];
	(void) [sh getMacroCount];
	(void) [sh getLabCount];
	(void) [sh getProcCount];
	(void) [sh getInProc];
	for(v = av+1; v < av+c; v++) {
		if(strcmp(*v, "-o") == 0) {
			*[sh getOrgEnable] = 1;
			continue;
		}
		if(strcmp(*v, "-h") == 0) {
			*[sh getCartEnable] = 1;
			continue;
		}
		if(**v == '-') {
			[sh printString: *v];
			[sh error: ERR_OPT code: 255];
		}
		close(0);
		f = open(*v, 0);
		if(f < 0) {
			[sh printString: *v];
			[sh error: ERR_OPEN code: 255];
		}
	}
loop:
	*[sh getPeekCharacter] = [sh getCharacter];
	[sh main];
	goto loop;
	return 0;
}

- (void) main
{
	register char  *cp;
	register struct Tree *t;

	*argp = args;
	*eargp = args+ARGSIZ-1;
	*linep = line;
	*elinep = line+LINSIZ-1;
	do {
		cp = *linep;
		[self word];
	} while(*cp != '\n' || [self doDepth: args end: *argp] > 0 ||
	    [self labelHang: args end: *argp]);
	*treec = 0;
	t = [self syntax: args end: *argp];
	[self compileTree: t];
}
@end
