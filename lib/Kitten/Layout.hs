{-|
Module      : Kitten.Layout
Description : Whitespace-sensitive syntax desugaring
Copyright   : (c) Jon Purdy, 2016
License     : MIT
Maintainer  : evincarofautumn@gmail.com
Stability   : experimental
Portability : GHC
-}

module Kitten.Layout
  ( layout
  ) where

import Control.Applicative
import Kitten.Indent (Indent(..))
import Kitten.Informer (Informer(..))
import Kitten.Located (Located(..))
import Kitten.Parser (Parser, parserMatch, tokenSatisfy)
import Kitten.Token (Token(..))
import Text.Parsec ((<?>))
import qualified Kitten.Layoutness as Layoutness
import qualified Kitten.Located as Located
import qualified Kitten.Origin as Origin
import qualified Kitten.Report as Report
import qualified Kitten.Vocabulary as Vocabulary
import qualified Text.Parsec as Parsec

-- | Desugars layout-based syntax into explicit brace-delimited blocks according
-- to the *layout rule*:
--
-- A layout block begins with a colon followed by a token whose source column is
-- greater than the indent level of the colon token, and contains all tokens
-- (and bracket-delimited groups of tokens) whose source column is greater than
-- or equal to that of the first token.

layout :: (Informer m) => FilePath -> [Located Token] -> m [Located Token]
layout path tokens
  = case Parsec.runParser insertBraces Vocabulary.global path tokens of
    Left parseError -> do
      report $ Report.parseError parseError
      halt
    Right result -> return result

insertBraces :: Parser [Located Token]
insertBraces = (concat <$> many unit) <* Parsec.eof
  where

  unit :: Parser [Located Token]
  unit = unitWhere (const True)

  unitWhere :: (Located Token -> Bool) -> Parser [Located Token]
  unitWhere predicate
    = Parsec.try (Parsec.lookAhead (tokenSatisfy predicate)) *> Parsec.choice
      [ bracket (BlockBegin Layoutness.Nonlayout) BlockEnd
      , bracket GroupBegin GroupEnd
      , bracket VectorBegin VectorEnd
      , layoutBlock
      , (:[]) <$> tokenSatisfy nonbracket
      ] <?> "layout item"

  bracket :: Token -> Token -> Parser [Located Token]
  bracket open close = do
    begin <- parserMatch open
    inner <- concat <$> many unit
    end <- parserMatch close
    return (begin : inner ++ [end])

  nonbracket :: Located Token -> Bool
  nonbracket = not . (`elem` brackets) . Located.item

  brackets :: [Token]
  brackets = blockBrackets ++
    [ GroupBegin
    , GroupEnd
    , VectorBegin
    , VectorEnd
    ]

  blockBrackets :: [Token]
  blockBrackets =
    [ BlockBegin Layoutness.Nonlayout
    , BlockEnd
    , Layout
    ]

  layoutBlock :: Parser [Located Token]
  layoutBlock = do
    colon <- parserMatch Layout
    let
      colonOrigin = Located.origin colon
      Indent colonIndent = Located.indent colon
      validFirst = (> colonIndent)
        . Parsec.sourceColumn . Origin.begin . Located.origin
    firstToken <- Parsec.lookAhead (tokenSatisfy validFirst)
      <?> "a token with a source column greater than \
          \the start of the layout block"
    let
      firstOrigin = Origin.begin (Located.origin firstToken)
      inside = (>= Parsec.sourceColumn firstOrigin)
        . Parsec.sourceColumn . Origin.begin . Located.origin

    body <- concat <$> many (unitWhere inside)
    return $ At colonOrigin (Indent colonIndent) (BlockBegin Layoutness.Layout)
      : body ++ [At colonOrigin (Indent colonIndent) BlockEnd]
