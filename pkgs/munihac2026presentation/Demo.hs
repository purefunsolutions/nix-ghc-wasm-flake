-- | The live demo: facts about the running program, computed in the browser.
module Demo (livePanel, startTicker) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (evaluate)
import Control.Monad (forever, void)
import Data.Version (showVersion)
import Dom (now, pageBytes, setTextIfPresent, wasmBytes)
import Numeric (showFFloat)
import System.Info (arch, fullCompilerVersion, os)

-- | Starts a Haskell thread that updates the uptime on the live slide every
-- second. Under JSFFI, threadDelay is a JavaScript setTimeout.
startTicker :: Double -> IO ()
startTicker started = void . forkIO . forever $ do
  threadDelay 1000000
  uptime started >>= setTextIfPresent "uptime"

uptime :: Double -> IO String
uptime started = do
  t <- now
  pure (show (round ((t - started) / 1000) :: Int) ++ " s")

-- | The panel, given when the program started, n for n!, and how many rows
-- the README's tracker has.
livePanel :: Double -> Integer -> Int -> IO String
livePanel started n trackerRows = do
  t0 <- now
  let factorial = show (product [1 .. n])
  digits <- evaluate (length factorial)
  t1 <- now
  bytes <- wasmBytes
  page <- pageBytes
  up <- uptime started
  pure $
    "<dl class=\"live\">"
      ++ item
        "The compiler"
        ("GHC " ++ showVersion fullCompilerVersion ++ ", targeting " ++ arch ++ "-" ++ os ++ ", which nixpkgs built from source.")
      ++ item
        "This slide deck"
        ( mb bytes
            ++ " MB of WebAssembly, inlined into index.html so that it opens straight from a file. \
               \Everything the browser downloads, uncompressed and unminified, is "
            ++ mb page
            ++ " MB; I haven't tried any size optimisations yet."
        )
      ++ item
        (show n ++ "!")
        ( "the factorial of "
            ++ show n
            ++ ", computed live just now in "
            ++ show (round (t1 - t0) :: Int)
            ++ " ms by GHC's native bignum running as WebAssembly: <code>"
            ++ take 24 factorial
            ++ "…</code>, "
            ++ show digits
            ++ " digits in all. Press + or − to change n."
        )
      ++ item
        "A Haskell thread"
        ( "has been counting for <span id=\"uptime\">"
            ++ up
            ++ "</span>, using nothing more than <code>forkIO</code> and <code>threadDelay</code>. \
               \Under JSFFI, a <code>threadDelay</code> is a JavaScript <code>setTimeout</code>."
        )
      ++ item
        "Template Haskell"
        ( "read slides.md and README.md when this slide deck was built, and found "
            ++ show trackerRows
            ++ " rows in the tracker. Those splices ran in GHC's wasm interpreter."
        )
      ++ "</dl>"
  where
    item term description = "<dt>" ++ term ++ "</dt><dd>" ++ description ++ "</dd>"
    mb n = showFFloat (Just 1) (fromIntegral n / 1e6 :: Double) ""
