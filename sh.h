#ifndef SH_H
#define SH_H 1
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <signal.h>
#import <setjmp.h>
#import <errno.h>
#import <sys/wait.h>
#import <fcntl.h>
#import <fcntl.h>

#import "/usr/local/include/objc/Object.h"
#import "/usr/local/include/objc/objc-api.h"

#define QUOTE 0200

#define TVAR 1
#define TPAR 2
#define TOR 3
#define TAND 4
#define TXOR 5
#define TASG 6
#define TGTR 7
#define TLSS 8
#define TLST 9
#define TEQU 10
#define TNEQ 11
#define TGEQ 12
#define TLEQ 13
#define TOR2 14
#define TAND2 15
#define TNUM 16
#define TDECL 17
#define TADD 18
#define TSUB 19
#define TADDR 23
#define TIF 24
#define TWHILE 25
#define TELSE 26
#define TDEREF 27
#define TMUL 20
#define TDIV 21
#define TMOD 22
#define DTYP t_dtyp
#define DLEF t_dlef
#define DRIT t_drit
#define DARR t_darr
#define DSTR t_dtre

#define LINSIZ 4000
#define ARGSIZ 200
#define EXPSIZ 1000
#define TRESIZ 200
#define NUMSIZ 12
#define SYMSIZ 50
#define SYMNAMSIZ 32
#define ORGADR 32768

#define ERR_SYNTAX "syntax error"
#define ERR_EQUALS "'=' error"
#define ERR_BADDIR ": bad directory"
#define ERR_COUNT ": arg count"
#define ERR_AGAIN "try again"
#define ERR_OPEN ": cannot open"
#define ERR_CREATE ": cannot create"
#define ERR_FOUND ": not found"
#define ERR_LARGE ": too large"
#define ERR_CHAR "Too many characters"
#define ERR_ARGS "Too many args"
#define ERR_BADMSG ": bad message"
#define ERR_LNGMSG ": message too long"
#define ERR_REDECL ": redeclared"
#define ERR_UNDECL ": undeclared"

#define DOLREPL 1
#define DOLREPQ 2

struct Keyword {
	const char *kname;
	int ktype;
};

struct Tree {
	int t_dtyp;
	struct Tree *t_dlef;
	struct Tree *t_drit;
	struct Tree *t_dtre;
	char *t_darr[ARGSIZ];
};

@interface Shell: Object
{
@private
	char seta[26][EXPSIZ];
	char line[LINSIZ];
	char *args[ARGSIZ];
	char pidp[NUMSIZ];
	struct Tree trebuf[TRESIZ];
	char symnam[SYMSIZ][SYMNAMSIZ];
	int symtyp[SYMSIZ];
	int *symc;
	int *lblc;
	int *orgflg;
	int *treec;
	int *errval;
	int *idolp;
	char **dolp;
	char ***dolv;
	int *dolc;
	char **promp;
	char **linep;
	char **elinep;
	char ***argp;
	char ***eargp;
	int *peekc;
	int *gflg;
	int *error;
	int *uid;
	int *setintr;
	char **arginp;
	int *onelflg;
	int *stoperr;
	int *execflg;
	jmp_buf *jmp;
}
+ (int) argumentCount: (int) c argumentVector: (char **) av;
- (void) main;
@end

@interface Shell (Semantic)
- (void) compileTree: (struct Tree *) t;
- (void) compileAddress: (struct Tree *) t;
- (void) declareName: (char *) na type: (int) t;
- (int) lookupName: (char *) na;
@end

@interface Shell (Lexer)
- (void) word;
- (void) setVariable: (int) i value: (char *) na;
- (int) readCharacter;
- (int) getCharacter: (int) flag;
@end

@interface Shell (Parser)
- (struct Tree *) syntax: (char **) p1 end: (char **) p2;
- (struct Tree *) syn1: (char **) p1 end: (char **) p2;
- (int) braceDepth: (char **) p1 end: (char **) p2;
- (struct Tree *) statement: (char **) p1 end: (char **) p2;
- (struct Tree *) headparse: (char **) p1 end: (char **) p2;
- (struct Tree *) syn2: (char **) p1 end: (char **) p2;
- (struct Tree *) syn3: (char **) p1 end: (char **) p2;
- (struct Tree *) syn4: (char **) p1 end: (char **) p2;
- (struct Tree *) syn5: (char **) p1 end: (char **) p2;
- (struct Tree *) syn6: (char **) p1 end: (char **) p2;
- (struct Tree *) syn7: (char **) p1 end: (char **) p2;
- (struct Tree *) synxor: (char **) p1 end: (char **) p2;
- (struct Tree *) syneq: (char **) p1 end: (char **) p2;
- (struct Tree *) synrel: (char **) p1 end: (char **) p2;
- (struct Tree *) synadd: (char **) p1 end: (char **) p2;
- (struct Tree *) synmul: (char **) p1 end: (char **) p2;
- (struct Tree *) synun: (char **) p1 end: (char **) p2;
- (int) isOperator: (char *) w;
- (int) srchx: (char *) cp;
- (struct Tree *) tree;
@end

@interface Shell (Miscellaneous)
- (void) printString: (const char *) as;
- (void) putCharacter: (int) c;
- (int) anyCharacter: (int) c in: (const char *) as;
- (void) error: (const char *) s code: (int) exitno;
- (char *) integerToASCII: (int) n;
- (char *) getPIDPointer;
- (void) setPIDPointer: (char *) ptr;
- (int *) getTreeCount;
- (int *) getErrorValue;
- (int *) getCurrentDollarPointer;
- (char **) getDollarPointer;
- (char ***) getDollarVector;
- (int *) getDollarCount;
- (char **) getPrompt;
- (char **) getLinePointer;
- (char **) getEndLinePointer;
- (char ***) getArgumentPointer;
- (char ***) getEndArgumentPointer;
- (int *) getPeekCharacter;
- (int *) getGlobFlag;
- (int *) getError;
- (int *) getUserID;
- (int *) getSetInterrupt;
- (char **) getArgumentInput;
- (int *) getOneLineFlag;
- (int *) getStopError;
- (int *) getExecuteFlag;
- (jmp_buf *) getJumpBuffer;
- (int *) getLabelCount;
- (int *) getSymbolCount;
- (int *) getOrgFlag;
@end
#endif /* !SH_H */
