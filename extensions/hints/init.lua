--- === hs.hints ===
---
--- Switch focus with a transient per-application keyboard shortcut

local hints = require "hs.hints.internal"
local screen = require "hs.screen"
local window = require "hs.window"
local hotkey = require "hs.hotkey"
local modal_hotkey = hotkey.modal

--- hs.hints.hintChars
--- Variable
--- This controls the set of characters that will be used for window hints. They must be characters found in hs.keycodes.map
--- The default is the letters A-Z.
hints.hintChars = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}

--- hs.hints.style
--- Variable
--- If this is set to "vimperator", every window hint starts with the first character
--- of the parent application's title
hints.style = "default"

--- hs.hints.fontName
--- Variable
--- A fully specified family-face name, preferrably the PostScript name, such as Helvetica-BoldOblique or Times-Roman. (The Font Book app displays PostScript names of fonts in the Font Info panel.)
--- The default value is the system font
hints.fontName = nil

--- hs.hints.fontSize
--- Variable
--- The size of font that should be used. A value of 0.0 will use the default size.
hints.fontSize = 0.0

--- hs.hints.showTitleThresh
--- Variable
--- If there are less than or equal to this many windows on screen their titles will be shown in the hints.
--- The default is 4. Setting to 0 will disable this feature.
hints.showTitleThresh = 4

local openHints = {}
local takenPositions = {}
local hintDict = {}
local modalKey = nil

local bumpThresh = 40^2
local bumpMove = 80

function hints.bumpPos(x,y)
  for i, pos in ipairs(takenPositions) do
    if ((pos.x-x)^2 + (pos.y-y)^2) < bumpThresh then
      return hints.bumpPos(x,y+bumpMove)
    end
  end
  return {x = x,y = y}
end

function hints.addWindow(dict, win)
  local n = dict['count']
  if n == nil then
    dict['count'] = 0
    n = 0
  end
  local m = (n % #hints.hintChars) + 1
  local char = hints.hintChars[m]
  if n < #hints.hintChars then
    dict[char] = win
  else
    if type(dict[char]) == "userdata" then
      -- dict[m] is already occupied by another window
      -- which me must convert into a new dictionary
      local otherWindow = dict[char]
      dict[char] = {}
      hints.addWindow(dict, otherWindow)
    end
    hints.addWindow(dict[char], win)
  end
  dict['count'] = dict['count'] + 1
end

-- Private helper to recursively find the total number of hints in a dict
function hints._dictSize(t)
  if type(t) == "userdata" and t:screen() then -- onscreen window
    return 1
  elseif type(t) == "table" then
    local count = 0
    for _,v in pairs(t) do count = count + hints._dictSize(v) end
    return count
  end
  return 0 -- screenless window or something else
end

function hints.displayHintsForDict(dict, prefixstring, showTitles)
  if showTitles == nil then
    showTitles = hints._dictSize(hintDict) <= hints.showTitleThresh
  end
  for key, val in pairs(dict) do
    if type(val) == "userdata" and val:screen() then -- this is an onscreen window
      local win = val
      local app = win:application()
      local fr = win:frame()
      local sfr = win:screen():frame()
      if app and win:isStandard() then
        local c = {x = fr.x + (fr.w/2) - sfr.x, y = fr.y + (fr.h/2) - sfr.y}
        local d = hints.bumpPos(c.x, c.y)
        if d.y > (sfr.y + sfr.h - bumpMove) then
            d.x = d.x + bumpMove
            d.y = fr.y + (fr.h/2) - sfr.y
            d = hints.bumpPos(d.x, d.y)
        end
        c = d
        if c.y < 0 then
          print("hs.hints: Skipping offscreen window: "..win:title())
        else
          local suffixString = ""
          if showTitles then
            suffixString = ": "..win:title()
          end
          -- print(win:title().." x:"..c.x.." y:"..c.y) -- debugging
          local hint = hints.new(c.x, c.y, prefixstring .. key .. suffixString, app:bundleID(), win:screen(), hints.fontName, hints.fontSize)
          table.insert(takenPositions, c)
          table.insert(openHints, hint)
        end
      end
    elseif type(val) == "table" then -- this is another window dict
      hints.displayHintsForDict(val, prefixstring .. key, showTitles)
    end
  end
end

function hints.processChar(char)
  if hintDict[char] ~= nil then
    hints.closeHints()
    if type(hintDict[char]) == "userdata" then
      if hintDict[char] then hintDict[char]:focus() end
      modalKey:exit()
    elseif type(hintDict[char]) == "table" then
      hintDict = hintDict[char]
      if hintDict.count == 1 then
        hintDict.A:focus()
        modalKey:exit()
      else
        takenPositions = {}
        hints.displayHintsForDict(hintDict, "")
      end
    end
  end
end

function hints.setupModal()
  k = modal_hotkey.new(nil, nil)
  k:bind({}, 'escape', function() hints.closeHints(); k:exit() end)

  for _, c in ipairs(hints.hintChars) do
    k:bind({}, c, function() hints.processChar(c) end)
  end
  return k
end

--- hs.hints.windowHints(windows)
--- Function
--- Displays a keyboard hint for switching focus to each window
---
--- Parameters:
---  * windows - A table containing some `hs.window` objects
---
--- Returns:
---  * None
---
--- Notes:
---  * If there are more windows open than there are characters available in hs.hints.hintChars,
---    we resort to multi-character hints
---  * If hints.style is set to "vimperator", every window hint is prefixed with the first
---    character of the parent application's name
---  * To display hints only for the currently focused application, try something like:
---   * `hs.hints.windowHints(hs.window.focusedWindow():application():allWindows())`
function hints.windowHints(windows)

  windows = windows or window.allWindows()

  if (modalKey == nil) then
    modalKey = hints.setupModal()
  end
  hints.closeHints()
  hintDict = {}
  for i, win in ipairs(windows) do
    local app = win:application()
    if app and win:isStandard() then
      if hints.style == "vimperator" then
        if app and win:isStandard() then
          local appchar = string.upper(string.sub(app:title(), 1, 1))
          modalKey:bind({}, appchar, function() hints.processChar(appchar) end)
          if hintDict[appchar] == nil then
            hintDict[appchar] = {}
          end
          hints.addWindow(hintDict[appchar], win)
        end
      else
        hints.addWindow(hintDict, win)
      end
    end
  end
  takenPositions = {}
  if next(hintDict) ~= nil then
    hints.displayHintsForDict(hintDict, "")
    modalKey:enter()
  end
end

function hints.closeHints()
  for _, hint in ipairs(openHints) do
    hint:close()
  end
  openHints = {}
  takenPositions = {}
end

return hints
