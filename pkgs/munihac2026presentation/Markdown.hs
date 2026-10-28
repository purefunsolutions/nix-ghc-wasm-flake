-- | A deliberately tiny Markdown dialect, just enough for the slides and for
-- reading the README's tables.
module Markdown
  ( Block (..),
    parseBlocks,
    renderBlock,
    inline,
    escape,
    trim,
    breakOn,
  )
where

import Data.Char (isSpace)
import Data.List (isPrefixOf)

data Block
  = Heading Int String
  | Para String
  | Bullets [String]
  | Code String
  | -- | Header cells and rows, each a list of cells.
    Table [String] [[String]]
  | -- | @\@name args@ on a line of its own.
    Directive String String
  deriving (Show)

parseBlocks :: [String] -> [Block]
parseBlocks [] = []
parseBlocks (l : ls)
  | all isSpace l = parseBlocks ls
  | "```" `isPrefixOf` l =
      let (code, rest) = break ("```" `isPrefixOf`) ls
       in Code (unlines code) : parseBlocks (drop 1 rest)
  | "#" `isPrefixOf` l =
      let (hashes, title) = span (== '#') l
       in Heading (length hashes) (trim title) : parseBlocks ls
  | "@" `isPrefixOf` l =
      let (name, args) = break isSpace (drop 1 l)
       in Directive name (trim args) : parseBlocks ls
  | isBullet l =
      let (items, rest) = bullets (l : ls)
       in Bullets items : parseBlocks rest
  | "|" `isPrefixOf` l =
      let (rows, rest) = span ("|" `isPrefixOf`) (l : ls)
       in table (map cells rows) : parseBlocks rest
  | otherwise =
      let (para, rest) = break endsPara ls
       in Para (unwords (map trim (l : para))) : parseBlocks rest
  where
    endsPara x = all isSpace x || any (`isPrefixOf` x) ["```", "#", "@", "|"] || isBullet x

isBullet :: String -> Bool
isBullet l = "- " `isPrefixOf` l

-- | Bullets, each with its indented continuation lines.
bullets :: [String] -> ([String], [String])
bullets (l : ls)
  | isBullet l =
      let (cont, rest) = span continues ls
          (items, rest') = bullets rest
       in (unwords (map trim (drop 2 l : cont)) : items, rest')
bullets ls = ([], ls)

continues :: String -> Bool
continues l@(c : _) = isSpace c && not (all isSpace l)
continues [] = False

table :: [[String]] -> Block
table [] = Table [] []
table (header : rows) = Table header (filter (not . isSeparator) rows)
  where
    isSeparator = all (all (`elem` "-: "))

cells :: String -> [String]
cells = map trim . splitOn '|' . dropEnd . drop 1 . trim
  where
    dropEnd s = if not (null s) && last s == '|' then init s else s

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, []) -> [a]
  (a, _ : rest) -> a : splitOn c rest

-- | Renders a block; directives are left to the caller.
renderBlock :: Block -> String
renderBlock block = case block of
  Heading n title -> tag ("h" ++ show (min 6 n)) (inline title)
  Para text -> tag "p" (inline text)
  Bullets items -> tag "ul" (concatMap (tag "li" . inline) items)
  Code code -> tag "pre" (tag "code" (escape code))
  Table header rows ->
    tag "table" $
      tag "thead" (tag "tr" (concatMap (tag "th" . inline) header))
        ++ tag "tbody" (concatMap (tag "tr" . concatMap cell) rows)
  Directive name _ -> "<p class=\"error\">Unknown directive @" ++ escape name ++ "</p>"
  where
    cell c
      | c == "✓" = "<td class=\"ok\">✓</td>"
      | otherwise = tag "td" (inline c)

tag :: String -> String -> String
tag t body = "<" ++ t ++ ">" ++ body ++ "</" ++ t ++ ">"

-- | Inline Markdown: code spans, bold and links.
inline :: String -> String
inline s = case s of
  [] -> []
  '`' : rest
    | (code, '`' : rest') <- break (== '`') rest ->
        "<code>" ++ escape code ++ "</code>" ++ inline rest'
  '*' : '*' : rest
    | Just (bold, rest') <- breakOn "**" rest ->
        "<strong>" ++ inline bold ++ "</strong>" ++ inline rest'
  '[' : rest
    | (text, ']' : '(' : rest') <- break (== ']') rest,
      (url, ')' : rest'') <- break (== ')') rest' ->
        "<a href=\""
          ++ escape url
          ++ "\" target=\"_blank\" rel=\"noopener\">"
          ++ inline text
          ++ "</a>"
          ++ inline rest''
  c : rest -> escape [c] ++ inline rest

escape :: String -> String
escape = concatMap esc
  where
    esc '<' = "&lt;"
    esc '>' = "&gt;"
    esc '&' = "&amp;"
    esc '"' = "&quot;"
    esc c = [c]

trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse

-- | Splits at the first occurrence of the needle, dropping it.
breakOn :: String -> String -> Maybe (String, String)
breakOn needle = go []
  where
    go _ [] = Nothing
    go acc s@(c : rest)
      | needle `isPrefixOf` s = Just (reverse acc, drop (length needle) s)
      | otherwise = go (c : acc) rest
