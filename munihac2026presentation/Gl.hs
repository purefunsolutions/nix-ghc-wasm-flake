-- | The WebGL2 calls the 3D demo needs, one JSFFI import each. Pointers go
-- to WebGL as views into the wasm module's memory.
module Gl where

import Data.Word (Word8)
import Foreign.Ptr (Ptr)
import GHC.Wasm.Prim (JSString (..), JSVal, fromJSString, toJSString)

type GL = JSVal

-- * Canvas and context

foreign import javascript unsafe "document.getElementById($1)"
  js_element :: JSString -> IO JSVal

foreign import javascript unsafe "$1 !== null && $1.isConnected"
  isConnected :: JSVal -> IO Bool

element :: String -> IO JSVal
element = js_element . toJSString

foreign import javascript unsafe "$1.getContext('webgl2', {antialias: true})"
  getContext :: JSVal -> IO GL

foreign import javascript unsafe "$1 === null"
  isNull :: JSVal -> IO Bool

-- | Makes the canvas' drawing buffer match its size on screen, in device
-- pixels; returns the new width and height packed as width * 65536 + height.
foreign import javascript unsafe
  "const c = $1, r = window.devicePixelRatio || 1; \
  \const w = Math.max(1, Math.round(c.clientWidth * r)), h = Math.max(1, Math.round(c.clientHeight * r)); \
  \if (c.width !== w || c.height !== h) { c.width = w; c.height = h; } \
  \return w * 65536 + h;"
  js_fitCanvas :: JSVal -> IO Int

fitCanvas :: JSVal -> IO (Int, Int)
fitCanvas canvas = (`divMod` 65536) <$> js_fitCanvas canvas

foreign import javascript unsafe "document.getElementById($1).textContent = $2"
  js_setText :: JSString -> JSString -> IO ()

setText :: String -> String -> IO ()
setText i t = js_setText (toJSString i) (toJSString t)

-- | Calls the function on the next animation frame with its timestamp.
foreign import javascript unsafe "requestAnimationFrame($1)"
  requestAnimationFrame :: JSVal -> IO ()

foreign import javascript "wrapper sync"
  frameCallback :: (Double -> IO ()) -> IO JSVal

-- * Shaders

foreign import javascript unsafe
  "const s = $1.createShader($2 ? $1.VERTEX_SHADER : $1.FRAGMENT_SHADER); \
  \$1.shaderSource(s, $3); $1.compileShader(s); return s;"
  js_shader :: GL -> Bool -> JSString -> IO JSVal

foreign import javascript unsafe
  "const p = $1.createProgram(); $1.attachShader(p, $2); $1.attachShader(p, $3); \
  \$1.linkProgram(p); return p;"
  js_link :: GL -> JSVal -> JSVal -> IO JSVal

foreign import javascript unsafe
  "$1.getProgramParameter($2, $1.LINK_STATUS) ? '' : \
  \[$1.getShaderInfoLog($3), $1.getShaderInfoLog($4), $1.getProgramInfoLog($2)].join('\\n')"
  js_linkErrors :: GL -> JSVal -> JSVal -> JSVal -> IO JSString

-- | Compiles and links a vertex and a fragment shader, or returns the logs.
program :: GL -> String -> String -> IO (Either String JSVal)
program gl vertex fragment = do
  vs <- js_shader gl True (toJSString vertex)
  fs <- js_shader gl False (toJSString fragment)
  p <- js_link gl vs fs
  errors <- fromJSString <$> js_linkErrors gl p vs fs
  pure (if null errors then Right p else Left errors)

foreign import javascript unsafe "$1.useProgram($2)"
  useProgram :: GL -> JSVal -> IO ()

foreign import javascript unsafe "$1.getAttribLocation($2, $3)"
  js_attrib :: GL -> JSVal -> JSString -> IO Int

attrib :: GL -> JSVal -> String -> IO Int
attrib gl p name = js_attrib gl p (toJSString name)

foreign import javascript unsafe "$1.getUniformLocation($2, $3)"
  js_uniform :: GL -> JSVal -> JSString -> IO JSVal

uniform :: GL -> JSVal -> String -> IO JSVal
uniform gl p name = js_uniform gl p (toJSString name)

foreign import javascript unsafe "$1.uniform1f($2, $3)"
  uniform1f :: GL -> JSVal -> Double -> IO ()

foreign import javascript unsafe "$1.uniform2f($2, $3, $4)"
  uniform2f :: GL -> JSVal -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.uniform3f($2, $3, $4, $5)"
  uniform3f :: GL -> JSVal -> Double -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.uniform1i($2, $3)"
  uniform1i :: GL -> JSVal -> Int -> IO ()

-- | Uploads a 4×4 matrix of 16 Floats at the pointer.
foreign import javascript unsafe
  "$1.uniformMatrix4fv($2, false, new Float32Array(__exports.memory.buffer, $3, 16))"
  uniformMatrix4fv :: GL -> JSVal -> Ptr Float -> IO ()

-- * Buffers and vertex arrays

foreign import javascript unsafe "$1.bindBuffer($1.ARRAY_BUFFER, $2)"
  bindArrayBuffer :: GL -> JSVal -> IO ()

foreign import javascript unsafe "$1.createVertexArray()"
  createVertexArray :: GL -> IO JSVal

foreign import javascript unsafe "$1.bindVertexArray($2)"
  bindVertexArray :: GL -> JSVal -> IO ()

