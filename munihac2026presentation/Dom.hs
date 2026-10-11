-- | The few browser APIs the slides need, via GHC's JavaScript FFI.
module Dom
  ( JSVal
  , setInnerHTML
  , setClass
  , getHash
  , setHash
  , onDocument
  , eventKey
  , hasModifier
  , preventDefault
  , clickFraction
  , isLinkClick
  , toggleFullscreen
  , now
  , setTextIfPresent
  , wasmBytes
  , pageBytes
  ) where

import GHC.Wasm.Prim (JSString (..), JSVal, fromJSString, toJSString)

foreign import javascript unsafe "document.getElementById($1).innerHTML = $2"
  js_setInnerHTML :: JSString -> JSString -> IO ()

setInnerHTML :: String -> String -> IO ()
setInnerHTML i html = js_setInnerHTML (toJSString i) (toJSString html)

foreign import javascript unsafe "document.getElementById($1).className = $2"
  js_setClass :: JSString -> JSString -> IO ()

setClass :: String -> String -> IO ()
setClass i c = js_setClass (toJSString i) (toJSString c)

foreign import javascript unsafe "location.hash"
  js_getHash :: IO JSString

getHash :: IO String
getHash = fromJSString <$> js_getHash

foreign import javascript unsafe "history.replaceState(null, '', '#' + $1)"
  setHash :: Int -> IO ()

-- | A synchronous callback, so that handlers can still call preventDefault.
foreign import javascript "wrapper sync"
  js_callback :: (JSVal -> IO ()) -> IO JSVal

foreign import javascript unsafe "document.addEventListener($1, $2)"
  js_addEventListener :: JSString -> JSVal -> IO ()

onDocument :: String -> (JSVal -> IO ()) -> IO ()
onDocument event handler = js_callback handler >>= js_addEventListener (toJSString event)

foreign import javascript unsafe "$1.key"
  js_eventKey :: JSVal -> IO JSString

eventKey :: JSVal -> IO String
eventKey e = fromJSString <$> js_eventKey e

foreign import javascript unsafe "$1.ctrlKey || $1.metaKey || $1.altKey"
  hasModifier :: JSVal -> IO Bool

foreign import javascript unsafe "$1.preventDefault()"
  preventDefault :: JSVal -> IO ()

-- | Where a click landed, from 0 at the left edge to 1 at the right.
foreign import javascript unsafe "$1.clientX / window.innerWidth"
  clickFraction :: JSVal -> IO Double

foreign import javascript unsafe "$1.target.closest('a') !== null"
  isLinkClick :: JSVal -> IO Bool

foreign import javascript unsafe
  "document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()"
  toggleFullscreen :: IO ()

-- | Milliseconds since the page started loading.
foreign import javascript unsafe "performance.now()"
  now :: IO Double

foreign import javascript unsafe "const e = document.getElementById($1); if (e) e.textContent = $2;"
  js_setTextIfPresent :: JSString -> JSString -> IO ()

setTextIfPresent :: String -> String -> IO ()
setTextIfPresent i text = js_setTextIfPresent (toJSString i) (toJSString text)

-- | The size of this program's wasm module, from main.js.
foreign import javascript unsafe "globalThis.presentationWasmBytes ?? 0"
  wasmBytes :: IO Int

-- | The size of everything the browser downloads for this page, measured by
-- the Nix build.
foreign import javascript unsafe "Number(document.getElementById('stage').dataset.bytes ?? 0)"
  pageBytes :: IO Int
