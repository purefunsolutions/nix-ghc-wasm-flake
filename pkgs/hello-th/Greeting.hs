module Greeting (greeting) where

import Language.Haskell.TH (Exp, Q, stringE)

greeting :: String -> Q Exp
greeting who = stringE ("Hello, " ++ who ++ "! (spliced in from another module)")
