-- | The WebGL demo: the lambda from lambda.glb in pride colours, above a
-- bumpy floor that partly reflects it, in a 3D starfield. Haskell does the
-- maths and drives every frame; the GLSL shaders do the pixels.
module Lambda3D (startLambda3D) where

import Content (lambdaMesh)
import Control.Monad (when)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Word (Word32, Word8)
import Dom (now, setTextIfPresent)
import Foreign.Marshal.Alloc (mallocBytes)
import Foreign.Marshal.Array (pokeArray)
import Foreign.Ptr (Ptr, castPtr)
import GHC.Wasm.Prim (JSVal)
import Gl

-- * Maths: column-major 4×4 matrices, like WebGL wants them

type M4 = [Double]

mul :: M4 -> M4 -> M4
mul a b = [sum [a !! (r + 4 * k) * b !! (k + 4 * c) | k <- [0 .. 3]] | c <- [0 .. 3], r <- [0 .. 3 :: Int]]

perspective :: Double -> Double -> Double -> Double -> M4
perspective fovy aspect near far =
  let f = 1 / tan (fovy / 2)
      nf = 1 / (near - far)
   in [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]

type V3 = (Double, Double, Double)

lookAt :: V3 -> V3 -> M4
lookAt eye target =
  let f = normalise (target `minus` eye)
      s = normalise (f `cross` (0, 1, 0))
      u = s `cross` f
      (sx, sy, sz) = s
      (ux, uy, uz) = u
      (fx, fy, fz) = f
   in [sx, ux, -fx, 0, sy, uy, -fy, 0, sz, uz, -fz, 0, -(dot s eye), -(dot u eye), dot f eye, 1]
  where
    minus (a, b, c) (x, y, z) = (a - x, b - y, c - z)
    cross (a, b, c) (x, y, z) = (b * z - c * y, c * x - a * z, a * y - b * x)
    dot (a, b, c) (x, y, z) = a * x + b * y + c * z
    normalise v@(a, b, c) = let l = sqrt (dot v v) in (a / l, b / l, c / l)

rotationY :: Double -> M4
rotationY a = [cos a, 0, -(sin a), 0, 0, 1, 0, 0, sin a, 0, cos a, 0, 0, 0, 0, 1]

scaling :: Double -> Double -> Double -> M4
scaling x y z = [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]

translation :: Double -> Double -> Double -> M4
translation x y z = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]

-- * Shaders

starVertex, starFragment, lambdaVertex, lambdaFragment, floorVertex, floorFragment :: String
starVertex =
  unlines
    [ "#version 300 es",
      "in vec2 a_corner;",
      "in vec4 a_star;",
      "uniform mat4 u_viewproj;",
      "uniform float u_time;",
      "uniform vec2 u_viewport;",
      "out vec2 v_corner;",
      "out float v_light;",
      "out float v_hue;",
      "void main() {",
      "  // Fly towards the camera, wrapping around, while the field turns.",
      "  float z = mod(a_star.z * 20.0 + u_time * 2.5, 40.0) - 38.0;",
      "  float a = u_time * 0.05 + z * 0.015;",
      "  vec2 xy = mat2(cos(a), sin(a), -sin(a), cos(a)) * (a_star.xy * vec2(16.0, 10.0));",
      "  vec4 clip = u_viewproj * vec4(xy, z, 1.0);",
      "  float seed = a_star.w * 0.5 + 0.5;",
      "  float size = clamp(55.0 / max(clip.w, 0.1), 2.0, 16.0) * (0.5 + 0.5 * seed);",
      "  clip.xy += a_corner * size / u_viewport * 2.0 * clip.w;",
      "  gl_Position = clip;",
      "  v_corner = a_corner;",
      "  v_light = smoothstep(-38.0, -24.0, z) * smoothstep(2.0, 0.5, z) * (0.4 + 0.6 * seed);",
      "  v_hue = fract(seed * 17.0);",
      "}"
    ]
