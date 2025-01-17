{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Lang.Crucible.Syntax.Overrides
  ( setupOverrides
  ) where

import Control.Lens hiding ((:>), Empty)
import Control.Monad (forM_)
import Control.Monad.IO.Class
import System.IO

import Data.Parameterized.Context hiding (view)

import What4.Expr.Builder
import What4.Interface
import What4.ProgramLoc
import What4.SatResult
import What4.Solver (LogData(..), defaultLogData)
import What4.Solver.Z3 (runZ3InOverride)

import Lang.Crucible.Backend
import Lang.Crucible.Types
import Lang.Crucible.FunctionHandle
import Lang.Crucible.Simulator


setupOverrides ::
  (IsSymInterface sym, sym ~ (ExprBuilder t st fs)) =>
  sym -> HandleAllocator -> IO [(FnBinding p sym ext, Position)]
setupOverrides _ ha =
  do f1 <- FnBinding <$> mkHandle ha "proveObligations"
                     <*> pure (UseOverride (mkOverride "proveObligations" proveObligations))

     return [(f1, InternalPos)]


proveObligations :: (IsSymInterface sym, sym ~ (ExprBuilder t st fs)) =>
  OverrideSim p sym ext r EmptyCtx UnitType (RegValue sym UnitType)
proveObligations =
  ovrWithBackend $ \bak ->
  do let sym = backendGetSym bak
     h <- printHandle <$> getContext
     liftIO $ do
       hPutStrLn h "Attempting to prove all outstanding obligations!\n"

       obls <- maybe [] goalsToList <$> getProofObligations bak
       clearProofObligations bak

       forM_ obls $ \o ->
         do asms <- assumptionsPred sym (proofAssumptions o)
            gl <- notPred sym (o ^. to proofGoal.labeledPred)
            let logData = defaultLogData { logCallbackVerbose = \_ -> hPutStrLn h
                                         , logReason = "assertion proof" }
            runZ3InOverride sym logData [asms,gl] $ \case
              Unsat{}  -> hPutStrLn h $ unlines ["Proof Succeeded!", show $ ppSimError $ (proofGoal o)^.labeledPredMsg]
              Sat _mdl -> hPutStrLn h $ unlines ["Proof failed!", show $ ppSimError $ (proofGoal o)^.labeledPredMsg]
              Unknown  -> hPutStrLn h $ unlines ["Proof inconclusive!", show $ ppSimError $ (proofGoal o)^.labeledPredMsg]
