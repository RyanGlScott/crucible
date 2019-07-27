-- |
-- Module           : Lang.Crucible.LLVM.Intrinsics.Libc
-- Description      : Override definitions for C standard library functions
-- Copyright        : (c) Galois, Inc 2015-2019
-- License          : BSD3
-- Maintainer       : Rob Dockins <rdockins@galois.com>
-- Stability        : provisional
------------------------------------------------------------------------

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE ImpredicativeTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

module Lang.Crucible.LLVM.Intrinsics.Libc where

import           Control.Lens ((^.), _1, _2, _3)
import qualified Codec.Binary.UTF8.Generic as UTF8
import           Control.Monad.Reader
import           Control.Monad.State
import qualified Data.Char as DC
import qualified Data.Foldable as F
import qualified Data.Vector as V
import           System.IO
import qualified Text.LLVM.AST as L

import           Data.Parameterized.Context ( pattern (:>), pattern Empty )
import qualified Data.Parameterized.Context as Ctx

import           What4.Interface
import           What4.ProgramLoc (plSourceLoc)

import           Lang.Crucible.Backend
import           Lang.Crucible.CFG.Common
import           Lang.Crucible.Types
import           Lang.Crucible.Simulator.ExecutionTree
import           Lang.Crucible.Simulator.OverrideSim
import           Lang.Crucible.Simulator.RegMap
import           Lang.Crucible.Simulator.SimError

import           Lang.Crucible.LLVM.Bytes
import           Lang.Crucible.LLVM.DataLayout
import           Lang.Crucible.LLVM.Extension
import           Lang.Crucible.LLVM.MemModel
import qualified Lang.Crucible.LLVM.MemModel.Type as G
import qualified Lang.Crucible.LLVM.MemModel.Generic as G
import           Lang.Crucible.LLVM.Printf
import           Lang.Crucible.LLVM.Types (pattern SizeT)
import           Lang.Crucible.LLVM.TypeContext

import           Lang.Crucible.LLVM.Intrinsics.Common

------------------------------------------------------------------------
-- ** Declarations


llvmMemcpyOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
           (EmptyCtx ::> LLVMPointerType wptr
                     ::> LLVMPointerType wptr
                     ::> BVType wptr)
           (LLVMPointerType wptr)
llvmMemcpyOverride =
  let nm = "memcpy" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType (L.Integer 8)
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType (L.Integer 8)
                     , L.PtrTo $ L.PrimType (L.Integer 8)
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> PtrRepr :> SizeT)
  PtrRepr
  (\memOps sym args ->
     do volatile <- liftIO $ RegEntry knownRepr <$> bvLit sym knownNat 0
        Ctx.uncurryAssignment (callMemcpy sym memOps)
                              (args :> volatile)
        return $ regValue $ args^._1 -- return first argument
  )


llvmMemcpyChkOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr
                   ::> LLVMPointerType wptr
                   ::> BVType wptr
                   ::> BVType wptr)
         (LLVMPointerType wptr)
llvmMemcpyChkOverride =
  let nm = "__memcpy_chk" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType (L.Integer 8)
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType (L.Integer 8)
                     , L.PtrTo $ L.PrimType (L.Integer 8)
                     , llvmSizeT
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> PtrRepr :> SizeT :> SizeT)
  PtrRepr
  (\memOps sym args ->
    do let args' = Ctx.empty :> (args^._1) :> (args^._2) :> (args^._3)
       volatile <- liftIO $ RegEntry knownRepr <$> bvLit sym knownNat 0
       Ctx.uncurryAssignment (callMemcpy sym memOps)
                             (args' :> volatile)
       return $ regValue $ args^._1 -- return first argument
  )

llvmMemmoveOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> (LLVMPointerType wptr)
                   ::> (LLVMPointerType wptr)
                   ::> BVType wptr)
         (LLVMPointerType wptr)
llvmMemmoveOverride =
  let nm = "memmove" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType (L.Integer 8)
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType (L.Integer 8)
                     , L.PtrTo $ L.PrimType (L.Integer 8)
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> PtrRepr :> SizeT)
  PtrRepr
  (\memOps sym args ->
    do volatile <- liftIO (RegEntry knownRepr <$> bvLit sym knownNat 0)
       Ctx.uncurryAssignment (callMemmove sym memOps)
                             (args :> volatile)
       return $ regValue $ args^._1 -- return first argument
  )

llvmMemsetOverride :: forall p sym arch wptr.
     (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr
                   ::> BVType 32
                   ::> BVType wptr)
         (LLVMPointerType wptr)