starFragment =
  unlines
    [ "#version 300 es",
      "precision highp float;",
      "in vec2 v_corner;",
      "in float v_light;",
      "in float v_hue;",
      "out vec4 color;",
      "void main() {",
      "  float glow = exp(-dot(v_corner, v_corner) * 5.0);",
      "  vec3 tint = mix(vec3(0.8, 0.85, 1.0), vec3(0.7, 0.6, 1.0), v_hue);",
      "  color = vec4(tint, glow * v_light * 2.2);",
      "}"
    ]
lambdaVertex =
  unlines
    [ "#version 300 es",
      "in vec3 a_position;",
      "in vec3 a_normal;",
      "uniform mat4 u_model;",
      "uniform mat4 u_viewproj;",
      "out vec3 v_normal;",
      "out vec3 v_world;",
      "out vec3 v_local;",
      "void main() {",
      "  vec4 world = u_model * vec4(a_position, 1.0);",
      "  v_world = world.xyz;",
      "  v_local = a_position;",
      "  v_normal = mat3(u_model) * a_normal;",
      "  gl_Position = u_viewproj * world;",
      "}"
    ]
lambdaFragment =
  unlines
    [ "#version 300 es",
      "precision highp float;",
      "in vec3 v_normal;",
      "in vec3 v_world;",
      "in vec3 v_local;",
      "uniform float u_time;",
      "uniform vec3 u_eye;",
      "out vec4 color;",
      "const vec3 flag[6] = vec3[6](",
      "  vec3(0.894, 0.012, 0.012), vec3(1.0, 0.549, 0.0), vec3(1.0, 0.929, 0.0),",
      "  vec3(0.0, 0.502, 0.149), vec3(0.141, 0.251, 0.557), vec3(0.451, 0.161, 0.510));",
      "void main() {",
      "  // The pride flag from top to bottom, rippling like cloth.",
      "  float y = 1.0 - v_local.y + 0.04 * sin(v_local.x * 9.0 + v_local.z * 5.0 - u_time * 2.5);",
      "  vec3 base = flag[clamp(int(floor(y * 6.0)), 0, 5)];",
      "  vec3 n = normalize(v_normal);",
      "  vec3 v = normalize(u_eye - v_world);",
      "  vec3 l = normalize(vec3(0.5, 0.8, 0.7));",
      "  float diffuse = max(dot(n, l), 0.0);",
      "  float specular = pow(max(dot(n, normalize(l + v)), 0.0), 40.0);",
      "  float rim = pow(1.0 - abs(dot(n, v)), 3.0);",
      "  float sweep = smoothstep(0.06, 0.0, abs(fract(v_local.x * 0.7 + v_local.y * 0.5 - u_time * 0.3) - 0.5));",
      "  vec3 c = base * (0.3 + 0.8 * diffuse) + vec3(0.7) * specular + base * rim * 0.8 + vec3(0.35) * sweep;",
      "  color = vec4(c, 1.0);",
      "}"
    ]
floorVertex =
  unlines
    [ "#version 300 es",
      "in vec2 a_corner;",
      "uniform mat4 u_viewproj;",
      "out vec3 v_world;",
      "void main() {",
      "  v_world = vec3(a_corner.x * 14.0, 0.0, a_corner.y * 14.0);",
      "  gl_Position = u_viewproj * vec4(v_world, 1.0);",
      "}"
    ]
