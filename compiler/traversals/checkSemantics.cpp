#include "checkSemantics.h"
#include "expr.h"


void CheckSemantics::preProcessExpr(Expr* expr) {
  if (ParenOpExpr* parenOpExpr = dynamic_cast<ParenOpExpr*>(expr)) {
    if (parenOpExpr->opTag >= OP_GETSNORM) {
      if (parenOpExpr->get(1)->isConst() || parenOpExpr->get(1)->isParam()) {
        USR_FATAL(parenOpExpr, "Assigning to a constant expression");
      }
    }
  }

  if (DefExpr* defExpr = dynamic_cast<DefExpr*>(expr)) {
    if (defExpr->sym->isParam()) {
      if (defExpr->init && !dynamic_cast<IntLiteral*>(defExpr->init)) {
        USR_FATAL(defExpr, "Initializing parameter to a variable expression.");
      }
    }
  }
}

