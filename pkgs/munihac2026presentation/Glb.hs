-- | Just enough glTF 2.0 binary (.glb) to read one mesh: positions, normals
-- and 16-bit indices of the first primitive, placed by the first node.
-- Template Haskell runs this at build time, so it must not depend on JSFFI.
module Glb (Mesh (..), parseGlb, vertexBytes, indexBytes) where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import qualified Data.ByteString as B
import Data.Char (isDigit, isSpace)
import Data.Word (Word16, Word32, Word8)
import GHC.Float (castFloatToWord32, castWord32ToFloat)

data Mesh = Mesh
  { -- | Interleaved position and normal: 6 floats per vertex. The mesh is
    -- centred on the y axis, stands on y = 0 and is 1 high.
    meshVertices :: [Float],
    meshIndices :: [Word16]
  }

parseGlb :: B.ByteString -> Either String Mesh
parseGlb glb = do
  check (B.take 4 glb == B.pack [0x67, 0x6c, 0x54, 0x46]) "not a .glb file"
  let jsonLen = u32 glb 12
      json = B.drop 20 (B.take (20 + jsonLen) glb)
      binStart = 20 + jsonLen + 8
  doc <- parseJson (map (toEnum . fromIntegral) (B.unpack json))
  primitive <- at doc ["meshes", "0", "primitives", "0"]
  positions <- accessor doc binStart =<< at primitive ["attributes", "POSITION"]
  normals <- accessor doc binStart =<< at primitive ["attributes", "NORMAL"]
  indices <- accessor doc binStart =<< at primitive ["indices"]
  let node = either (const (JObj [])) id (at doc ["nodes", "0"])
      rotation = either (const [0, 0, 0, 1]) numbers (at node ["rotation"])
      scale = either (const [1, 1, 1]) numbers (at node ["scale"])
      place = rotate rotation . zipWith (*) scale
      ps = map place (triples (floats positions))
      ns = map (rotate rotation) (triples (floats normals))
      (xs, ys, zs) = unzip3 [(x, y, z) | [x, y, z] <- ps]
      centre lo hi = (lo + hi) / 2
      height = maximum ys - minimum ys
      normalise [x, y, z] =
        [ (x - centre (minimum xs) (maximum xs)) / height,
          (y - minimum ys) / height,
          (z - centre (minimum zs) (maximum zs)) / height
        ]
      normalise p = p
  pure
    Mesh
      { meshVertices = concat (zipWith (++) (map normalise ps) ns),
        meshIndices = [fromIntegral (u16 indices (2 * i)) | i <- [0 .. B.length indices `div` 2 - 1]]
      }
  where
    check ok err = if ok then Right () else Left err
    -- The bytes an accessor refers to, without strides or offsets.
    accessor doc binStart ix = do
      i <- index ix
      acc <- at doc ["accessors", show i]
      view <- index =<< at acc ["bufferView"]
      bv <- at doc ["bufferViews", show view]
      offset <- index (either (const (JNum 0)) id (at bv ["byteOffset"]))
      len <- index =<< at bv ["byteLength"]
      pure (B.take len (B.drop (binStart + offset) glb))
    floats bytes = [castWord32ToFloat (fromIntegral (u32 bytes (4 * i))) | i <- [0 .. B.length bytes `div` 4 - 1]]
    triples (a : b : c : rest) = [a, b, c] : triples rest
    triples _ = []

-- | Rotates a point by a quaternion [x, y, z, w].
rotate :: [Float] -> [Float] -> [Float]
rotate [qx, qy, qz, qw] [x, y, z] =
  let -- t = 2 q × v; v' = v + w t + q × t
      tx = 2 * (qy * z - qz * y)
      ty = 2 * (qz * x - qx * z)
      tz = 2 * (qx * y - qy * x)
   in [ x + qw * tx + (qy * tz - qz * ty),
        y + qw * ty + (qz * tx - qx * tz),
        z + qw * tz + (qx * ty - qy * tx)
      ]
rotate _ v = v

u32 :: B.ByteString -> Int -> Int
u32 b i = foldr (\k acc -> acc `shiftL` 8 .|. fromIntegral (B.index b (i + k))) 0 [0 .. 3]

u16 :: B.ByteString -> Int -> Int
u16 b i = fromIntegral (B.index b i) .|. fromIntegral (B.index b (i + 1)) `shiftL` 8

-- | Little-endian bytes, as WebGL wants them.
vertexBytes :: Mesh -> [Word8]
vertexBytes = concatMap (le 4 . castFloatToWord32) . meshVertices

indexBytes :: Mesh -> [Word8]
indexBytes = concatMap (le 2 . (fromIntegral :: Word16 -> Word32)) . meshIndices

le :: Int -> Word32 -> [Word8]
le n w = [fromIntegral ((w `shiftR` (8 * k)) .&. 0xff) | k <- [0 .. n - 1]]

-- Just enough JSON for glTF.

data Json = JObj [(String, Json)] | JArr [Json] | JNum Double | JStr String | JLit String

at :: Json -> [String] -> Either String Json
at j [] = Right j
at (JObj kvs) (k : ks) = maybe (Left ("glTF: no " ++ k)) (`at` ks) (lookup k kvs)
at (JArr xs) (k : ks) | all isDigit k, read k < length xs = at (xs !! read k) ks
at _ (k : _) = Left ("glTF: no " ++ k)

index :: Json -> Either String Int
index (JNum n) = Right (round n)
index _ = Left "glTF: expected a number"

numbers :: Json -> [Float]
numbers (JArr xs) = [realToFrac n | JNum n <- xs]
numbers _ = []

parseJson :: String -> Either String Json
parseJson s = case value (skip s) of
  Just (j, _) -> Right j
  Nothing -> Left "glTF: invalid JSON"
  where
    skip = dropWhile isSpace
    value ('{' : rest) = object [] (skip rest)
    value ('[' : rest) = array [] (skip rest)
    value ('"' : rest) = let (str, rest') = break (== '"') rest in Just (JStr str, skip (drop 1 rest'))
    value str@(c : _)
      | c == '-' || isDigit c =
          let (num, rest) = span (`elem` "+-.eE0123456789") str
           in Just (JNum (readNumber num), skip rest)
      | otherwise = let (lit, rest) = span (`elem` "truefalsn") str in Just (JLit lit, skip rest)
    value [] = Nothing
    object acc ('}' : rest) = Just (JObj (reverse acc), skip rest)
    object acc (',' : rest) = object acc (skip rest)
    object acc ('"' : rest) = do
      let (key, rest') = break (== '"') rest
      (v, rest'') <- value (skip (drop 1 (skip (drop 1 rest'))))
      object ((key, v) : acc) rest''
    object _ _ = Nothing
    array acc (']' : rest) = Just (JArr (reverse acc), skip rest)
    array acc (',' : rest) = array acc (skip rest)
    array acc str = do
      (v, rest) <- value str
      array (v : acc) rest
    -- read wants a digit before the point and no "+" in the exponent.
    readNumber num = case num of
      '-' : rest -> negate (readNumber rest)
      '.' : _ -> readNumber ('0' : num)
      _ -> read (filter (/= '+') num)
