{-# LANGUAGE ForeignFunctionInterface #-}

-- | Each line of output exercises one layer of the wasm toolchain, see
-- expected-output.txt.
module Main (main) where

import Foreign.C.Types (CInt (..))
import Foreign.Ptr (FunPtr, freeHaskellFunPtr)
import System.Environment (getArgs)

type BinOp = CInt -> CInt -> IO CInt

-- | A plain C function from cbits/hello.c, compiled by the wasm C compiler.
foreign import ccall unsafe "hello_add"
  c_add :: CInt -> CInt -> IO CInt

-- | Calls the function pointer it is given. Has to be a safe call, since it
-- calls back into Haskell.
foreign import ccall safe "hello_apply"
  c_apply :: FunPtr BinOp -> CInt -> CInt -> IO CInt

-- | Turns a Haskell closure into a C function pointer. GHC implements this
-- with libffi closures (libffi-wasm on wasm).
foreign import ccall "wrapper"
  mkBinOp :: BinOp -> IO (FunPtr BinOp)

main :: IO ()
main = do
  putStrLn "Hello from GHC's wasm backend, built purely with Nix!"
  -- Exceeds 64 bits, so it needs the bignum backend (native-bignum here).
  print (product [1 .. 30 :: Integer])
  args <- getArgs
  putStrLn ("args: " ++ unwords args)
  s <- c_add 40 2
  putStrLn ("C FFI: 40 + 2 = " ++ show s)
  mul <- mkBinOp (\a b -> pure (a * b))
  p <- c_apply mul 6 7
  freeHaskellFunPtr mul
  putStrLn ("FFI wrapper (libffi-wasm): 6 * 7 = " ++ show p)