llvmMemsetOverride =
  let nm = "memset" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType (L.Integer 8)
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType (L.Integer 8)
                     , L.PrimType $ L.Integer 32
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> KnownBV @32 :> SizeT)
  PtrRepr
  (\memOps sym args ->
    do LeqProof <- return (leqTrans @9 @16 @wptr LeqProof LeqProof)
       let dest = args^._1
       val <- liftIO (RegEntry knownRepr <$> bvTrunc sym (knownNat @8) (regValue (args^._2)))
       let len = args^._3
       volatile <- liftIO
          (RegEntry knownRepr <$> bvLit sym knownNat 0)
       callMemset sym memOps dest val len volatile
       return (regValue dest)
  )

llvmMemsetChkOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr
                 ::> BVType 32
                 ::> BVType wptr
                 ::> BVType wptr)
         (LLVMPointerType wptr)
llvmMemsetChkOverride =
  let nm = "__memset_chk" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType (L.Integer 8)
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType (L.Integer 8)
                     , L.PrimType $ L.Integer 32
                     , llvmSizeT
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> KnownBV @32 :> SizeT :> SizeT)
  PtrRepr
  (\memOps sym args ->
    do let dest = args^._1
       val <- liftIO
            (RegEntry knownRepr <$> bvTrunc sym knownNat (regValue (args^._2)))
       let len = args^._3
       volatile <- liftIO
          (RegEntry knownRepr <$> bvLit sym knownNat 0)
       callMemset sym memOps dest val len volatile
       return (regValue dest)
  )

------------------------------------------------------------------------
-- *** Allocation

llvmCallocOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch, ?lc :: TypeContext)
  => LLVMOverride p sym arch
         (EmptyCtx ::> BVType wptr ::> BVType wptr)
         (LLVMPointerType wptr)
llvmCallocOverride =
  let nm = "calloc" in
  let alignment = maxAlignment (llvmDataLayout ?lc) in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType $ L.Integer 8
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ llvmSizeT
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> SizeT :> SizeT)
  PtrRepr
  (\memOps sym args -> Ctx.uncurryAssignment (callCalloc sym memOps alignment) args)


llvmReallocOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch, ?lc :: TypeContext)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr ::> BVType wptr)
         (LLVMPointerType wptr)
llvmReallocOverride =
  let nm = "realloc" in
  let alignment = maxAlignment (llvmDataLayout ?lc) in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType $ L.Integer 8
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> SizeT)
  PtrRepr
  (\memOps sym args -> Ctx.uncurryAssignment (callRealloc sym memOps alignment) args)

llvmMallocOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch, ?lc :: TypeContext)
  => LLVMOverride p sym arch
         (EmptyCtx ::> BVType wptr)
         (LLVMPointerType wptr)
llvmMallocOverride =
  let nm = "malloc" in
  let alignment = maxAlignment (llvmDataLayout ?lc) in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType $ L.Integer 8
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> SizeT)
  PtrRepr
  (\memOps sym args -> Ctx.uncurryAssignment (callMalloc sym memOps alignment) args)

posixMemalign ::
  (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch, ?lc :: TypeContext) =>
  LLVMOverride p sym arch
      (EmptyCtx ::> LLVMPointerType wptr
                ::> BVType wptr
                ::> BVType wptr)
      (BVType 32)
posixMemalign =
  let nm = "posix_memalign" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PtrTo $  L.PrimType $ L.Integer 8
                     , llvmSizeT
                     , llvmSizeT
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> SizeT :> SizeT)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (callPosixMemalign sym memOps) args)


llvmFreeOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr)
         UnitType
llvmFreeOverride =
  let nm = "free" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType L.Void
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr)
  UnitRepr
  (\memOps sym args -> Ctx.uncurryAssignment (callFree sym memOps) args)

------------------------------------------------------------------------
-- *** Strings and I/O

llvmSnprintfOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr
                   ::> BVType wptr
                   ::> LLVMPointerType wptr
                   ::> VectorType AnyType)
         (BVType 32)
llvmSnprintfOverride =
  let nm = "snprintf" in
  LLVMOverride
  ( L.Declare
   { L.decRetType = L.PrimType (L.Integer 32)
   , L.decName = L.Symbol nm
   , L.decArgs = [ L.PtrTo (L.PrimType (L.Integer 8))
                 , llvmSizeT
                 , L.PtrTo (L.PrimType (L.Integer 8))
                 ]
   , L.decVarArgs = True
   , L.decAttrs = []
   , L.decComdat = mempty
   }
  )
  (Empty :> PtrRepr :> SizeT :> PtrRepr :> VectorRepr AnyRepr)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (callSnprintf sym memOps) args)

llvmPrintfOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> LLVMPointerType wptr
                   ::> VectorType AnyType)
         (BVType 32)
llvmPrintfOverride =
  let nm = "printf" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = True
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> VectorRepr AnyRepr)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (callPrintf sym memOps) args)

llvmPrintfChkOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
         (EmptyCtx ::> BVType 32
                   ::> LLVMPointerType wptr
                   ::> VectorType AnyType)
         (BVType 32)
llvmPrintfChkOverride =
  let nm = "__printf_chk" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PrimType $ L.Integer 32
                     , L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = True
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> KnownBV @32 :> PtrRepr :> VectorRepr AnyRepr)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (\_flg -> callPrintf sym memOps) args)


llvmPutCharOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch (EmptyCtx ::> BVType 32) (BVType 32)
llvmPutCharOverride =
  let nm = "putchar" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PrimType $ L.Integer 32
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> KnownBV @32)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (callPutChar sym memOps) args)


llvmPutsOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch (EmptyCtx ::> LLVMPointerType wptr) (BVType 32)
llvmPutsOverride =
  let nm = "puts" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr)
  (KnownBV @32)
  (\memOps sym args -> Ctx.uncurryAssignment (callPuts sym memOps) args)

llvmStrlenOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch (EmptyCtx ::> LLVMPointerType wptr) (BVType wptr)
llvmStrlenOverride =
  let nm = "strlen" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = llvmSizeT
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr)
  SizeT
  (\memOps sym args -> Ctx.uncurryAssignment (callStrlen sym memOps) args)

------------------------------------------------------------------------
-- ** Implementations

------------------------------------------------------------------------
-- *** Allocation

callRealloc
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> Alignment
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (LLVMPointerType wptr))
callRealloc sym mvar alignment (regValue -> ptr) (regValue -> sz) =
  do szZero  <- liftIO (notPred sym =<< bvIsNonzero sym sz)
     ptrNull <- liftIO (ptrIsNull sym PtrWidth ptr)
     symbolicBranches emptyRegMap
       -- If the pointer is null, behave like malloc
       [ (ptrNull
         , do mem <- readGlobal mvar
              (newp, mem') <- liftIO $ doMalloc sym G.HeapAlloc G.Mutable "<realloc>" mem sz alignment
              writeGlobal mvar mem'
              return newp
         ,
         Nothing)

       -- If the size is zero, behave like malloc (of zero bytes) then free
       , (szZero
         , do mem <- readGlobal mvar
              (newp, mem') <- liftIO $
                do (newp, mem1) <- doMalloc sym G.HeapAlloc G.Mutable "<realloc>" mem sz alignment
                   mem2 <- doFree sym mem1 ptr
                   return (newp, mem2)
              writeGlobal mvar mem'
              return newp
         , Nothing
         )

       -- Otherwise, allocate a new region, memcopy `sz` bytes and free the old pointer
       , (truePred sym
         , do mem  <- readGlobal mvar
              (newp, mem') <- liftIO $
                do (newp, mem1) <- doMalloc sym G.HeapAlloc G.Mutable "<realloc>" mem sz alignment
                   mem2 <- uncheckedMemcpy sym mem1 newp ptr sz
                   mem3 <- doFree sym mem2 ptr
                   return (newp, mem3)
              writeGlobal mvar mem'
              return newp
         , Nothing)
       ]


callPosixMemalign
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch, ?lc :: TypeContext)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType wptr)
  -> RegEntry sym (BVType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType 32))
