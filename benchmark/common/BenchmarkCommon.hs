{-# LANGUAGE CPP #-}

#include "MachDeps.h"
#define HDLSYN Other

module BenchmarkCommon where

import Clash.Annotations.BitRepresentation.Internal (CustomReprs, buildCustomReprs)
import Clash.Annotations.TopEntity
import Clash.Backend
import Clash.Backend.VHDL
import Clash.Core.TyCon
import Clash.Core.Type
import Clash.Core.Var
import Clash.Driver
import Clash.Driver.Types
import Clash.GHC.Evaluator (reduceConstant)
import Clash.GHC.GenerateBindings
import Clash.GHC.LoadModules (ghcLibDir)
import Clash.GHC.NetlistTypes
import Clash.Netlist.BlackBox.Types (HdlSyn(Other))
import Clash.Netlist.Types          (FilteredHWType)
import Clash.Primitives.Types

import Util (OverridingBool(..))

import qualified Control.Concurrent.Supply as Supply
import Data.IntMap.Strict           (IntMap)

defaultTests :: [FilePath]
defaultTests =
  [ "examples/FIR.hs"
  , "examples/Queens.hs"
  , "benchmark/tests/BundleMapRepeat.hs"
  , "benchmark/tests/PipelinesViaFolds.hs"
  ]

typeTrans :: (CustomReprs -> TyConMap -> Type -> Maybe (Either String FilteredHWType))
typeTrans = ghcTypeToHWType WORD_SIZE_IN_BITS True

opts :: [FilePath] -> ClashOpts
opts idirs =
  ClashOpts 20 20 15 0 DebugNone False True True Auto WORD_SIZE_IN_BITS Nothing
    HDLSYN True True idirs Nothing True True False Nothing

backend :: VHDLState
backend = initBackend WORD_SIZE_IN_BITS HDLSYN True Nothing

runInputStage
  :: [FilePath]
  -- ^ Import dirs
  -> FilePath
  -> IO (BindingMap
        ,TyConMap
        ,IntMap TyConName
        ,[(Id, Maybe TopEntity, Maybe Id)]
        ,CompiledPrimMap
        ,CustomReprs
        ,[Id]
        ,Id
        )
runInputStage idirs src = do
  pds <- primDirs backend
  (bindingsMap,tcm,tupTcm,topEntities,primMap,reprs) <- generateBindings Auto pds idirs (hdlKind backend) src Nothing
  let topEntityNames = map (\(x,_,_) -> x) topEntities
      ((topEntity,_,_):_) = topEntities
      tm = topEntity
  topDir   <- ghcLibDir
  primMap2 <- sequence $ fmap (sequence . fmap (compilePrimitive [] [] topDir)) primMap
  return (bindingsMap,tcm,tupTcm,topEntities, primMap2, buildCustomReprs reprs, topEntityNames,tm)

runNormalisationStage
  :: [FilePath]
  -> String
  -> IO (BindingMap
        ,[(Id, Maybe TopEntity, Maybe Id)]
        ,CompiledPrimMap
        ,TyConMap
        ,CustomReprs
        ,Id
        )
runNormalisationStage idirs src = do
  supplyN <- Supply.newSupply
  (bindingsMap,tcm,tupTcm,topEntities,primMap,reprs,topEntityNames,topEntity) <-
    runInputStage idirs src
  let opts1 = opts idirs
      transformedBindings =
        normalizeEntity reprs bindingsMap primMap tcm tupTcm typeTrans reduceConstant
          topEntityNames opts1 supplyN topEntity
  return (transformedBindings,topEntities,primMap,tcm,reprs,topEntity)
