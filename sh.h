#ifndef SH_H
#define SH_H 1
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
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
#define TADDR 23
#define TIF 24
#define TWHILE 25
#define TELSE 26
#define TDEREF 27
#define TBLOCK 28
#define TINPUT 29
#define TOUTPUT 30
#define TNOT 31
#define TDO 32
#define TEND 33
#define TTHEN 34
#define TTO 35
#define TDISABLE 36
#define TENABLE 37
#define THALT 38
#define TBYTE 39
#define TCASE 40
#define TSHL 41
#define TSHR 42
#define TROL 43
#define TROR 44
#define TSCL 45
#define TSCR 46
#define TTIME 47
#define TDEC 48
#define TLOW 49
#define THIGH 50
#define TDOUBLE 51
#define TSUBSCRIPT 52
#define TLENGTH 53
#define TLAST 54
#define TARRAY 55
#define TGOTO 56
#define TGO 57
#define TLABEL 58
#define TCALL 59
#define TPROCEDURE 60
#define TRETURN 61
#define TDATA 62
#define TINITIAL 63
#define TLITERAL 64
#define TINTERRUPT 65
#define TLDEF 66
#define TNOP 67
#define TMUL 20
#define TDIV 21
#define TMOD 22
#define DTYP t_dtyp
#define DLEF t_dlef
#define DRIT t_drit
#define DARR t_darr
#define DSTR t_dtre
/* a procedure node's interrupt flag, clear of the parameter
   names in DARR[3 .. 3+npar-1] */
#define DINT t_darr[ARGSIZ-1]

#define LINSIZ 4000
#define ARGSIZ 200
#define TRESIZ 200
#define NUMSIZ 12
#define SYMSIZ 50
#define SYMNAMSIZ 32
#define SYMLABSIZ 48
#define MACSIZ 32
#define MACVSIZ 64
#define LABSIZ 32
#define PROCSIZ 16
#define MAXPARS 16
#define ORGADR 0
#define RAMSTART 0xC000
#define RAMSIZE 0x2000
#define STACKP 0xDFF8

#define ERR_SYNTAX "syntax error"
#define ERR_OPEN ": cannot open"
#define ERR_LARGE ": too large"
#define ERR_CHAR "Too many characters"
#define ERR_ARGS "Too many args"
#define ERR_REDECL ": redeclared"
#define ERR_UNDECL ": undeclared"

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
	char line[LINSIZ];
	char *args[ARGSIZ];
	struct Tree trebuf[TRESIZ];
	char symnam[SYMSIZ][SYMNAMSIZ];
	int symtyp[SYMSIZ];
	int symlev[SYMSIZ];
	char symlab[SYMSIZ][SYMLABSIZ];
	int symadr[SYMSIZ];
	int symsiz[SYMSIZ];
	char macnam[MACSIZ][SYMNAMSIZ];
	char macval[MACSIZ][MACVSIZ];
	int maclev[MACSIZ];
	char labnam[LABSIZ][SYMNAMSIZ];
	int labdef[LABSIZ];
	char prcnam[PROCSIZ][SYMNAMSIZ];
	int prcnpar[PROCSIZ];
	int prcadr[PROCSIZ][MAXPARS];
	int prcret[PROCSIZ];
	int *symc;
	int *ramc;
	int *scope;
	int *lblc;
	int *orgflg;
	int *treec;
	int *errval;
	char **linep;
	char **elinep;
	char ***argp;
	char ***eargp;
	int *peekc;
	int *macc;
	int *labc;
	int *prcc;
	int *inProc;
}
+ (int) argumentCount: (int) c argumentVector: (char **) av;
- (void) main;
@end

@interface Shell (Semantic)
- (void) compileTree: (struct Tree *) t;
- (int) exprType: (struct Tree *) t;
- (int) symbolType: (int) i;
- (void) toHL;
- (void) compile16: (struct Tree *) t;
- (void) pair16: (struct Tree *) t;
- (void) compileShift: (struct Tree *) t op: (const char *) op;
- (void) prologue;
- (void) compileAddress: (struct Tree *) t;
- (int) declareName: (char *) na type: (int) t;
- (int) declareArray: (char *) na type: (int) t size: (int) n;
- (int) lookupName: (char *) na;
- (int) arraySize: (int) i;
- (void) compileIndex: (struct Tree *) t;
- (void) emitLabel: (char *) na;
- (void) emitArgs: (struct Tree *) list;
- (void) emitCall: (struct Tree *) t;
- (void) defineProc: (struct Tree *) t;
- (int) procIndex: (char *) na;
@end

@interface Shell (Lexer)
- (void) word;
- (int) readCharacter;
- (int) getCharacter;
- (int) getRawCharacter;
- (void) readQuoted: (int) q;
- (void) endOfFile;
@end

