-- Prepare PowerPoint-inspired EMC slides for the CSS in emc-slides.css.
--
-- This filter changes slides only when the document has
-- emc-theme: graduate|sophia|general.
-- It changes the Pandoc document before Quarto writes Reveal.js HTML. It does
-- not draw or position slides: the CSS does that, while title-slide.html
-- builds the title slide. The filter lets authors use ordinary Markdown below
-- a level-2 heading without repeating layout wrappers and theme classes.
--
-- For each level-2 slide it:
--   * adds emc-theme-<theme> and, usually, emc-content-slide;
--   * wraps ordinary content in .emc-slide-content;
--   * turns optional image/kicker/subtitle heading attributes into slide
--     elements;
--   * marks a paragraph that is entirely bold as a larger stand-out line;
--   * separates the plot from its explanation on a .emc-plot-slide;
--   * moves a ::: {.emc-citation} block to a line at the bottom of the slide;
--     and
--   * inserts decorative brand art, and an optional photo, on a closing slide.
-- A slide with .emc-unfiltered skips these transformations. The same layout
-- can be authored manually with heading classes and fenced Divs; see README.
-- .emc-no-auto-content keeps the theme and extras but skips only the wrapper.
-- An explicit .emc-theme-sophia, .emc-theme-graduate, or .emc-theme-general
-- on a slide overrides the document's emc-theme for that slide.

local themes = { graduate = true, sophia = true, general = true }

