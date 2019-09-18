{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE BangPatterns #-}
module Language.Haskell.Liquid.Synthesize.Check (check, hasType) where


import Language.Fixpoint.Types.Constraints
import qualified Language.Fixpoint.Types.Config as F 
import qualified Language.Fixpoint.Types as F 
import Language.Fixpoint.Solver

import Language.Haskell.Liquid.Types.Types 
import Language.Haskell.Liquid.Types.Specs 
import Language.Haskell.Liquid.Constraint.Env 
import Language.Haskell.Liquid.Constraint.Generate 
import Language.Haskell.Liquid.Constraint.Types 
import Language.Haskell.Liquid.Constraint.ToFixpoint
import Language.Haskell.Liquid.Synthesize.Monad
import Language.Haskell.Liquid.Synthesize.GHC
import Language.Haskell.Liquid.GHC.Misc (showPpr)
import Language.Haskell.Liquid.Misc (mapThd3)

import CoreSyn 
import Var 

import Control.Monad.State.Lazy

hasType :: SpecType -> CoreExpr -> SM Bool
hasType t !e' = do 
  x  <- freshVar t 
  st <- get 
  r <- liftIO $ check (sCGI st) (sCGEnv st) (sFCfg st) x e t 
  -- liftIO $ putStrLn ("Checked:  Expr = " ++ showPpr (fst $ fromAnf e []) ++ " of type " ++ show t ++ "\n Res = " ++ show r)
  return r 
 where e = tx e' 

{-
tx turns 
let x1 = 
    let x2 = 
      let x3 = e3 in 
      e2[x3] in 
    e1[x2] in 
e[x1]
into 
let x3 = e3     in 
let x2 = e2[x3] in 
let x1 = e1[x2] in
e[x1] 

so that the refinement type of e can refer to all bindings x1, x2, x3
-}

tx :: CoreExpr -> CoreExpr
tx (Case e b t alts) = Case e b t (mapThd3 tx <$> alts)
tx e@(Let _ _) = let (bs,e') = unbind e in foldr Let e' bs 
tx e = e 

unbind :: CoreExpr -> ([CoreBind], CoreExpr)
unbind (Let (NonRec x ex) e) = let (bs,e') = unbind ex in (bs ++ [NonRec x e'],e)
unbind e = ([], e)


check :: CGInfo -> CGEnv -> F.Config -> Var -> CoreExpr -> SpecType -> IO Bool 
check cgi γ cfg x e t = do 
    finfo <- cgInfoFInfo info' cs
    isSafe <$> solve cfg{F.srcFile = "SCheck" <> F.srcFile cfg} finfo 
  where 
    cs = generateConstraintsWithEnv info' cgi (γ{grtys = insertREnv (F.symbol x) t (grtys γ)}) 
    info' = info {giSrc = giSrc', giSpec = giSpec'}
    giSrc' = (giSrc info) {giCbs = [Rec [(x, e)]]}
    giSpec' = giSpecOld{gsSig = gsSig'}
    giSpecOld = giSpec info 
    gsSigOld  = gsSig giSpecOld
    gsSig' = gsSigOld {gsTySigs = (x,dummyLoc t):(gsTySigs gsSigOld)}
    info = ghcI cgi 


