{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Embeds files at compile time. The splices run in GHC's wasm interpreter
-- (node + dyld.mjs), so this module must not depend on JSFFI.
module Embed (embedFirstFile, embedMesh) where

import Control.Exception (IOException, try)
import qualified Data.ByteString as B
import GHC.Ptr (Ptr (..))
import Glb (Mesh (..), indexBytes, parseGlb, vertexBytes)
import Language.Haskell.TH (Exp, Q, litE, runIO, stringL, stringPrimL)
import Language.Haskell.TH.Syntax (addDependentFile, lift)
import System.IO (IOMode (ReadMode), hGetContents', hSetEncoding, utf8, withFile)

-- | The contents of the first of the given files that can be read, as a
-- string literal.
embedFirstFile :: [FilePath] -> Q Exp
embedFirstFile paths = do
  (path, contents) <- runIO (firstReadable paths)
  addDependentFile path
  litE (stringL contents)

firstReadable :: [FilePath] -> IO (FilePath, String)
firstReadable [] = ioError (userError "embedFirstFile: none of the files can be read")
firstReadable (path : rest) = do
  result <- try (withFile path ReadMode (\h -> hSetEncoding h utf8 >> hGetContents' h))
  case result of
    Right contents -> pure (path, contents)
    Left (_ :: IOException) -> firstReadable rest

-- | A .glb mesh, parsed at compile time and baked into the program's data
-- as WebGL-ready bytes: (vertices, their size in bytes, indices, how many).
embedMesh :: FilePath -> Q Exp
embedMesh path = do
  addDependentFile path
  glb <- runIO (B.readFile path)
  mesh <- either fail pure (parseGlb glb)
  let vertices = vertexBytes mesh
  [|
    ( Ptr $(litE (stringPrimL vertices))
    , $(lift (length vertices))
    , Ptr $(litE (stringPrimL (indexBytes mesh)))
    , $(lift (length (meshIndices mesh)))
    )
    |]