floorFragment =
  unlines
    [ "#version 300 es",
      "precision highp float;",
      "in vec3 v_world;",
      "uniform sampler2D u_reflection;",
      "uniform vec2 u_viewport;",
      "uniform float u_time;",
      "uniform vec3 u_eye;",
      "out vec4 color;",
      "float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }",
      "float noise(vec2 p) {",
      "  vec2 i = floor(p), f = fract(p);",
      "  f = f * f * (3.0 - 2.0 * f);",
      "  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);",
      "}",
      "float height(vec2 p) {",
      "  return 0.6 * noise(p * 2.5 + vec2(u_time * 0.2, 0.0))",
      "       + 0.3 * noise(p * 7.0 - vec2(0.0, u_time * 0.3))",
      "       + 0.08 * sin(length(p) * 12.0 - u_time * 2.0);",
      "}",
      "void main() {",
      "  vec2 p = v_world.xz;",
      "  float e = 0.01;",
      "  vec2 slope = vec2(height(p + vec2(e, 0)) - height(p - vec2(e, 0)),",
      "                    height(p + vec2(0, e)) - height(p - vec2(0, e))) / (2.0 * e);",
      "  vec3 n = normalize(vec3(-slope.x * 0.06, 1.0, -slope.y * 0.06));",
      "  // The mirrored scene, displaced by the bumps.",
      "  vec3 reflection = texture(u_reflection, gl_FragCoord.xy / u_viewport + n.xz * 0.08).rgb;",
      "  vec3 v = normalize(u_eye - v_world);",
      "  float fresnel = 0.3 + 0.7 * pow(1.0 - max(dot(n, v), 0.0), 3.0);",
      "  // Smooth, wet patches reflect; rough ones mostly don't.",
      "  float wet = smoothstep(0.35, 0.65, noise(p * 0.8 + 7.0));",
      "  vec2 g = abs(fract(p * 2.0) - 0.5);",
      "  float grid = smoothstep(0.47, 0.5, max(g.x, g.y));",
      "  vec3 c = vec3(0.03, 0.025, 0.07) + vec3(0.4, 0.31, 0.94) * (0.05 * height(p) + 0.12 * grid)",
      "          + reflection * fresnel * mix(0.12, 0.9, wet);",
      "  color = vec4(c, smoothstep(12.0, 3.0, length(p)));",
      "}"
    ]

-- * The scene

starCount :: Int
starCount = 4000

-- | x, y, z and a seed in [-1, 1] for each star, from a linear congruential
-- generator.
starData :: [Float]
starData = map unit (take (4 * starCount) (drop 1 (iterate step 20261011)))
  where
    step :: Word32 -> Word32
    step s = s * 1664525 + 1013904223
    unit s = fromIntegral s / 2147483648 - 1

floatBuffer :: GL -> [Float] -> IO JSVal
floatBuffer gl xs = do
  p <- mallocBytes (4 * length xs)
  pokeArray p xs
  arrayBuffer gl (castPtr p :: Ptr Word8) (4 * length xs)

-- | Starts the demo on the canvas with the given id. It stops by itself when
-- the canvas leaves the page.
startLambda3D :: String -> IO ()
startLambda3D canvasId = do
  canvas <- element canvasId
  gl <- getContext canvas
  noGL <- isNull gl
  if noGL
    then setText "glerror" "This browser has no WebGL2."
    else do
      programs <-
        sequence
          <$> sequence
            [ program gl starVertex starFragment,
              program gl lambdaVertex lambdaFragment,
              program gl floorVertex floorFragment
            ]
      case programs of
        Left err -> setText "glerror" err >> putStrLn err
        Right ps -> scene canvas gl ps

