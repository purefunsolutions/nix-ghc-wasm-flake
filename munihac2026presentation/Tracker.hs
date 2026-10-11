-- | The "Upstream tracker" table from the repository's README.md, which is
-- where the statuses of all upstream changes are kept up to date.
module Tracker (Tracker (..), Row (..), parseTracker, renderTracker, renderSummary) where

import Data.Char (isAlphaNum, isDigit, toLower)
import Data.List (findIndex, intercalate, isInfixOf, isPrefixOf, nub)
import Markdown

data Row = Row
  { rowWhere :: String
  , rowChange :: String
  , rowBy :: String
  , rowStatus :: String
  }

data Tracker = Tracker
  { -- | From "Statuses as of 2026-10-11." above the table.
    trackerAsOf :: Maybe String
  , trackerRows :: [Row]
  }

parseTracker :: String -> Either String Tracker
parseTracker readme = do
  let section =
        takeWhile (not . ("## " `isPrefixOf`)) . drop 1
          . dropWhile ((/= "## Upstream tracker") . trim)
          $ lines readme
  (header, rows) <- case [(h, rs) | Table h rs <- parseBlocks section] of
    t : _ -> Right t
    [] -> Left "README.md has no table under \"## Upstream tracker\""
  let column name = maybe (Left ("the tracker table has no " ++ name ++ " column")) Right $
        findIndex ((== name) . map toLower) header
  w <- column "where"
  c <- column "change"
  b <- column "by"
  s <- column "status"
  let cell i r = if i < length r then r !! i else ""
  pure
    Tracker
      { trackerAsOf = asOf (unwords section)
      , trackerRows = [Row (cell w r) (cell c r) (cell b r) (cell s r) | r <- rows]
      }
  where
    asOf text = case breakOn "Statuses as of " text of
      Just (_, rest) | date@(_ : _) <- takeWhile (\x -> isDigit x || x == '-') rest -> Just date
      _ -> Nothing

data Group = Merged | Open | ToDo | Other
  deriving (Eq)

classify :: Row -> Group
classify row
  | "merged" `isPrefixOf` status = Merged
  | any (`isPrefixOf` status) ["open", "draft"] = Open
  | any (`isInfixOf` status) ["not submitted", "to file", "to submit"] = ToDo
  | otherwise = Other
  where
    status = map toLower (trim (rowStatus row))

renderTracker :: Either String Tracker -> String
renderTracker (Left err) = "<p class=\"error\">Couldn't read the README's tracker: " ++ escape err ++ "</p>"
renderTracker (Right tracker) =
  "<p class=\"asof\">Template Haskell read this table from README.md when the slide deck was built"
    ++ maybe "." (\d -> "; these are the statuses as of " ++ escape d ++ ".") (trackerAsOf tracker)
    ++ "</p>"
    ++ "<div class=\"tracker\">"
    ++ column (if null merged then "Open" else "Open and merged") (merged ++ open)
    ++ column "Still to submit or file" (todo ++ other)
    ++ "</div>"
  where
    rows g = filter ((== g) . classify) (trackerRows tracker)
    merged = rows Merged
    open = rows Open
    todo = rows ToDo
    other = rows Other
    column title rs =
      "<section><h2>" ++ escape title ++ " <span class=\"count\">" ++ show (length rs) ++ "</span></h2><ul>"
        ++ concatMap renderRow rs
        ++ "</ul></section>"

renderRow :: Row -> String
renderRow row =
  "<li class=\"" ++ groupClass (classify row) ++ "\">"
    ++ "<span class=\"what\"><span class=\"where where-" ++ slug (rowWhere row) ++ "\">"
    ++ escape (rowWhere row)
    ++ "</span> "
    ++ (if null ids then "" else "<span class=\"ids\">" ++ inline ids ++ "</span> ")
    ++ inline summary
    ++ "</span><span class=\"state\">"
    ++ (if null (rowBy row) then "" else "<span class=\"who\">" ++ inline (rowBy row) ++ "</span> ")
    ++ inline (rowStatus row)
    ++ "</span></li>"
  where
    (ids, summary) = splitChange (rowChange row)
    slug = map toLower . filter isAlphaNum
    groupClass g = case g of
      Merged -> "merged"
      Open -> "open"
      ToDo -> "todo"
      Other -> "other"

-- | Splits "[!123](…) ([#45](…)): what it does; why" into the links and
-- "what it does".
splitChange :: String -> (String, String)
splitChange change = case breakOn ": " change of
  Just (ids, rest) | "](" `isInfixOf` ids -> (ids, summary rest)
  _ -> ("", summary change)
  where
    summary = trim . takeWhile (/= ';')

-- | What's still ahead, counted per project: "in GHC, six changes to get
-- merged (two of them not submitted yet) and two issues still to file; …".
renderSummary :: Either String Tracker -> String
renderSummary (Left err) = renderTracker (Left err)
renderSummary (Right tracker) =
  "<p class=\"summary\"><strong>Still ahead,</strong> going by the README: "
    ++ intercalate "; " (filter (not . null) (map project projects))
    ++ ".</p>"
  where
    pending = [r | r <- trackerRows tracker, classify r /= Merged]
    projects = nub (map rowWhere pending)
    isIssue r = "issue" `isInfixOf` map toLower (rowStatus r)
    project p =
      let rs = filter ((== p) . rowWhere) pending
          changes = filter (not . isIssue) rs
          unsent = filter ((== ToDo) . classify) changes
          issues = filter isIssue rs
       in "in " ++ escape p ++ ", "
            ++ intercalate
              " and "
              ( [ count (length changes) "change" ++ " to get merged"
                    ++ ( if null unsent
                           then ""
                           else
                             " ("
                               ++ (if length unsent == length changes then "" else number (length unsent) ++ " of them ")
                               ++ "not submitted yet)"
                       )
                | not (null changes)
                ]
                  ++ [count (length issues) "issue" ++ " still to file" | not (null issues)]
              )
    count n noun = number n ++ " " ++ noun ++ (if n == 1 then "" else "s")
    number n
      | n <= 12 = words "zero one two three four five six seven eight nine ten eleven twelve" !! n
      | otherwise = show n
