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
#define DTYP t_dtyp
#define DLEF t_dlef.t_dltr
#define DRIT t_drit.t_drtr
#define DARR t_dcom.t_darr
#define DPTR t_dcom.t_dptr
#define DSPT t_dspr.t_dptr
#define DSTR t_dspr.t_dtre
#define DLPT t_dlef.t_dlpt
#define DRPT t_drit.t_drpt

#define LINSIZ 1000
#define ARGSIZ 50
#define EXPSIZ 1000
#define TRESIZ 100
#define NUMSIZ 12
#define CMDSIZ 100
#define MSGSIZ 100
#define LSTSIZ 10

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

#define DOLREPL 1
#define DOLREPQ 2

struct Builtin {
	const char *bname;
	SEL bfunc;
};

struct Argument {
	const char *arg;
	struct Argument *next;
	struct Argument *prev;
};

struct Tree {
	int t_dtyp;
	union {
		struct Tree *t_dltr;
		char *t_dlpt;
	} t_dlef;
	union {
		struct Tree *t_drtr;
		char *t_drpt;
	} t_drit;
	union {
		char *t_dptr;
		struct Tree *t_dtre;
	} t_dspr;
	union {
		char *t_dptr;
		char *t_darr[ARGSIZ];
	} t_dcom;
};

struct Pack {
	struct Builtin *ptr;
	size_t count;
};

@interface Shell: Object
{
@private
	id func;
	char msg[MSGSIZ];
	char seta[26][EXPSIZ];
	char line[LINSIZ];
	char *args[ARGSIZ];
	char pidp[NUMSIZ];
	struct Tree trebuf[TRESIZ];
	struct Argument argbuf[LSTSIZ];
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
	struct Argument *argdef;
}
+ (int) argumentCount: (int) c argumentVector: (char **) av;
- (void) main;
@end

@interface Shell (Semantic)
- (void) compileTree: (struct Tree *) t;
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
- (struct Tree *) syn2: (char **) p1 end: (char **) p2;
- (struct Tree *) syn3: (char **) p1 end: (char **) p2;
- (struct Tree *) syn4: (char **) p1 end: (char **) p2;
- (struct Tree *) syn5: (char **) p1 end: (char **) p2;
- (struct Tree *) syn6: (char **) p1 end: (char **) p2;
- (struct Tree *) syn7: (char **) p1 end: (char **) p2;
- (struct Tree *) tree;
@end

@interface Shell (Miscellaneous)
- (void) printString: (const char *) as;
- (void) putCharacter: (int) c;
- (void) printNumber: (int) n;
- (int) anyCharacter: (int) c in: (const char *) as;
- (int) equalString: (const char *) as1 to: (const char *) as2;
- (void) error: (const char *) s code: (int) exitno;
- (int) lastCharacter: (char *) cp;
- (void) scan: (struct Tree *) at selector: (SEL) sel;
- (int) glob: (int) c;
- (int) trim: (int) c;
- (char *) integerToASCII: (int) n;
- (char *) getPIDPointer;
- (void) setPIDPointer: (char *) ptr;
- (char *) getLine;
- (void) setLine: (char *) ptr;
- (char **) getArguments;
- (void) setArguments: (char **) ptr;
- (struct Tree *) getTreeBuffer;
- (void) setTreeBuffer: (struct Tree *) ptr;
- (struct Argument *) getArgumentBuffer;
- (void) setArgumentBuffer: (struct Argument *) ptr;
- (char *) getMessage;
- (void) setMessage: (char *) ptr;
- (char (*)[]) getSetASCII;
- (void) setSetASCII: (char (*)[]) ptr;
- (id) getFunction;
- (void) setFunction: (id) ptr;
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
- (struct Argument *) getArgumentDefinition;
@end
#endif /* !SH_H */