@interface Shell (Parser)
- (struct Tree *) syntax: (char **) p1 end: (char **) p2;
- (struct Tree *) splitList: (char **) p1 at: (char **) p end: (char **) p2;
- (struct Tree *) syn1: (char **) p1 end: (char **) p2;
- (struct Tree *) statement: (char **) p1 end: (char **) p2;
- (struct Tree *) headparse: (char **) p1 end: (char **) p2;
- (struct Tree *) syn2: (char **) p1 end: (char **) p2;
- (struct Tree *) syn3: (char **) p1 end: (char **) p2;
- (struct Tree *) syn4: (char **) p1 end: (char **) p2;
- (struct Tree *) syn7: (char **) p1 end: (char **) p2;
- (struct Tree *) synnot: (char **) p1 end: (char **) p2;
- (struct Tree *) syneq: (char **) p1 end: (char **) p2;
- (struct Tree *) synrel: (char **) p1 end: (char **) p2;
- (struct Tree *) synadd: (char **) p1 end: (char **) p2;
- (struct Tree *) synmul: (char **) p1 end: (char **) p2;
- (struct Tree *) synun: (char **) p1 end: (char **) p2;
- (int) isOperator: (char *) w;
- (int) srchx: (char *) cp;
- (int) wordIs: (char *) w name: (const char *) s;
- (int) nameOk: (char *) na;
- (int) doDepth: (char **) p1 end: (char **) p2;
- (char **) matchEnd: (char **) p1 end: (char **) p2;
- (char **) endPast: (char **) m end: (char **) p2;
- (char **) matchParen: (char **) p1 end: (char **) p2;
- (char **) matchElse: (char **) p1 end: (char **) p2;
- (char **) findSemi: (char **) p1 end: (char **) p2;
- (char **) findTo: (char **) p1 end: (char **) p2;
- (char **) findComma: (char **) p1 end: (char **) p2;
- (char **) findPlus: (char **) p1 end: (char **) p2;
- (char **) skipSep: (char **) p1 end: (char **) p2;
- (int) splitCase: (char **) p1 end: (char **) p2 into: (struct Tree **) stmts;
- (struct Tree *) call: (int) k args: (char **) lp end: (char **) rp;
- (void) stringBytes: (char *) s;
- (int) collectValues: (char **) lp end: (char **) rp into: (char **) dst;
- (struct Tree *) dataDecl: (char **) p1 args: (char **) lp end: (char **) rp;
- (struct Tree *) initialDecl: (char **) p1 count: (int) n args: (char **) lp end: (char **) rp args2: (char **) lp2 end: (char **) rp2;
- (struct Tree *) call2: (int) k args: (char **) lp end: (char **) rp;
- (struct Tree *) callDec: (char **) lp end: (char **) rp;
- (char **) findAssign: (char **) p1 end: (char **) p2;
- (int) numberValue: (char *) s;
- (struct Tree *) arrayDecl: (char **) p1 args: (char **) lp end: (char **) rp;
- (struct Tree *) groupDecl: (char **) p1 args: (char **) lp end: (char **) rp;
- (struct Tree *) subscript: (char *) na args: (char **) lp end: (char **) rp;
- (struct Tree *) arrayInfo: (int) k args: (char **) lp end: (char **) rp;
- (void) stripDollar: (char *) s;
- (struct Tree *) doStatement: (char **) p1 end: (char **) p2;
- (struct Tree *) procDef: (char **) p1 end: (char **) p2;
- (struct Tree *) callStmt: (char **) p1 end: (char **) p2;
- (struct Tree *) argList: (char **) lp end: (char **) rp;
- (struct Tree *) literalDecl: (char *) na value: (char *) val;
- (char *) macroValue: (char *) na;
- (char *) resolveMacro: (char *) w;
- (char **) matchProc: (char **) p1 end: (char **) p2;
- (int) nameEq: (char *) a other: (char *) b;
- (struct Tree *) tree;
@end

@interface Shell (Miscellaneous)
- (void) printString: (const char *) as;
- (void) putCharacter: (int) c;
- (int) anyCharacter: (int) c in: (const char *) as;
- (void) error: (const char *) s code: (int) code;
- (char *) integerToASCII: (int) n;
- (int *) getTreeCount;
- (int *) getErrorValue;
- (char **) getLinePointer;
- (char **) getEndLinePointer;
- (char ***) getArgumentPointer;
- (char ***) getEndArgumentPointer;
- (int *) getPeekCharacter;
- (int *) getLabelCount;
- (int *) getSymbolCount;
- (int *) getScope;
- (int *) getRamPointer;
- (int *) getOrgFlag;
- (int *) getMacroCount;
- (int *) getLabCount;
- (int *) getProcCount;
- (int *) getInProc;
@end
#endif /* !SH_H */
