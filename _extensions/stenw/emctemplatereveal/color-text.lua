-- Keep [text]{color="#hex"} and allow custom accents on .emc-callout boxes.
-- Named colors use brand classes; arbitrary CSS colors retain the old behavior.
local named_colors = {
  accent = "emc-accent",
  ["dark-blue"] = "emc-dark-blue",
  ["light-blue"] = "emc-light-blue",
  ["medium-blue"] = "emc-medium-blue",
  ["dark-blue-variant"] = "emc-dark-blue-variant",
  ["light-blue-variant"] = "emc-light-blue-variant",
  ["dark-blue-80"] = "emc-dark-blue-80",
  ["light-blue-80"] = "emc-light-blue-80",
  ["very-light-blue"] = "emc-very-light-blue",
  green = "emc-green",
  teal = "emc-green",
  red = "emc-red",
  purple = "emc-purple",
  lilac = "emc-lilac",
  orange = "emc-orange",
  ["light-grey"] = "emc-light-grey",
}

local function add_style(el, declaration)
  local style = el.attributes.style or ""
  if style ~= "" and not style:match(";%s*$") then
    style = style .. ";"
  end
  el.attributes.style = style .. declaration .. ";"
end

function Span(el)
  local color = el.attributes.color
  if not color then
    return nil
  end

  el.attributes.color = nil
  local class = named_colors[color:lower()]
  if class then
    el.classes:insert(class)
    return el
  end
  add_style(el, "color: " .. color)
  return el
end

function Div(el)
  local is_callout = false
  for _, class in ipairs(el.classes) do
    if class == "emc-callout" then
      is_callout = true
      break
    end
  end
  if not is_callout then
    return nil
  end

  local color = el.attributes.color
  if not color then
    return nil
  end
  -- A hex value keeps the generated style declaration well formed.
  if not color:match("^#%x%x%x$") and not color:match("^#%x%x%x%x%x%x$") then
    return nil
  end

  el.attributes.color = nil
  add_style(el, "--emc-callout-accent: " .. color)
  return el
end
