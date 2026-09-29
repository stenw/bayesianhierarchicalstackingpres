-- Add one of the optional brand backgrounds to a slide heading. Reveal
-- resolves these URLs from the rendered HTML, so include the extension path.
local backgrounds = {
  triangledb = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/triangledb.svg",
  trianglelb = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/trianglelb.svg",
  lbback = "_extensions/stenw/emctemplatereveal/layoutassets/backgrounds/lbback.svg",
}

function Header(el)
  -- An author's explicit background takes precedence over a class preset.
  if el.attributes["background"] or el.attributes["background-image"]
      or el.attributes["data-background"] or el.attributes["data-background-image"] then
    return nil
  end

  for _, class in ipairs(el.classes) do
    local image = backgrounds[class]
    if image then
      el.attributes["data-background-image"] = image
      return el
    end
  end
end