callPosixMemalign sym mvar (regValue -> outPtr) (regValue -> align) (regValue -> sz) =
  case asUnsignedBV align >>= toAlignment . toBytes of
    Nothing -> fail $ unwords ["posix_memalign: invalid alignment value:", show (printSymExpr align)]
    Just a ->
      do let dl = llvmDataLayout ?lc

         mem <- readGlobal mvar
         mem'' <- liftIO $
           do loc <- plSourceLoc <$> getCurrentProgramLoc sym
              (p, mem') <- doMalloc sym G.HeapAlloc G.Mutable (show loc) mem sz a
              storeRaw sym mem' outPtr (bitvectorType (dl^.ptrSize)) (dl^.ptrAlign) (ptrToPtrVal p)
         writeGlobal mvar mem''

         liftIO $ bvLit sym knownNat 0

callMalloc
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> Alignment
  -> RegEntry sym (BVType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (LLVMPointerType wptr))
callMalloc sym mvar alignment (regValue -> sz) = do
  --liftIO $ putStrLn "MEM MALLOC"
  mem <- readGlobal mvar
  loc <- liftIO $ plSourceLoc <$> getCurrentProgramLoc sym
  (p, mem') <- liftIO $ doMalloc sym G.HeapAlloc G.Mutable (show loc) mem sz alignment
  writeGlobal mvar mem'
  return p


callCalloc
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> Alignment
  -> RegEntry sym (BVType wptr)
  -> RegEntry sym (BVType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (LLVMPointerType wptr))
callCalloc sym mvar alignment
           (regValue -> sz)
           (regValue -> num) = do
  --liftIO $ putStrLn "MEM CALLOC"
  mem <- readGlobal mvar
  (p, mem') <- liftIO $ doCalloc sym mem sz num alignment
  writeGlobal mvar mem'
  return p


callFree
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret ()
callFree sym mvar
           (regValue -> ptr) = do
  --liftIO $ putStrLn "MEM FREE"
  mem <- readGlobal mvar
  mem' <- liftIO $ doFree sym mem ptr
  writeGlobal mvar mem'

------------------------------------------------------------------------
-- *** Memory manipulation

callMemcpy
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType w)
  -> RegEntry sym (BVType 1)
  -> OverrideSim p sym (LLVM arch) r args ret ()
callMemcpy sym mvar
           (regValue -> dest)
           (regValue -> src)
           (RegEntry (BVRepr w) len)
           _volatile = do
  -- FIXME? add assertions about alignment
  --liftIO $ putStrLn "MEM COPY"
  mem <- readGlobal mvar
  liftIO $ assertDisjointRegions sym w dest src len
  mem' <- liftIO $ doMemcpy sym w mem dest src len
  writeGlobal mvar mem'

-- NB the only difference between memcpy and memove
-- is that memmove does not assert that the memory
-- ranges are disjoint.  The underlying operation
-- works correctly in both cases.
callMemmove
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType w)
  -> RegEntry sym (BVType 1)
  -> OverrideSim p sym (LLVM arch) r args ret ()
callMemmove sym mvar
           (regValue -> dest)
           (regValue -> src)
           (RegEntry (BVRepr w) len)
           _volatile = do
  -- FIXME? add assertions about alignment
  --liftIO $ putStrLn "MEM MOVE"
  mem <- readGlobal mvar
  mem' <- liftIO $ doMemcpy sym w mem dest src len
  writeGlobal mvar mem'

callMemset
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType 8)
  -> RegEntry sym (BVType w)
  -> RegEntry sym (BVType 1)
  -> OverrideSim p sym (LLVM arch) r args ret ()
callMemset sym mvar
           (regValue -> dest)
           (regValue -> val)
           (RegEntry (BVRepr w) len)
           _volatile = do
  -- FIXME? add assertions about alignment
  --liftIO $ putStrLn "MEM SET"
  mem <- readGlobal mvar
  mem' <- liftIO $ doMemset sym w mem dest val len
  writeGlobal mvar mem'

------------------------------------------------------------------------
-- *** Strings and I/O

callPutChar
  :: (IsSymInterface sym, HasPtrWidth wptr)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (BVType 32)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType 32))
callPutChar _sym _mvar
 (regValue -> ch) = do
    h <- printHandle <$> getContext
    let chval = maybe '?' (toEnum . fromInteger) (asUnsignedBV ch)
    liftIO $ hPutChar h chval
    return ch

callPuts
  :: (IsSymInterface sym, HasPtrWidth wptr)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType 32))
callPuts sym mvar
  (regValue -> strPtr) = do
    mem <- readGlobal mvar
    str <- liftIO $ loadString sym mem strPtr Nothing
    h <- printHandle <$> getContext
    liftIO $ hPutStrLn h (UTF8.toString str)
    -- return non-negative value on success
    liftIO $ bvLit sym knownNat 1

callStrlen
  :: (IsSymInterface sym, HasPtrWidth wptr)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType wptr))
callStrlen sym mvar (regValue -> strPtr) = do
  mem <- readGlobal mvar
  liftIO $ strLen sym mem strPtr

