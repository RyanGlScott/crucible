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
import Data.Foldable(toList)
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
  do sym <- getSymInterface
     h <- printHandle <$> getContext
     liftIO $ do
       hPutStrLn h "Attempting to prove all outstanding obligations!\n"

       obls <- proofGoalsToList <$> getProofObligations sym
       clearProofObligations sym

       forM_ obls $ \o ->
         do let asms = map (view labeledPred) $ toList $ proofAssumptions o
            gl <- notPred sym ((proofGoal o)^.labeledPred)
            let logData = defaultLogData { logCallbackVerbose = \_ -> hPutStrLn h
                                         , logReason = "assertion proof" }
            let msg = show $ ppSimError $ assertionSimError $ (proofGoal o)^.labeledPredMsg
            runZ3InOverride sym logData (asms ++ [gl]) $ \case
              Unsat{}  -> hPutStrLn h $ unlines ["Proof Succeeded!", msg]
              Sat _mdl -> hPutStrLn h $ unlines ["Proof failed!", msg]
              Unknown  -> hPutStrLn h $ unlines ["Proof inconclusive!", msg]
