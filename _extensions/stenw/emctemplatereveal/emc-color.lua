-- Use named brand colors without writing HTML or CSS in a Quarto document.
local colors = {
  ["accent"] = "emc-theme-accent",
  ["dark-blue"] = "emc-dark-blue",
  ["light-blue"] = "emc-light-blue",
  ["medium-blue"] = "emc-medium-blue",
  ["dark-blue-variant"] = "emc-dark-blue-variant",
  ["light-blue-variant"] = "emc-light-blue-variant",
  ["dark-blue-80"] = "emc-dark-blue-80",
  ["light-blue-80"] = "emc-light-blue-80",
  ["very-light-blue"] = "emc-very-light-blue",
  ["green"] = "emc-green",
  ["teal"] = "emc-green",
  ["red"] = "emc-red",
  ["purple"] = "emc-purple",
  ["lilac"] = "emc-lilac",
  ["orange"] = "emc-orange",
  ["light-grey"] = "emc-light-grey",
}

return {
  ["emc-color"] = function(args)
    if #args < 2 then
      error('emc-color needs a color and text, for example {{< emc-color red "Important result" >}}')
    end
    local name = pandoc.utils.stringify(args[1]):lower()
    local class = colors[name]
    if not class then
      error("Unknown emc-color: " .. name)
    end
    local words = {}
    for i = 2, #args do
      words[#words + 1] = pandoc.utils.stringify(args[i])
    end
    local phrase = table.concat(words, " ")
    if phrase == "" then error("emc-color needs text after the color name") end
    return pandoc.Span({pandoc.Str(phrase)}, pandoc.Attr("", {class}))
  end,
}