scene :: JSVal -> GL -> [JSVal] -> IO ()
scene canvas gl ps = do
  let (starP, lambdaP, floorP) = case ps of
        [a, b, c] -> (a, b, c)
        _ -> error "three programs"
      (vertices, verticesSize, indices, indexCount) = lambdaMesh
  quad <- floatBuffer gl [-1, -1, 1, -1, -1, 1, 1, 1]

  starVAO <- createVertexArray gl
  bindVertexArray gl starVAO
  bindArrayBuffer gl quad
  corner <- attrib gl starP "a_corner"
  attribPointer gl corner 2 8 0 0
  _ <- floatBuffer gl starData
  star <- attrib gl starP "a_star"
  attribPointer gl star 4 16 0 1

  floorVAO <- createVertexArray gl
  bindVertexArray gl floorVAO
  bindArrayBuffer gl quad
  floorCorner <- attrib gl floorP "a_corner"
  attribPointer gl floorCorner 2 8 0 0

  lambdaVAO <- createVertexArray gl
  bindVertexArray gl lambdaVAO
  _ <- arrayBuffer gl vertices verticesSize
  position <- attrib gl lambdaP "a_position"
  attribPointer gl position 3 24 0 0
  normal <- attrib gl lambdaP "a_normal"
  attribPointer gl normal 3 24 12 0
  _ <- elementBuffer gl indices (2 * indexCount)

  scratch <- mallocBytes 64
  target <- newIORef Nothing
  started <- now
  let matrix p name m = do
        pokeArray scratch (map realToFrac m)
        u <- uniform gl p name
        uniformMatrix4fv gl u scratch
      float p name x = uniform gl p name >>= \u -> uniform1f gl u x
      vec2 p name x y = uniform gl p name >>= \u -> uniform2f gl u x y
      vec3 p name (x, y, z) = uniform gl p name >>= \u -> uniform3f gl u x y z

      stars t vp (w, h) = do
        useProgram gl starP
        bindVertexArray gl starVAO
        blendDepth gl 1 False False
        matrix starP "u_viewproj" vp
        float starP "u_time" t
        vec2 starP "u_viewport" (fromIntegral w) (fromIntegral h)
        drawStripInstanced gl 4 starCount

      lambda t eye vp model = do
        useProgram gl lambdaP
        bindVertexArray gl lambdaVAO
        blendDepth gl 0 True True
        matrix lambdaP "u_model" model
        matrix lambdaP "u_viewproj" vp
        float lambdaP "u_time" t
        vec3 lambdaP "u_eye" eye
        drawTriangles gl indexCount

      frame = do
        t <- (/ 1000) . subtract started <$> now
        (w, h) <- fitCanvas canvas
        let (rw, rh) = (max 1 (w `div` 2), max 1 (h `div` 2))
        -- The reflection's render target, half size, remade on resize.
        current <- readIORef target
        reflection <- case current of
          Just (tw, th, tgt) | (tw, th) == (rw, rh) -> pure tgt
          _ -> do
            mapM_ (\(_, _, old) -> deleteTarget gl old) current
            tgt <- createTarget gl rw rh
            writeIORef target (Just (rw, rh, tgt))
            pure tgt
        let eye = (0, 0.8, 3.1)
            vp = perspective (pi / 4.5) (fromIntegral w / fromIntegral h) 0.1 100 `mul` lookAt eye (0, 0.5, 0)
            -- Right of centre, leaving room for the text on the left.
            model = translation 0.75 0.08 0 `mul` rotationY (t * 0.8) `mul` scaling 1.1 1.1 1.1
            mirror = scaling 1 (-1) 1

        -- The mirrored scene, into the texture.
        bindTarget gl reflection
        viewport gl rw rh
        clear gl 0 0 0
        stars t (vp `mul` mirror) (rw, rh)
        lambda t eye vp (mirror `mul` model)

        -- The scene, with the floor showing the reflection.
        bindTarget gl noTarget
        viewport gl w h
        clear gl 0.035 0.03 0.075
        stars t vp (w, h)
        useProgram gl floorP
        bindVertexArray gl floorVAO
        blendDepth gl 2 True True
        bindTargetTexture gl reflection
        uniform gl floorP "u_reflection" >>= \u -> uniform1i gl u 0
        matrix floorP "u_viewproj" vp
        float floorP "u_time" t
        vec2 floorP "u_viewport" (fromIntegral w) (fromIntegral h)
        vec3 floorP "u_eye" eye
        drawStrip gl 4
        lambda t eye vp model

  -- Frames since the frame rate was last shown, and when that was.
  fps <- newIORef (0 :: Int, started)
  let countFrame = do
        (frames, since) <- readIORef fps
        t <- now
        if t - since < 500
          then writeIORef fps (frames + 1, since)
          else do
            setTextIfPresent "fps" (show (round (fromIntegral (frames + 1) * 1000 / (t - since)) :: Int) ++ " fps")
            writeIORef fps (0, t)

  self <- newIORef Nothing
  callback <- frameCallback $ \_ -> do
    alive <- isConnected canvas
    when alive $ do
      frame
      countFrame
      readIORef self >>= mapM_ requestAnimationFrame
  writeIORef self (Just callback)
  requestAnimationFrame callback