callSnprintf
  :: forall sym wptr p arch r args ret
    . (IsSymInterface sym, HasPtrWidth wptr)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (BVType wptr)
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (VectorType AnyType)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType 32))
callSnprintf sym mvar (regValue -> dstPtr) (regValue -> dstLen) (regValue -> strPtr) (regValue -> valist) = do
  mem <- readGlobal mvar
  formatStr <- liftIO $ loadString sym mem strPtr Nothing
  case parseDirectives formatStr of
    Left err -> overrideError (AssertFailureSimError err)
    Right ds -> do
      ((str, n), mem') <- liftIO $ runStateT (executeDirectives (printfOps sym valist) ds) mem
      zero <- liftIO $ bvLit sym (knownNat @8) 0
      arr0 <- liftIO $ constantArray sym (Empty :> BaseBVRepr ?ptrWidth) zero
      symArr <- liftIO $ F.foldrM copyCharToArray arr0 (zip [0..] str)
      mem'' <- liftIO $ doArrayStore sym mem' dstPtr noAlignment symArr dstLen
      writeGlobal mvar mem''
      liftIO $ bvLit sym (knownNat @32) (fromIntegral n)
  where
    copyCharToArray :: (Int, Char)
                    -> SymArray sym (SingleCtx (BaseBVType wptr)) (BaseBVType 8)
                    -> IO (SymArray sym (SingleCtx (BaseBVType wptr)) (BaseBVType 8))
    copyCharToArray (charIdx, chr) arr = do
      bv8 <- bvLit sym (knownNat @8) (fromIntegral (DC.ord chr))
      idx <- bvLit sym ?ptrWidth (fromIntegral charIdx)
      arrayUpdate sym arr (Empty :> idx) bv8


callPrintf
  :: (IsSymInterface sym, HasPtrWidth wptr)
  => sym
  -> GlobalVar Mem
  -> RegEntry sym (LLVMPointerType wptr)
  -> RegEntry sym (VectorType AnyType)
  -> OverrideSim p sym (LLVM arch) r args ret (RegValue sym (BVType 32))
callPrintf sym mvar
  (regValue -> strPtr)
  (regValue -> valist) = do
    mem <- readGlobal mvar
    formatStr <- liftIO $ loadString sym mem strPtr Nothing
    case parseDirectives formatStr of
      Left err -> overrideError $ AssertFailureSimError err
      Right ds -> do
        ((str, n), mem') <- liftIO $ runStateT (executeDirectives (printfOps sym valist) ds) mem
        writeGlobal mvar mem'
        h <- printHandle <$> getContext
        liftIO $ hPutStr h str
        liftIO $ bvLit sym knownNat (toInteger n)

printfOps :: (IsSymInterface sym, HasPtrWidth wptr)
          => sym
          -> V.Vector (AnyValue sym)
          -> PrintfOperations (StateT (MemImpl sym) IO)
printfOps sym valist =
  PrintfOperations
  { printfUnsupported = \x -> lift $ addFailedAssertion sym
                                   $ Unsupported x

  , printfGetInteger = \i sgn _len ->
     case valist V.!? (i-1) of
       Just (AnyValue (LLVMPointerRepr _w) x) ->
         do bv <- liftIO (projectLLVM_bv sym x)
            if sgn then
              return $ asSignedBV bv
            else
              return $ asUnsignedBV bv
       Just (AnyValue tpr _) ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Type mismatch in printf.  Expected integer, but got:"
                        , show tpr]
       Nothing ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Out-of-bounds argument access in printf:", show i]

  , printfGetFloat = \i _len ->
     case valist V.!? (i-1) of
       Just (AnyValue (FloatRepr _fi) _x) ->
         -- TODO: handle interpreted floats
         return Nothing
       Just (AnyValue tpr _) ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords [ "Type mismatch in printf."
                        , "Expected floating-point, but got:", show tpr]
       Nothing ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Out-of-bounds argument access in printf:", show i]

  , printfGetString  = \i numchars ->
     case valist V.!? (i-1) of
       Just (AnyValue PtrRepr ptr) ->
           do mem <- get
              liftIO $ loadString sym mem ptr numchars
       Just (AnyValue tpr _) ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords [ "Type mismatch in printf."
                        , "Expected char*, but got:", show tpr]
       Nothing ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Out-of-bounds argument access in printf:", show i]

  , printfGetPointer = \i ->
     case valist V.!? (i-1) of
       Just (AnyValue PtrRepr ptr) ->
         return $ show (G.ppPtr ptr)
       Just (AnyValue tpr _) ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords [ "Type mismatch in printf."
                        , "Expected void*, but got:", show tpr]
       Nothing ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Out-of-bounds argument access in printf:", show i]

  , printfSetInteger = \i len v ->
     case valist V.!? (i-1) of
       Just (AnyValue PtrRepr ptr) ->
         do mem <- get
            case len of
              Len_Byte  -> do
                 let w8 = knownNat :: NatRepr 8
                 let tp = G.bitvectorType 1
                 x <- liftIO (llvmPointer_bv sym =<< bvLit sym w8 (toInteger v))
                 mem' <- liftIO $ doStore sym mem ptr (LLVMPointerRepr w8) tp noAlignment x
                 put mem'
              Len_Short -> do
                 let w16 = knownNat :: NatRepr 16
                 let tp = G.bitvectorType 2
                 x <- liftIO (llvmPointer_bv sym =<< bvLit sym w16 (toInteger v))
                 mem' <- liftIO $ doStore sym mem ptr (LLVMPointerRepr w16) tp noAlignment x
                 put mem'
              Len_NoMod -> do
                 let w32  = knownNat :: NatRepr 32
                 let tp = G.bitvectorType 4
                 x <- liftIO (llvmPointer_bv sym =<< bvLit sym w32 (toInteger v))
                 mem' <- liftIO $ doStore sym mem ptr (LLVMPointerRepr w32) tp noAlignment x
                 put mem'
              Len_Long  -> do
                 let w64 = knownNat :: NatRepr 64
                 let tp = G.bitvectorType 8
                 x <- liftIO (llvmPointer_bv sym =<< bvLit sym w64 (toInteger v))
                 mem' <- liftIO $ doStore sym mem ptr (LLVMPointerRepr w64) tp noAlignment x
                 put mem'
              _ ->
                lift $ addFailedAssertion sym
                     $ Unsupported
                     $ unwords ["Unsupported size modifier in %n conversion:", show len]

       Just (AnyValue tpr _) ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords [ "Type mismatch in printf."
                        , "Expected void*, but got:", show tpr]

       Nothing ->
         lift $ addFailedAssertion sym
              $ AssertFailureSimError
              $ unwords ["Out-of-bounds argument access in printf:", show i]
  }

------------------------------------------------------------------------
-- *** Other

llvmAssertRtnOverride
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
        (EmptyCtx ::> LLVMPointerType wptr
                  ::> LLVMPointerType wptr
                  ::> BVType 32
                  ::> LLVMPointerType wptr)
        UnitType
llvmAssertRtnOverride =
  let nm = "__assert_rtn" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType L.Void
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     , L.PtrTo $ L.PrimType $ L.Integer 8
                     , L.PrimType $ L.Integer 32
                     , L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> PtrRepr :> KnownBV @32 :> PtrRepr)
  UnitRepr
  (\_ sym _args ->
       do let err = AssertFailureSimError "Call to __assert_rtn"
          liftIO $ assert sym (falsePred sym) err
  )