-- | Creates and binds an array buffer (or an element array buffer, for
-- indices) and copies the bytes into it.
foreign import javascript unsafe
  "const b = $1.createBuffer(), t = $2 ? $1.ELEMENT_ARRAY_BUFFER : $1.ARRAY_BUFFER; \
  \$1.bindBuffer(t, b); \
  \$1.bufferData(t, new Uint8Array(__exports.memory.buffer, $3, $4), $1.STATIC_DRAW); \
  \return b;"
  js_buffer :: GL -> Bool -> Ptr Word8 -> Int -> IO JSVal

arrayBuffer, elementBuffer :: GL -> Ptr Word8 -> Int -> IO JSVal
arrayBuffer gl = js_buffer gl False
elementBuffer gl = js_buffer gl True

-- | Float attribute: location, components, stride and offset in bytes, and
-- the divisor (0 per vertex, 1 per instance).
foreign import javascript unsafe
  "if ($2 >= 0) { $1.enableVertexAttribArray($2); \
  \$1.vertexAttribPointer($2, $3, $1.FLOAT, false, $4, $5); $1.vertexAttribDivisor($2, $6); }"
  attribPointer :: GL -> Int -> Int -> Int -> Int -> Int -> IO ()

-- * Drawing

foreign import javascript unsafe "$1.viewport(0, 0, $2, $3)"
  viewport :: GL -> Int -> Int -> IO ()

foreign import javascript unsafe "$1.clearColor($2, $3, $4, 1); $1.clear($1.COLOR_BUFFER_BIT | $1.DEPTH_BUFFER_BIT)"
  clear :: GL -> Double -> Double -> Double -> IO ()

foreign import javascript unsafe "$1.drawArrays($1.TRIANGLE_STRIP, 0, $2)"
  drawStrip :: GL -> Int -> IO ()

foreign import javascript unsafe "$1.drawArraysInstanced($1.TRIANGLE_STRIP, 0, $2, $3)"
  drawStripInstanced :: GL -> Int -> Int -> IO ()

foreign import javascript unsafe "$1.drawElements($1.TRIANGLES, $2, $1.UNSIGNED_SHORT, 0)"
  drawTriangles :: GL -> Int -> IO ()

-- | Blending: 0 off, 1 additive, 2 alpha. Depth testing and writing on or off.
foreign import javascript unsafe
  "if ($2 === 0) $1.disable($1.BLEND); else { $1.enable($1.BLEND); \
  \$1.blendFunc($1.SRC_ALPHA, $2 === 1 ? $1.ONE : $1.ONE_MINUS_SRC_ALPHA); } \
  \if ($3) $1.enable($1.DEPTH_TEST); else $1.disable($1.DEPTH_TEST); $1.depthMask($4);"
  blendDepth :: GL -> Int -> Bool -> Bool -> IO ()

-- * Render to texture

-- | A framebuffer with a colour texture and a depth buffer, as an array
-- [framebuffer, texture, depth].
foreign import javascript unsafe
  "const f = $1.createFramebuffer(), t = $1.createTexture(), d = $1.createRenderbuffer(); \
  \$1.bindTexture($1.TEXTURE_2D, t); \
  \$1.texImage2D($1.TEXTURE_2D, 0, $1.RGBA, $2, $3, 0, $1.RGBA, $1.UNSIGNED_BYTE, null); \
  \$1.texParameteri($1.TEXTURE_2D, $1.TEXTURE_MIN_FILTER, $1.LINEAR); \
  \$1.texParameteri($1.TEXTURE_2D, $1.TEXTURE_WRAP_S, $1.CLAMP_TO_EDGE); \
  \$1.texParameteri($1.TEXTURE_2D, $1.TEXTURE_WRAP_T, $1.CLAMP_TO_EDGE); \
  \$1.bindRenderbuffer($1.RENDERBUFFER, d); \
  \$1.renderbufferStorage($1.RENDERBUFFER, $1.DEPTH_COMPONENT16, $2, $3); \
  \$1.bindFramebuffer($1.FRAMEBUFFER, f); \
  \$1.framebufferTexture2D($1.FRAMEBUFFER, $1.COLOR_ATTACHMENT0, $1.TEXTURE_2D, t, 0); \
  \$1.framebufferRenderbuffer($1.FRAMEBUFFER, $1.DEPTH_ATTACHMENT, $1.RENDERBUFFER, d); \
  \$1.bindFramebuffer($1.FRAMEBUFFER, null); \
  \return [f, t, d];"
  createTarget :: GL -> Int -> Int -> IO JSVal

foreign import javascript unsafe
  "$1.deleteFramebuffer($2[0]); $1.deleteTexture($2[1]); $1.deleteRenderbuffer($2[2]);"
  deleteTarget :: GL -> JSVal -> IO ()

-- | Renders into the target from now on, or into the canvas for null.
foreign import javascript unsafe "$1.bindFramebuffer($1.FRAMEBUFFER, $2 === null ? null : $2[0])"
  bindTarget :: GL -> JSVal -> IO ()

foreign import javascript unsafe "null"
  noTarget :: JSVal

-- | Binds the target's texture to texture unit 0.
foreign import javascript unsafe "$1.activeTexture($1.TEXTURE0); $1.bindTexture($1.TEXTURE_2D, $2[1])"
  bindTargetTexture :: GL -> JSVal -> IO ()
