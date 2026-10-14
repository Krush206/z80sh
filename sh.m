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
	int f, i;

	sh = [self new];
	(void) [sh getTreeCount];
	(void) [sh getErrorValue];
	(void) [sh getCurrentDollarPointer];
	(void) [sh getDollarPointer];
	(void) [sh getDollarVector];
	(void) [sh getDollarCount];
	(void) [sh getPrompt];
	(void) [sh getLinePointer];
	(void) [sh getEndLinePointer];
	(void) [sh getArgumentPointer];
	(void) [sh getEndArgumentPointer];
	(void) [sh getPeekCharacter];
	(void) [sh getGlobFlag];
	(void) [sh getError];
	(void) [sh getUserID];
	(void) [sh getSetInterrupt];
	(void) [sh getArgumentInput];
	(void) [sh getOneLineFlag];
	(void) [sh getStopError];
	(void) [sh getExecuteFlag];
	(void) [sh getJumpBuffer];
	(void) [sh getLabelCount];
	(void) [sh getSymbolCount];
	(void) [sh getScope];
	(void) [sh getOrgFlag];
	(void) strcpy([sh getPIDPointer], [sh integerToASCII: getpid()]);
	v = av;
	for(i = 1; i + 1 < c; i++) {
		if(strcmp(v[i], "-o") != 0)
			continue;
		f = open(v[i+1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
		if(f < 0) {
			[sh printString: v[i+1]];
			[sh error: ERR_CREATE code: 255];
		}
		dup2(f, 1);
		close(f);
		for(f = i; f + 2 < c; f++)
			v[f] = v[f+2];
		c -= 2;
		v[c] = NULL;
		i--;
	}
	*[sh getPrompt] = "% ";
	if(getuid() == 0)
		*[sh getPrompt] = "# ";
	if(!isatty(0))
		*[sh getPrompt] = NULL;
	*[sh getStopError] = 0;
	if(c>1 && v[1][0]=='-' && v[1][1]=='e') {
		++(*[sh getStopError]);
		v[1] = v[0];
		++v;
		--c;
	}
	*[sh getArgumentInput] = NULL;
	*[sh getExecuteFlag] = *[sh getOneLineFlag] = 0;
	if(c > 1) {
		*[sh getPrompt] = NULL;
		if (*v[1]=='-') {
			*[sh getExecuteFlag] = 1;
			if (v[1][1]=='c' && c>2)
				*[sh getArgumentInput] = v[2];
			else if (v[1][1]=='t')
				*[sh getOneLineFlag] = 2;
		} else {
			close(0);
			f = open(v[1], 0);
			if(f < 0) {
				[sh printString: v[1]];
				[sh error: ERR_OPEN code: 255];
			}
		}
	}
	*[sh getSetInterrupt] = 0;
	if(*[sh getExecuteFlag]) {
		signal(SIGQUIT, SIG_DFL);
		signal(SIGINT, SIG_DFL);
		if (*[sh getArgumentInput]==NULL&&*[sh getOneLineFlag]==0)
			(*[sh getSetInterrupt])++;
	}
	*[sh getDollarVector] = v;
	*[sh getDollarCount] = c;
loop:
	if(*[sh getPrompt] != NULL)
		[sh printString: *[sh getPrompt]];
	*[sh getPeekCharacter] = [sh getCharacter: !DOLREPL];
	[sh main];
	goto loop;
	object_dispose(sh);
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
	*error = 0;
	*gflg = 0;
	do {
		if(*promp != NULL && *linep != line)
			[self printString: "> "];
		cp = *linep;
		[self word];
	} while(*cp != '\n' || [self braceDepth: args end: *argp] > 0);
	*treec = 0;
	if(*gflg == 0) {
		if(*error == 0) {
			setjmp(*jmp);
			if (*error)
				return;
			t = [self syntax: args end: *argp];
		}
		if(*error != 0)
			[self error: ERR_SYNTAX code: 255]; else
			[self compileTree: t];
	}
}
@end