-- Short names accepted by image="..." on the three photo layouts. Any other
-- value is treated as a local image path supplied by the presentation author.
local image_presets = {
  ["math-surface"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/math-surface.png",
  ["stats-clusters"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/stats-clusters.png",
  ["geometry-glass"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/geometry-glass.png",
  ["distribution-ridges"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/distribution-ridges.png",
  ["formula-chalkboard"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/formula-chalkboard.png",
  ["r-code"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/r-code.svg",
  ["bluecode"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/bluecode.jpg",
  ["blackcode"] = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/blackcode.jpg",
}
local image_focuses = { left = true, center = true, right = true, top = true, bottom = true }

-- Accept older .pptx-* names on slide headings and fenced Divs. This does not
-- change similarly named spans or arbitrary HTML classes.
local function canonicalize_classes(element)
  for i, class in ipairs(element.classes) do
    if class:sub(1, 5) == "pptx-" then
      element.classes[i] = "emc-" .. class:sub(6)
    elseif class == "attribution" then
      -- The quarto-ext/attribution syntax, shown here as a citation line.
      element.classes[i] = "emc-citation"
    end
  end
end

local function canonicalize_divs(blocks)
  for _, block in ipairs(blocks) do
    if block.t == "Div" then
      canonicalize_classes(block)
      canonicalize_divs(block.content)
    end
  end
end

local function has_class(element, name)
  for _, class in ipairs(element.classes) do
    if class == name then return true end
  end
  return false
end

-- A slide may use another bundled look in a layout gallery. Keep an explicit
-- .emc-theme-* class instead of appending the document-wide theme as well.
local function ensure_theme_class(heading, default_theme)
  local chosen
  for _, class in ipairs(heading.classes) do
    local name = class:match("^emc%-theme%-(.+)$")
    if name and name ~= "accent" then
      if not themes[name] then
        error("slide theme must be graduate, sophia, or general")
      end
      if chosen and chosen ~= name then
        error("a slide can have only one emc-theme-* class")
      end
      chosen = name
    end
  end
  if not chosen then heading.classes:insert("emc-theme-" .. default_theme) end
end

-- A heading's kicker="..." or subtitle="..." becomes a separate, plain-text
-- Div that the CSS can position. Remove the attribute so it is not emitted on
-- the HTML section as well.
local function add_slide_extra(result, heading, attribute, class)
  local value = heading.attributes[attribute]
  if value and value ~= "" then
    heading.attributes[attribute] = nil
    result:insert(pandoc.Div({pandoc.Para({pandoc.Str(value)})},
      pandoc.Attr("", {class})))
  end
end

-- A paragraph containing only bold text, such as **Main point**, is a
-- stand-out line in the PowerPoint originals. Wrap it in .emc-standout so the
-- CSS can enlarge it; bold words within a sentence keep the body size.
local function mark_standout_lines(blocks)
  return pandoc.Blocks(blocks):walk({
    Para = function(para)
      if #para.content == 1 and para.content[1].t == "Strong" then
        para.content = {pandoc.Span(para.content, pandoc.Attr("", {"emc-standout"}))}
        return para
      end
    end,
  })
end

-- An explicit image="preset-or-path" becomes an image layer above the CSS
-- default photo. image-focus selects its crop. With no image attribute, the
-- theme's default photo remains in the CSS background for this layout.
local photo_layouts = {
  "emc-dark-photo-slide", "emc-image-dark-box", "emc-image-light-box",
  "emc-light-photo-slide", "emc-statement-slide", "emc-closing-slide",
}

-- A ::: {.emc-citation} block becomes a line at the bottom of the slide, so
-- the CSS can place it beside the logo and page number. Layouts whose lower
-- area is covered by a photo or panel keep the citation with their text.
local citation_in_place = {
  "emc-image-dark-box", "emc-image-light-box", "emc-light-photo-slide",
  "emc-statement-slide",
}

local function take_citations(heading, content)
  for _, class in ipairs(citation_in_place) do
    if has_class(heading, class) then return content, pandoc.List() end
  end
  local kept, citations = pandoc.List(), pandoc.List()
  for _, block in ipairs(content) do
    if block.t == "Div" and has_class(block, "emc-citation") then
      block.classes:insert("emc-footer-citation")
      citations:insert(block)
    else
      kept:insert(block)
    end
  end
  return kept, citations
end

local function add_slide_image(result, heading)
  local value = heading.attributes.image
  local is_photo_layout = false
  for _, class in ipairs(photo_layouts) do
    if has_class(heading, class) then is_photo_layout = true end
  end
  if not is_photo_layout then return end
  local focus = heading.attributes["image-focus"]
  if focus then
    if not image_focuses[focus] then
      error("image-focus must be left, center, right, top, or bottom")
    end
    heading.attributes["image-focus"] = nil
    heading.classes:insert("emc-image-focus-" .. focus)
  end
  if not value or value == "" then return end
  heading.attributes.image = nil
  local image = pandoc.Image({}, image_presets[value] or value, "",
    pandoc.Attr("", {"emc-slide-image"}))
  result:insert(pandoc.Div({pandoc.Para({image})},
    pandoc.Attr("", {"emc-image-layer"})))
end

local function contains_image(block)
  local found = false
  pandoc.Blocks({block}):walk({Image = function() found = true end})
  return found
end

-- On a .emc-plot-slide, the plot and its explanation get separate areas so
-- they never overlap. An explicit ::: {.emc-plot} Div is the plot; otherwise
-- the first block containing an image (a Markdown image, a figure, or a code
-- cell's figure output) is. Speaker notes stay with the explanation.
local function split_plot(content)
  local plot_index
  for index, block in ipairs(content) do
    if block.t == "Div" and has_class(block, "emc-plot") then
      plot_index = index
      break
    end
  end
  if not plot_index then
    for index, block in ipairs(content) do
      if not (block.t == "Div" and has_class(block, "notes")) and contains_image(block) then
        plot_index = index
        break
      end
    end
  end
  if not plot_index then
    error(".emc-plot-slide needs an image, a figure, or a ::: {.emc-plot} block")
  end
  local text = pandoc.List()
  for index, block in ipairs(content) do
    if index ~= plot_index then text:insert(block) end
  end
  local plot = content[plot_index]
  if not (plot.t == "Div" and has_class(plot, "emc-plot")) then
    plot = pandoc.Div({plot}, pandoc.Attr("", {"emc-plot"}))
  end
  return text, plot
end

function Pandoc(doc)
  -- Standard EMC presentations have no emc-theme and pass through unchanged.
  if not doc.meta["emc-theme"] then return doc end
  local theme = pandoc.utils.stringify(doc.meta["emc-theme"]):lower()
  if not themes[theme] then
    error("emc-theme must be graduate, sophia, or general")
  end
  -- emc-hide-squares: true removes the square patterns from every slide; the
  -- title partial reads the same option for the title slide.
  local hide_squares = doc.meta["emc-hide-squares"]
  hide_squares = hide_squares == true or
    (hide_squares ~= nil and pandoc.utils.stringify(hide_squares) == "true")
  local function apply_deck_options(heading)
    if hide_squares and not has_class(heading, "emc-no-squares") then
      heading.classes:insert("emc-no-squares")
    end
  end

  local result = pandoc.List()
  local i = 1
  while i <= #doc.blocks do
    local block = doc.blocks[i]
    if block.t == "Header" and block.level == 2 then
      local heading = block
      canonicalize_classes(heading)
      local content = pandoc.List()
      i = i + 1
      -- Collect this slide's blocks up to the next level-1 or level-2 heading.
      while i <= #doc.blocks do
        local next_block = doc.blocks[i]
        if next_block.t == "Header" and next_block.level <= 2 then break end
        content:insert(next_block)
        i = i + 1
      end

      if has_class(heading, "emc-unfiltered") then
        -- Leave the slide layout alone. Only older .pptx-* heading classes
        -- were renamed above; content and theme classes are not altered.
        result:insert(heading)
        for _, item in ipairs(content) do result:insert(item) end
      elseif has_class(heading, "emc-closing-slide") then
        -- Closing slides have their own structure and do not get a content
        -- wrapper. The empty Div supplies CSS-drawn logo and square artwork.
        canonicalize_divs(content)
        ensure_theme_class(heading, theme)
        apply_deck_options(heading)
        result:insert(heading)
        -- image="preset-or-path" replaces the theme's closing photo.
        add_slide_image(result, heading)
        result:insert(pandoc.RawBlock("html", '<div class="emc-brand-art" aria-hidden="true"></div>'))
        for _, item in ipairs(content) do result:insert(item) end
      else
        -- For an ordinary slide, add theme/content classes and optional
        -- photo, kicker, and subtitle elements before its body content.
        canonicalize_divs(content)
        content = mark_standout_lines(content)
        ensure_theme_class(heading, theme)
        apply_deck_options(heading)
        if not has_class(heading, "emc-content-slide") then
          heading.classes:insert("emc-content-slide")
        end
        local citations
        content, citations = take_citations(heading, content)
        result:insert(heading)
        add_slide_image(result, heading)
        add_slide_extra(result, heading, "kicker", "emc-slide-kicker")
        add_slide_extra(result, heading, "subtitle", "emc-slide-subtitle")
        -- Custom slides can opt out of the wrapper. An existing single
        -- .emc-slide-content Div is respected rather than nested twice.
        if has_class(heading, "emc-plot-slide") then
          local text, plot = split_plot(content)
          result:insert(pandoc.Div(text, pandoc.Attr("", {"emc-slide-content", "emc-plot-text"})))
          result:insert(plot)
        elseif has_class(heading, "emc-no-auto-content") or
            (#content == 1 and content[1].t == "Div" and
             has_class(content[1], "emc-slide-content")) then
          for _, item in ipairs(content) do result:insert(item) end
        else
          result:insert(pandoc.Div(content, pandoc.Attr("", {"emc-slide-content"})))
        end
        for _, citation in ipairs(citations) do result:insert(citation) end
      end
    else
      result:insert(block)
      i = i + 1
    end
  end
  doc.blocks = result
  return doc
end
