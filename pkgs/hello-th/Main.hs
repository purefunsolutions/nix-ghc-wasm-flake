{-# LANGUAGE TemplateHaskell #-}

-- | Each splice runs at compile time, in GHC's wasm interpreter (node + dyld.mjs).
module Main (main) where

import Greeting (greeting)
import Language.Haskell.TH (integerL, litE, stringE)

main :: IO ()
main = do
  -- Uses only template-haskell and base, i.e. GHC's own shared libraries.
  putStrLn $(stringE "Hello from Template Haskell!")
  -- Computed while compiling, not when the program runs.
  print $(litE (integerL (product [1 .. 20])))
  -- Calls a function from another module of this package at compile time.
  putStrLn $(greeting "wasm")
