module Test.Term where

import Control.Monad
import Test.HUnit.Lang (assertFailure)
import Test.Hspec

import Test.Util

import Kitten.Anno
import Kitten.Def
import Kitten.Error
import Kitten.Fragment
import Kitten.Term
import Kitten.Token (tokenize)

import qualified Kitten.Builtin as Builtin

spec :: Spec
spec = do
  describe "empty program"
    $ testTerm "" (fragment [] [] [])

  describe "terms" $ do
    testTerm "1 2 3"
      (fragment [] [] [int 1, int 2, int 3])
    testTerm "dup swap drop vec cat fun compose apply"
      $ fragment [] []
        [ Builtin Builtin.Dup
        , Builtin Builtin.Swap
        , Builtin Builtin.Drop
        , Builtin Builtin.Vec
        , Builtin Builtin.Cat
        , Builtin Builtin.Fun
        , Builtin Builtin.Compose
        , Builtin Builtin.Apply
        ]

testTerm :: String -> Fragment Term -> Spec
testTerm source expected = it (show source)
  $ case parsed source of
    Left message -> assertFailure $ show message
    Right actual
      | expected == actual -> return ()
      | otherwise -> expectedButGot
        (show expected) (show actual)
  where
  parsed
    = liftParseError . parse "test"
    <=< liftParseError . tokenize "test"

fragment :: [Anno] -> [Def Term] -> [Term] -> Fragment Term
fragment annos defs terms
  = Fragment annos defs (Compose terms)

int :: Int -> Term
int = Value . Int