llvmGetenv
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
        (EmptyCtx ::> LLVMPointerType wptr)
        (LLVMPointerType wptr)
llvmGetenv =
  let nm = "getenv" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PtrTo $ L.PrimType $ L.Integer 8
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr)
  PtrRepr
  (\_ sym _args -> liftIO $ mkNullPointer sym PtrWidth)

----------------------------------------------------------------------------
-- atexit stuff

cxa_atexit
  :: (IsSymInterface sym, HasPtrWidth wptr, wptr ~ ArchWidth arch)
  => LLVMOverride p sym arch
        (EmptyCtx ::> LLVMPointerType wptr ::> LLVMPointerType wptr ::> LLVMPointerType wptr)
        (BVType 32)
cxa_atexit =
  let nm = "__cxa_atexit" in
  LLVMOverride
  ( L.Declare
    { L.decRetType = L.PrimType $ L.Integer 32
    , L.decName    = L.Symbol nm
    , L.decArgs    = [ L.PtrTo $ L.FunTy (L.PrimType L.Void) [L.PtrTo $ L.PrimType $ L.Integer 8] False
                     , L.PtrTo $ L.PrimType $ L.Integer 8
                     , L.PtrTo $ L.PrimType $ L.Integer 8
                     ]
    , L.decVarArgs = False
    , L.decAttrs   = []
    , L.decComdat  = mempty
    }
  )
  (Empty :> PtrRepr :> PtrRepr :> PtrRepr)
  (KnownBV @32)
  (\_ sym _args -> liftIO $ bvLit sym knownNat 0)
