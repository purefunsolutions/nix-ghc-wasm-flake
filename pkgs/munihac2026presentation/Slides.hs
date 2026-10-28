-- | A deck is Markdown with slides separated by @---@ lines.
module Slides (Slide (..), parseDeck, renderSlide) where

import Markdown

data Slide = Slide
  { -- | From an @\@class name@ directive, for per-slide layout.
    slideClass :: String,
    slideBlocks :: [Block]
  }

parseDeck :: String -> [Slide]
parseDeck = map (toSlide . parseBlocks) . splitSlides . lines
  where
    toSlide blocks = Slide (concat [c | Directive "class" c <- blocks]) [b | b <- blocks, not (isClass b)]
    isClass (Directive "class" _) = True
    isClass _ = False

splitSlides :: [String] -> [[String]]
splitSlides ls = case break ((== "---") . trim) ls of
  (slide, []) -> [slide]
  (slide, _ : rest) -> slide : splitSlides rest

-- | Renders a slide's HTML, asking the given handler to render directives.
renderSlide :: (String -> String -> IO String) -> Slide -> IO String
renderSlide directive = fmap concat . traverse render . slideBlocks
  where
    render (Directive name args) = directive name args
    render block = pure (renderBlock block)
