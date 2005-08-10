#ifndef _SYMTAB_H_
#define _SYMTAB_H_

#include "chplenum.h"
#include "expr.h"
#include "stmt.h"
#include "symbol.h"
#include "symscope.h"


extern ModuleSymbol* commonModule;

class Symboltable {
 public:
  static void init(void);
  static void parsePrelude(void);
  static void doneParsingPreludes(void);
  static void doneParsingUserFiles(void);
  static bool parsingUserCode(void);

  static void traverse(SymtabTraversal* traversal);
  static void traverseFromScope(SymtabTraversal* traversal,
                                SymScope* scope);

  static void removeScope(SymScope* scope);
  static void pushScope(scopeType type);
  static SymScope* popScope(void);
  static SymScope* getCurrentScope(void);
  static SymScope* setCurrentScope(SymScope* newScope);
  static ModuleSymbol* getCurrentModule(void);
  static ModuleList* getModuleList(moduleSet modules);
  static FnSymbol* getCurrentFn(void);

  static void undefineInScope(Symbol* sym, SymScope* scope);
  static void defineInScope(Symbol* sym, SymScope* scope);
  static void define(Symbol* sym);

  /** SJD: These are the lookup's to use--
      lookupInScope only checks the passed scope
      lookupFromScope checks the passed scope and then moves up the scopes
  **/
  static Symbol* lookupInScope(char* name, SymScope* scope);
  static Symbol* lookupFromScope(char* name, SymScope* scope, 
                                 bool genError = false);

  static Symbol* lookupInCurrentScope(char* name);
  static Symbol* lookup(char* name, bool genError = false);

  static Symbol* lookupInternal(char* name, 
                                scopeType scope = SCOPE_PRELUDE);
  static TypeSymbol* lookupInternalType(char* name);

  static Expr* startLetExpr(void);
  static Expr* finishLetExpr(Expr* let_expr, AList<Stmt>* stmts, 
                             Expr* inner_expr);
  static BlockStmt* startCompoundStmt(void);
  static BlockStmt* finishCompoundStmt(BlockStmt* blkstmt, AList<Stmt>* body);
  static ModuleSymbol* startModuleDef(char* name, modType modtype = MOD_USER);
  static DefExpr* finishModuleDef(ModuleSymbol* mod, AList<Stmt>* def);
  static DefExpr* Symboltable::defineParam(paramType tag, char* ident,
                                           Expr* type, Expr* init);
  static AList<Stmt>* Symboltable::defineVarDef1(char* ident,
                                                 Expr* type, 
                                                 Expr* init);
  static void Symboltable::defineVarDef2(AList<Stmt>* stmts, varType vartag, 
                                         consType constag);
  static DefExpr* Symboltable::defineSingleVarDef(char* name, 
                                                  Type* type,
                                                  Expr* init,
                                                  varType vartag,
                                                  consType constag);
  static PrimitiveType* Symboltable::definePrimitiveType(char* name, char* cname, Expr* initExpr = NULL);
  static Type* Symboltable::defineBuiltinType(char* name, char* cname, Type* newType);
  static FnSymbol* startFnDef(FnSymbol* fnsym, bool noparens = false);
  static void continueFnDef(FnSymbol* fnsym, AList<DefExpr>* formals, 
                            Type* retType, bool isRef = false, Expr *whereExp = NULL);
  static FnSymbol* finishFnDef(FnSymbol* fnsym, BlockStmt* body, 
                               bool isExtern = true);
  static DefExpr* defineFunction(char* name, AList<DefExpr>* formals, 
                                 Type* retType, BlockStmt* body, 
                                 bool isExtern = false);

  static DefExpr* defineStructType(char* name, Type* type,
                                   SymScope* scope, AList<Stmt>* def);
  static ForallExpr* startForallExpr(AList<Expr>* indices, 
                                     AList<Expr>* iterators);
  static ForallExpr* finishForallExpr(ForallExpr* expr, 
                                      Expr* innerExpr = NULL);
  static ForLoopStmt* startForLoop(ForLoopStmtTag forLoopStmtTag,
                                   AList<Expr>* indices,
                                   AList<Expr>* iterators);
  static ForLoopStmt* finishForLoop(ForLoopStmt* stmt, Stmt* innerStmt);

  static void print(FILE* outfile = stderr);
  static void dump(FILE* outfile = stderr);
};

bool ModuleDefContainsOnlyNestedModules(AList<Stmt>* def);

#endif
