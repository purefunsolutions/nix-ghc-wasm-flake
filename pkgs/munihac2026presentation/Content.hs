{-# LANGUAGE MagicHash #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Files embedded at compile time by Template Haskell.
module Content (slidesSource, readmeSource, lambdaMesh) where

import Data.Word (Word8)
import Embed (embedFirstFile, embedMesh)
import GHC.Ptr (Ptr)

-- | The slides, in the small Markdown dialect of "Markdown".
slidesSource :: String
slidesSource = $(embedFirstFile ["slides.md"])

-- | The repository's README.md, for its upstream tracker. The Nix build
-- copies it next to the cabal file.
readmeSource :: String
readmeSource = $(embedFirstFile ["README.md", "../../README.md"])

-- | The lambda from lambda.glb: vertex bytes and their size, index bytes and
-- the number of indices.
lambdaMesh :: (Ptr Word8, Int, Ptr Word8, Int)
lambdaMesh = $(embedMesh "lambda.glb")
