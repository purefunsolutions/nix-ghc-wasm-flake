-- | The MuniHac 2026 lightning talk. JavaScript instantiates this wasm module
-- and calls hs_start; from then on, Haskell owns the page.
module Main (main) where

import Content (readmeSource, slidesSource)
import Data.Char (isAlphaNum, isAscii)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Version (showVersion)
import Control.Monad (when)
import Demo (livePanel, startTicker)
import Dom
import Lambda3D (startLambda3D)
import Markdown (Block (..), escape)
import Slides
import System.Info (arch, fullCompilerVersion, os)
import Text.Read (readMaybe)
import Tracker (Tracker (..), parseTracker, renderSummary, renderTracker)

foreign export javascript "hs_start" main :: IO ()

data Deck = Deck
  { slides :: [Slide]
  , current :: IORef Int
  , -- | n for the live slide's n!.
    factorialOf :: IORef Integer
  , started :: Double
  }

main :: IO ()
main = do
  started' <- now
  let deck = parseDeck slidesSource
      count = length deck
      clamp i = max 1 (min count i)
  putStrLn ("Hello from Haskell, " ++ show count ++ " slides")
  setInnerHTML "runtime" (escape runtime)
  start <- maybe 1 clamp . readMaybe . drop 1 <$> getHash
  st <- Deck deck <$> newIORef start <*> newIORef 10000 <*> pure started'
  let move f = modifyIORef' (current st) (clamp . f) >> render st
      -- Above 20000!, the slide would freeze for seconds.
      changeN f = modifyIORef' (factorialOf st) (max 1 . min 20000 . f) >> render st
  render st
  startTicker started'

  onDocument "keydown" $ \e -> do
    modified <- hasModifier e
    key <- eventKey e
    let action = case key of
          _ | Just f <- lookup key (keys count) -> Just (f move)
          k | k `elem` ["+", "="] -> Just (changeN (* 2))
          k | k `elem` ["-", "−"] -> Just (changeN (`div` 2))
          _ -> Nothing
    case action of
      Just a | not modified -> preventDefault e >> a
      _ -> pure ()

  onDocument "click" $ \e -> do
    onLink <- isLinkClick e
    x <- clickFraction e
    if onLink then pure () else move (if x < 1 / 3 then pred else succ)

-- | What each key does, given a way to move between slides.
keys :: Int -> [(String, ((Int -> Int) -> IO ()) -> IO ())]
keys count =
  [(k, ($ succ)) | k <- ["ArrowRight", "ArrowDown", " ", "PageDown", "n"]]
    ++ [(k, ($ pred)) | k <- ["ArrowLeft", "ArrowUp", "PageUp", "p"]]
    ++ [("Home", ($ const 1)), ("End", ($ const count)), ("f", const toggleFullscreen)]

render :: Deck -> IO ()
render st = do
  i <- readIORef (current st)
  let slide = slides st !! (i - 1)
  html <- renderSlide (directive st) slide
  setClass "slide" (slideClass slide)
  setInnerHTML "slide" html
  setInnerHTML "counter" (show i ++ " / " ++ show (length (slides st)))
  setHash i
  when (or [True | Directive "webgl" _ <- slideBlocks slide]) (startLambda3D "gl")

directive :: Deck -> String -> String -> IO String
directive st name args = case name of
  "logo" -> pure logo
  "qr" -> pure (qr args)
  "image" -> pure (image args)
  "webgl" -> pure "<canvas id=\"gl\" aria-hidden=\"true\"></canvas><p id=\"fps\" class=\"fps\"></p><p id=\"glerror\" class=\"error\"></p>"
  "tracker" -> pure (renderTracker tracker)
  "tracker-summary" -> pure (renderSummary tracker)
  "live" -> do
    n <- readIORef (factorialOf st)
    livePanel (started st) n (either (const 0) (length . trackerRows) tracker)
  _ -> pure ("<p class=\"error\">Unknown directive @" ++ escape name ++ "</p>")
  where
    tracker = parseTracker readmeSource

-- | A QR code for a URL, from the qr-*.svg files the Nix build generates for
-- every @qr line in slides.md.
qr :: String -> String
qr url =
  "<a class=\"qr\" href=\"" ++ escape url ++ "\" target=\"_blank\" rel=\"noopener\">"
    ++ "<img src=\"qr-" ++ map safe url ++ ".svg\" alt=\"QR code for " ++ escape url ++ "\"></a>"
  where
    safe c = if isAscii c && isAlphaNum c then c else '_'

-- | @image file alt text: a picture from web/, copied next to index.html by the
-- Nix build.
image :: String -> String
image args = case words args of
  file : alt -> "<img class=\"screenshot\" src=\"" ++ escape file ++ "\" alt=\"" ++ escape (unwords alt) ++ "\">"
  [] -> "<p class=\"error\">@image needs a file name</p>"

runtime :: String
runtime =
  "GHC " ++ showVersion fullCompilerVersion ++ " → " ++ arch ++ "-" ++ os ++ ", running in your browser"

-- | The Haskell logo inside WebAssembly's notched square.
logo :: String
logo =
  "<svg class=\"logo\" viewBox=\"0 0 100 100\" role=\"img\" aria-label=\"Haskell inside WebAssembly\">\
  \<path d=\"M0 0H33A17 17 0 0 0 67 0H100V100H0Z\" fill=\"#654ff0\"/>\
  \<g transform=\"translate(17.7 42) scale(3.8)\">\
  \<path d=\"M0 12l4-6-4-6h3l4 6-4 6z\" fill=\"#c9befd\"/>\
  \<path d=\"M4 12l4-6-4-6h3l8 12h-3l-2.5-3.75-2.5 3.75z\" fill=\"#ffffff\"/>\
  \<path d=\"M13.67 8.5l-1.33-2h4.67v2zM11.67 5.5l-1.33-2h6.67v2z\" fill=\"#e4defe\"/>\
  \</g></svg>"
