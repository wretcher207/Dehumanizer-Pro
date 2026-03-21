-- @description DeHumanizer Pro
-- @version 5.4
-- @author Dead Pixel Design
-- @links
--   Website https://www.deadpixeldesign.com
-- @about
--   # DeHumanizer Pro
--   Intentional dynamics shaping for modern drum programming.
--   Two independent engines, each with their own drawable curve and apply button:
--
--   ## Velocity Engine
--   - Time-mapped curve drawing with interpolation
--   - Role-aware filtering (Kick, Snare, Cymbals, etc.)
--   - Smart Phrase Reset logic
--   - Velocity preview before committing
--   - Right-click erase on curve canvas
--   - Full persistence (settings + curve)
--
--   ## Timing Engine
--   - Per-kit-piece lean (rush/drag) + variance
--     with biased bell-curve distribution and tempo-aware PPQ math
--   - Timing tooltip: live BPM-aware preview of lean offset in ms and PPQ
--   - Timing Variance Curve: drawable per-role curve mapping phrase position
--     to a variance multiplier (0x at bottom, 1x center, 2x top)
--   - Beat-aware tightening: beats 1/2/3/4 use 30% scatter

local SCRIPT_ID = "DEAD_PIXEL_DEHUMANIZER"

-- ================= CONFIGURATION =================
local CONFIG = {
  curve_points         = 256,
  golden_rule_min_diff = 4,
  phrase_gap_qn        = 1.0,
  max_lean_ms          = 15,
  max_variance_ms      = 15,
}

local ROLE_MAP = {
  Kicks   = {35, 36},
  Snare   = {38, 40},
  Hihat   = {42, 44, 46},
  Ride    = {51, 53, 59},
  Toms    = {41, 43, 45, 47, 48, 50},
  Cymbals = {49, 52, 55, 57},
}

local ROLES            = {"Kicks","Snare","Hihat","Ride","Toms","Cymbals","All"}
local TIMING_ROLE_KEYS = {"Kicks","Snare","Hihat","Ride","Toms","Cymbals"}

-- ================= DATA PERSISTENCE =================

local function serialize_curve(curve)
  local parts = {}
  for i = 1, #curve do
    parts[i] = string.format("%.4f", curve[i])
  end
  return table.concat(parts, ",")
end

local function deserialize_curve(str, num_points)
  local curve = {}
  local i = 1
  for val in str:gmatch("[^,]+") do
    curve[i] = tonumber(val) or 0.5
    i = i + 1
  end
  while #curve < num_points do curve[#curve + 1] = 0.5 end
  if #curve > num_points then
    local trimmed = {}
    for j = 1, num_points do trimmed[j] = curve[j] end
    curve = trimmed
  end
  return curve
end

local function save_settings(data)
  reaper.SetExtState(SCRIPT_ID, "minv",     tostring(data.minv),     true)
  reaper.SetExtState(SCRIPT_ID, "maxv",     tostring(data.maxv),     true)
  reaper.SetExtState(SCRIPT_ID, "drift",    tostring(data.drift),    true)
  reaper.SetExtState(SCRIPT_ID, "strength", tostring(data.strength), true)
  if data.curve then
    reaper.SetExtState(SCRIPT_ID, "curve", serialize_curve(data.curve), true)
  end
  if data.timing then
    for _, role in ipairs(TIMING_ROLE_KEYS) do
      local t = data.timing[role]
      if t then
        reaper.SetExtState(SCRIPT_ID, "t_lean_"    .. role, tostring(t.lean_ms),     true)
        reaper.SetExtState(SCRIPT_ID, "t_var_"     .. role, tostring(t.variance_ms), true)
        reaper.SetExtState(SCRIPT_ID, "t_enabled_" .. role, t.enabled and "1" or "0", true)
      end
    end
  end
  -- Persist timing variance curves (one per role)
  if data.timing_var_curve then
    for _, role in ipairs(TIMING_ROLE_KEYS) do
      if data.timing_var_curve[role] then
        reaper.SetExtState(SCRIPT_ID, "tvc_" .. role, serialize_curve(data.timing_var_curve[role]), true)
      end
    end
  end
end

local function load_settings()
  local settings = {
    minv     = tonumber(reaper.GetExtState(SCRIPT_ID, "minv"))     or 60,
    maxv     = tonumber(reaper.GetExtState(SCRIPT_ID, "maxv"))     or 110,
    drift    = tonumber(reaper.GetExtState(SCRIPT_ID, "drift"))    or 8,
    strength = tonumber(reaper.GetExtState(SCRIPT_ID, "strength")) or 1.0,
    curve    = nil,
    timing   = {},
    timing_var_curve = {},
  }
  local curve_str = reaper.GetExtState(SCRIPT_ID, "curve")
  if curve_str and curve_str ~= "" then
    settings.curve = deserialize_curve(curve_str, CONFIG.curve_points)
  end
  for _, role in ipairs(TIMING_ROLE_KEYS) do
    local stored_enabled = reaper.GetExtState(SCRIPT_ID, "t_enabled_" .. role)
    settings.timing[role] = {
      lean_ms     = tonumber(reaper.GetExtState(SCRIPT_ID, "t_lean_" .. role)) or 0,
      variance_ms = tonumber(reaper.GetExtState(SCRIPT_ID, "t_var_"  .. role)) or 4,
      enabled     = (stored_enabled == "1"),
    }
    -- Load timing variance curve for this role; default to all-0.5
    local tvc_str = reaper.GetExtState(SCRIPT_ID, "tvc_" .. role)
    if tvc_str and tvc_str ~= "" then
      settings.timing_var_curve[role] = deserialize_curve(tvc_str, CONFIG.curve_points)
    else
      local default_tvc = {}
      for i = 1, CONFIG.curve_points do default_tvc[i] = 0.5 end
      settings.timing_var_curve[role] = default_tvc
    end
  end
  return settings
end

-- ================= MATH & MIDI HELPERS =================

math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000000))

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function round(v)        return math.floor(v + 0.5) end
local function lerp(a, b, t)   return a + (b - a) * t end

local function rand_var(r)
  return ((math.random() + math.random() + math.random()) / 3 * 2 - 1) * r
end

local function biased_rand_timing(lean_ms, variance_ms)
  return lean_ms + rand_var(variance_ms)
end

local function is_note_in_role(pitch, role_name)
  if role_name == "All" then return true end
  local pitches = ROLE_MAP[role_name]
  if not pitches then return false end
  for _, p in ipairs(pitches) do if p == pitch then return true end end
  return false
end

local function build_pitch_role_lookup()
  local lookup = {}
  for role, pitches in pairs(ROLE_MAP) do
    for _, p in ipairs(pitches) do
      if not lookup[p] then lookup[p] = role end
    end
  end
  return lookup
end

local function get_notes(take)
  local notes = {}
  local _, cnt = reaper.MIDI_CountEvts(take)
  local min_ppq, max_ppq = math.huge, 0
  for i = 0, cnt - 1 do
    local _, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if sel then
      notes[#notes + 1] = {
        idx      = i,
        ppq      = sppq,
        endppq   = eppq,
        chan     = chan,
        pitch    = pitch,
        orig_vel = vel,
        muted    = muted,
        qn       = reaper.MIDI_GetProjQNFromPPQPos(take, sppq),
      }
      if sppq < min_ppq then min_ppq = sppq end
      if sppq > max_ppq then max_ppq = sppq end
    end
  end
  table.sort(notes, function(a, b) return a.ppq < b.ppq end)
  return notes, min_ppq, max_ppq
end

-- ================= CURVE PAINTING =================

local function paint_curve(curve, idx, value, brush_size)
  for i = -brush_size, brush_size do
    local ii = idx + i
    if curve[ii] then
      curve[ii] = lerp(curve[ii], value, 1 - (math.abs(i) / (brush_size + 1)))
    end
  end
end

local function paint_curve_interpolated(curve, prev_idx, prev_val, curr_idx, curr_val, brush_size)
  if not prev_idx then
    paint_curve(curve, curr_idx, curr_val, brush_size)
    return
  end
  local dist = math.abs(curr_idx - prev_idx)
  if dist <= 1 then
    paint_curve(curve, curr_idx, curr_val, brush_size)
    return
  end
  for s = 0, dist do
    local t = s / dist
    local interp_idx = clamp(round(lerp(prev_idx, curr_idx, t)), 1, #curve)
    paint_curve(curve, interp_idx, lerp(prev_val, curr_val, t), brush_size)
  end
end

-- ================= VELOCITY HUMANIZER =================

local function humanize(notes, min_p, max_p, role, minv, maxv, drift, curve, strength)
  local total_range = max_p - min_p
  if total_range <= 0 then total_range = 1 end
  local drift_off, last_vel, last_qn = 0, -1, -1
  local max_dev = (maxv - minv) * 0.12
  for _, n in ipairs(notes) do
    if is_note_in_role(n.pitch, role) then
      if last_qn ~= -1 and (n.qn - last_qn) > CONFIG.phrase_gap_qn then
        drift_off = 0
        last_vel  = -1
      end
      local t     = (n.ppq - min_p) / total_range
      local c_idx = clamp(math.floor(t * (#curve - 1)) + 1, 1, #curve)
      local target_vel = lerp(minv, maxv, curve[c_idx])
      local vel = lerp(n.orig_vel, target_vel, strength)
      drift_off = clamp((drift_off + math.random(-2, 2)) * 0.95, -drift, drift)
      vel = vel + drift_off + rand_var(max_dev)
      if math.abs(vel - last_vel) < CONFIG.golden_rule_min_diff then
        vel = vel + (math.random() > 0.5 and CONFIG.golden_rule_min_diff or -CONFIG.golden_rule_min_diff)
      end
      n.new_vel = clamp(round(vel), 1, 127)
      last_vel, last_qn = n.new_vel, n.qn
    end
  end
end

local function preview_humanize(notes, min_p, max_p, role, minv, maxv, curve, strength)
  local total_range = max_p - min_p
  if total_range <= 0 then total_range = 1 end
  local result = {}
  for _, n in ipairs(notes) do
    if is_note_in_role(n.pitch, role) then
      local t     = (n.ppq - min_p) / total_range
      local c_idx = clamp(math.floor(t * (#curve - 1)) + 1, 1, #curve)
      local vel   = lerp(n.orig_vel, lerp(minv, maxv, curve[c_idx]), strength)
      result[#result + 1] = {ppq = n.ppq, vel = clamp(round(vel), 1, 127)}
    end
  end
  return result
end

-- ================= TIMING ENGINE =================

local function apply_timing(take, notes, timing_settings, timing_var_curve)
  local bpm          = reaper.Master_GetTempo()
  local ms_per_beat  = 60000.0 / bpm
  local ppq_per_beat = reaper.MIDI_GetPPQPosFromProjQN(take, 1) -
                       reaper.MIDI_GetPPQPosFromProjQN(take, 0)
  local ppq_per_ms   = ppq_per_beat / ms_per_beat
  local pitch_role   = build_pitch_role_lookup()

  -- Compute min/max PPQ from notes for normalized phrase position
  local min_p, max_p = math.huge, 0
  for _, n in ipairs(notes) do
    if n.ppq < min_p then min_p = n.ppq end
    if n.ppq > max_p then max_p = n.ppq end
  end
  local total_range = max_p - min_p
  if total_range <= 0 then total_range = 1 end

  for _, n in ipairs(notes) do
    local role = pitch_role[n.pitch]
    if role then
      local ts = timing_settings[role]
      if ts and ts.enabled then
        -- Compute curve-scaled variance
        local curve_mult = 1.0
        if timing_var_curve and timing_var_curve[role] then
          local tvc = timing_var_curve[role]
          local t_pos   = (n.ppq - min_p) / total_range
          local c_idx = clamp(math.floor(t_pos * (#tvc - 1)) + 1, 1, #tvc)
          curve_mult = tvc[c_idx] * 2.0
        end
        local scaled_variance = ts.variance_ms * curve_mult

        local frac    = n.qn - math.floor(n.qn)
        local on_beat = (frac < 0.1 or frac > 0.9)
        local eff_var = scaled_variance * (on_beat and 0.3 or 1.0)
        local offset_ppq = biased_rand_timing(ts.lean_ms, eff_var) * ppq_per_ms
        local new_start  = math.max(0, n.ppq + offset_ppq)
        n.new_ppq    = new_start
        n.new_endppq = new_start + (n.endppq - n.ppq)
      end
    end
  end
end

local function get_tempo_info(take)
  local bpm          = reaper.Master_GetTempo()
  local ms_per_beat  = 60000.0 / bpm
  local ppq_per_beat = reaper.MIDI_GetPPQPosFromProjQN(take, 1) -
                       reaper.MIDI_GetPPQPosFromProjQN(take, 0)
  return bpm, ppq_per_beat / ms_per_beat
end

-- ================= MAIN GUI =================

local function run()
  local me = reaper.MIDIEditor_GetActive()
  if not me then return end
  local take = reaper.MIDIEditor_GetTake(me)
  if not take then return end

  local ctx = reaper.ImGui_CreateContext("DeHumanizer Pro v5.4")

  local saved    = load_settings()
  local role_idx = #ROLES - 1
  local minv, maxv = saved.minv, saved.maxv
  local drift, strength, brush = saved.drift, saved.strength, 5

  local curve = {}
  if saved.curve then
    for i = 1, CONFIG.curve_points do curve[i] = saved.curve[i] end
  else
    for i = 1, CONFIG.curve_points do curve[i] = 0.5 end
  end

  local timing = {}
  for _, role in ipairs(TIMING_ROLE_KEYS) do
    timing[role] = {
      lean_ms     = saved.timing[role].lean_ms,
      variance_ms = saved.timing[role].variance_ms,
      enabled     = saved.timing[role].enabled,
    }
  end

  -- Initialize timing variance curves from loaded settings
  local timing_var_curve = {}
  for _, role in ipairs(TIMING_ROLE_KEYS) do
    timing_var_curve[role] = {}
    if saved.timing_var_curve and saved.timing_var_curve[role] then
      for i = 1, CONFIG.curve_points do
        timing_var_curve[role][i] = saved.timing_var_curve[role][i]
      end
    else
      for i = 1, CONFIG.curve_points do
        timing_var_curve[role][i] = 0.5
      end
    end
  end

  -- Velocity canvas mouse tracking (existing)
  local prev_paint_idx = nil
  local prev_paint_val = nil
  local prev_erase_idx = nil

  -- Timing variance curve canvas mouse tracking (per-role tables)
  local prev_tvc_paint_idx = {}
  local prev_tvc_paint_val = {}
  local prev_tvc_erase_idx = {}
  for _, role in ipairs(TIMING_ROLE_KEYS) do
    prev_tvc_paint_idx[role] = nil
    prev_tvc_paint_val[role] = nil
    prev_tvc_erase_idx[role] = nil
  end

  -- Error tracking: log the first error to console, don't spam
  local last_error = nil

  local function loop()
    -- Re-validate take every frame BEFORE calling ImGui_Begin.
    local active_me = reaper.MIDIEditor_GetActive()
    if active_me then
      local candidate = reaper.MIDIEditor_GetTake(active_me)
      if candidate and reaper.ValidatePtr(candidate, "MediaItem_Take*") then
        take = candidate
      end
    end
    local take_valid = take and reaper.ValidatePtr(take, "MediaItem_Take*")

    -- Precompute anything that requires the take BEFORE entering ImGui.
    local notes, min_p, max_p, active_role, live_bpm, live_ppq_per_ms
    if take_valid then
      notes, min_p, max_p = get_notes(take)
      active_role = ROLES[role_idx + 1]
      live_bpm, live_ppq_per_ms = get_tempo_info(take)
    end

    reaper.ImGui_SetNextWindowSize(ctx, 470, 640, reaper.ImGui_Cond_FirstUseEver())

    -- Begin/End are always a matched pair. No early returns, no exceptions.
    local vis, open = reaper.ImGui_Begin(ctx, "DeHumanizer Pro v5.4 - Dead Pixel Design", true)

    -- pcall-wrap the entire GUI body so that ImGui_End is ALWAYS reached,
    -- even if a widget call or REAPER API throws inside the frame.
    -- ReaImGui v0.9+ will crash with "Calling End() too many times" if
    -- an unhandled error skips End on one frame and then End runs on the next.
    local body_ok, body_err = pcall(function()

      if vis then
        if not take_valid then
          -- Take is gone — show notice only, no MIDI calls.
          reaper.ImGui_Spacing(ctx)
          reaper.ImGui_TextDisabled(ctx, "No active MIDI editor or take.")
          reaper.ImGui_TextDisabled(ctx, "Open a MIDI item to continue.")
        else
          -- ===== VELOCITY SHAPING SECTION =====

          -- Section header for Velocity Engine
          reaper.ImGui_Spacing(ctx)
          reaper.ImGui_Text(ctx, "========== VELOCITY SHAPING ==========")
          reaper.ImGui_Spacing(ctx)

          local ch, rv = reaper.ImGui_Combo(ctx, "Target Role", role_idx, table.concat(ROLES, "\0") .. "\0")
          if ch then role_idx = rv end

          if active_role ~= "All" then
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Learn from Selection") then
              local learn_take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
              if learn_take then
                local _, note_count = reaper.MIDI_CountEvts(learn_take)
                local learned_any = false
                for i = 0, note_count - 1 do
                  local _, sel, _, _, _, _, pitch, _ = reaper.MIDI_GetNote(learn_take, i)
                  if sel then
                    local already_mapped = false
                    for _, existing_pitch in ipairs(ROLE_MAP[active_role]) do
                      if existing_pitch == pitch then already_mapped = true; break end
                    end
                    if not already_mapped then
                      table.insert(ROLE_MAP[active_role], pitch)
                      learned_any = true
                    end
                  end
                end
                if learned_any then
                  reaper.ShowConsoleMsg("DeHumanizer: Learned new pitch(es) for " .. active_role .. "\n")
                else
                  reaper.ShowConsoleMsg("DeHumanizer: No new pitches to learn (already mapped or none selected)\n")
                end
              end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
              reaper.ImGui_SetTooltip(ctx, "Select a note in the MIDI editor, then click to add its pitch to " .. active_role)
            end
          end

          reaper.ImGui_Separator(ctx)
          _, minv     = reaper.ImGui_SliderInt(ctx, "Min Velocity",    minv,     1, 127)
          _, maxv     = reaper.ImGui_SliderInt(ctx, "Max Velocity",    maxv,     1, 127)
          _, drift    = reaper.ImGui_SliderInt(ctx, "Drift Tension",   drift,    0, 30)
          _, strength = reaper.ImGui_SliderDouble(ctx, "Apply Strength", strength, 0, 1)

          -- Axis context hint for the velocity curve canvas
          reaper.ImGui_TextDisabled(ctx, "Draw velocity shape: bottom = Min Vel, top = Max Vel")

          local w, h = reaper.ImGui_GetContentRegionAvail(ctx); h = 200
          local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
          reaper.ImGui_InvisibleButton(ctx, "canvas", w, h)
          local dl = reaper.ImGui_GetWindowDrawList(ctx)

          local tr = max_p - min_p
          if tr > 0 then
            local lq = -1
            for _, n in ipairs(notes) do
              local nx = x + ((n.ppq - min_p) / tr) * w
              local ny = y + (1 - (n.orig_vel / 127)) * h
              if lq ~= -1 and (n.qn - lq) > CONFIG.phrase_gap_qn then
                reaper.ImGui_DrawList_AddLine(dl, nx, y, nx, y + h, 0x44FF0000, 1)
              end
              local col = is_note_in_role(n.pitch, active_role) and 0xAA00FFFF or 0x22FFFFFF
              reaper.ImGui_DrawList_AddCircleFilled(dl, nx, ny, 2.0, col)
              lq = n.qn
            end
            local preview = preview_humanize(notes, min_p, max_p, active_role, minv, maxv, curve, strength)
            for _, p in ipairs(preview) do
              local px = x + ((p.ppq - min_p) / tr) * w
              local py = y + (1 - (p.vel / 127)) * h
              reaper.ImGui_DrawList_AddCircleFilled(dl, px, py, 3.0, 0x88FF8800)
            end
          end

          local mx, my     = reaper.ImGui_GetMousePos(ctx)
          local is_hovered = reaper.ImGui_IsItemHovered(ctx)
          local left_down  = reaper.ImGui_IsMouseDown(ctx, 0)
          local right_down = reaper.ImGui_IsMouseDown(ctx, 1)

          if is_hovered and left_down then
            local nx  = clamp((mx - x) / w, 0, 1)
            local ny  = clamp(1 - ((my - y) / h), 0, 1)
            local idx = math.floor(nx * (CONFIG.curve_points - 1)) + 1
            paint_curve_interpolated(curve, prev_paint_idx, prev_paint_val, idx, ny, brush)
            prev_paint_idx = idx
            prev_paint_val = ny
          else
            prev_paint_idx = nil
            prev_paint_val = nil
          end

          if is_hovered and right_down then
            local nx  = clamp((mx - x) / w, 0, 1)
            local idx = math.floor(nx * (CONFIG.curve_points - 1)) + 1
            paint_curve_interpolated(curve, prev_erase_idx, 0.5, idx, 0.5, brush)
            prev_erase_idx = idx
          else
            prev_erase_idx = nil
          end

          for i = 1, #curve - 1 do
            reaper.ImGui_DrawList_AddLine(
              dl,
              x + (i - 1) / (#curve - 1) * w, y + (1 - curve[i])     * h,
              x + (i)     / (#curve - 1) * w, y + (1 - curve[i + 1]) * h,
              0xFF00FFFF, 2.5
            )
          end

          if reaper.ImGui_Button(ctx, "Reset Curve") then
            for i = 1, #curve do curve[i] = 0.5 end
          end

          reaper.ImGui_Separator(ctx)

          local leg_x, leg_y = reaper.ImGui_GetCursorScreenPos(ctx)
          reaper.ImGui_DrawList_AddCircleFilled(dl, leg_x  + 6, leg_y  + 7, 4.0, 0xAA00FFFF)
          reaper.ImGui_Dummy(ctx, 16, 0)
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, "Original")
          reaper.ImGui_SameLine(ctx, 0, 16)
          local leg2_x, leg2_y = reaper.ImGui_GetCursorScreenPos(ctx)
          reaper.ImGui_DrawList_AddCircleFilled(dl, leg2_x + 6, leg2_y + 7, 4.0, 0x88FF8800)
          reaper.ImGui_Dummy(ctx, 16, 0)
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_Text(ctx, "Preview")
          reaper.ImGui_SameLine(ctx, 0, 16)
          reaper.ImGui_TextDisabled(ctx, "LMB: draw | RMB: erase")

          reaper.ImGui_Separator(ctx)

          if reaper.ImGui_Button(ctx, "Save Settings", 120) then
            save_settings({minv=minv, maxv=maxv, drift=drift, strength=strength, curve=curve, timing=timing, timing_var_curve=timing_var_curve})
          end

          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "APPLY VELOCITY", -1, 40) then
            reaper.Undo_BeginBlock()
            humanize(notes, min_p, max_p, active_role, minv, maxv, drift, curve, strength)
            reaper.MIDI_DisableSort(take)
            for _, n in ipairs(notes) do
              if n.new_vel then
                reaper.MIDI_SetNote(take, n.idx, nil, nil, nil, nil, nil, nil, n.new_vel, false)
              end
            end
            reaper.MIDI_Sort(take)
            reaper.Undo_EndBlock("DeHumanizer Pro: Velocity", -1)
          end

          -- ===== TIMING ENGINE SECTION =====

          reaper.ImGui_Separator(ctx)

          -- Section header for Timing Engine
          reaper.ImGui_Spacing(ctx)
          reaper.ImGui_Text(ctx, "========== TIMING ENGINE ==========")
          reaper.ImGui_Spacing(ctx)

          local timing_open = reaper.ImGui_CollapsingHeader(ctx, "Timing Engine", reaper.ImGui_TreeNodeFlags_DefaultOpen())

          if timing_open then
            reaper.ImGui_TextDisabled(ctx, "Lean < 0 = drag (behind beat)    Lean > 0 = rush (ahead of beat)")
            reaper.ImGui_TextDisabled(ctx, "Beats 1/2/3/4 always use 30%% of scatter (stay grounded)")
            reaper.ImGui_Spacing(ctx)

            for _, role in ipairs(TIMING_ROLE_KEYS) do
              local t = timing[role]

              local chk_changed, chk_val = reaper.ImGui_Checkbox(ctx, role, t.enabled)
              if chk_changed then t.enabled = chk_val end

              if t.enabled then
                reaper.ImGui_SameLine(ctx, 0, 12)

                reaper.ImGui_SetNextItemWidth(ctx, 160)
                local lean_ch, lean_val = reaper.ImGui_SliderDouble(
                  ctx, "Lean##" .. role, t.lean_ms,
                  -CONFIG.max_lean_ms, CONFIG.max_lean_ms, "%.1f ms"
                )
                if lean_ch then t.lean_ms = lean_val end

                reaper.ImGui_SameLine(ctx, 0, 12)

                reaper.ImGui_SetNextItemWidth(ctx, 120)
                local var_ch, var_val = reaper.ImGui_SliderDouble(
                  ctx, "Scatter##" .. role, t.variance_ms,
                  0, CONFIG.max_variance_ms, "%.1f ms"
                )
                if var_ch then t.variance_ms = var_val end

                reaper.ImGui_SameLine(ctx, 0, 8)
                reaper.ImGui_TextDisabled(ctx, "(?)")

                if reaper.ImGui_IsItemHovered(ctx) then
                  local lean_ppq   = t.lean_ms * live_ppq_per_ms
                  local direction
                  if math.abs(t.lean_ms) < 0.05 then
                    direction = "centered on the grid"
                  elseif t.lean_ms > 0 then
                    direction = "rushing AHEAD of the beat"
                  else
                    direction = "dragging BEHIND the beat"
                  end
                  reaper.ImGui_BeginTooltip(ctx)
                  reaper.ImGui_Text(ctx, role .. " Timing Preview")
                  reaper.ImGui_Separator(ctx)
                  reaper.ImGui_Text(ctx, string.format("Tempo:          %.1f BPM", live_bpm))
                  reaper.ImGui_Text(ctx, string.format("Lean center:    %.1f ms  (%.2f PPQ)", t.lean_ms, lean_ppq))
                  reaper.ImGui_Text(ctx, string.format("Direction:      %s", direction))
                  reaper.ImGui_Separator(ctx)
                  reaper.ImGui_Text(ctx, string.format("Scatter (off-beat):      +/- %.1f ms", t.variance_ms))
                  reaper.ImGui_Text(ctx, string.format("Scatter (beats 1-4):     +/- %.1f ms  [tightened]", t.variance_ms * 0.3))
                  reaper.ImGui_Separator(ctx)
                  reaper.ImGui_TextDisabled(ctx, "Most hits land near the lean center.")
                  reaper.ImGui_TextDisabled(ctx, "Bell curve tapers toward the edges.")
                  reaper.ImGui_EndTooltip(ctx)
                end

                -- ===== TIMING VARIANCE CURVE CANVAS (per role) =====

                reaper.ImGui_Spacing(ctx)

                -- Axis labels to the left of the canvas
                reaper.ImGui_TextDisabled(ctx, "  Scatter Curve: 0x (bottom) — 1x (center) — 2x (top)")

                local tvc_w, _ = reaper.ImGui_GetContentRegionAvail(ctx)
                local tvc_h = 80
                local tvc_x, tvc_y = reaper.ImGui_GetCursorScreenPos(ctx)
                reaper.ImGui_InvisibleButton(ctx, "##tvcurvas_" .. role, tvc_w, tvc_h)
                local tvc_dl = reaper.ImGui_GetWindowDrawList(ctx)

                -- Draw background guide lines: center (1x) as dim line
                reaper.ImGui_DrawList_AddLine(
                  tvc_dl,
                  tvc_x, tvc_y + tvc_h * 0.5,
                  tvc_x + tvc_w, tvc_y + tvc_h * 0.5,
                  0x33FFFFFF, 1
                )

                -- Mouse interaction for this role's timing variance curve
                local tvc_mx, tvc_my         = reaper.ImGui_GetMousePos(ctx)
                local tvc_is_hovered         = reaper.ImGui_IsItemHovered(ctx)
                local tvc_left_down          = reaper.ImGui_IsMouseDown(ctx, 0)
                local tvc_right_down         = reaper.ImGui_IsMouseDown(ctx, 1)
                local tvc = timing_var_curve[role]

                if tvc_is_hovered and tvc_left_down then
                  local norm_x = clamp((tvc_mx - tvc_x) / tvc_w, 0, 1)
                  local norm_y = clamp(1 - ((tvc_my - tvc_y) / tvc_h), 0, 1)
                  local tidx   = math.floor(norm_x * (CONFIG.curve_points - 1)) + 1
                  paint_curve_interpolated(tvc, prev_tvc_paint_idx[role], prev_tvc_paint_val[role], tidx, norm_y, brush)
                  prev_tvc_paint_idx[role] = tidx
                  prev_tvc_paint_val[role] = norm_y
                else
                  prev_tvc_paint_idx[role] = nil
                  prev_tvc_paint_val[role] = nil
                end

                if tvc_is_hovered and tvc_right_down then
                  local norm_x = clamp((tvc_mx - tvc_x) / tvc_w, 0, 1)
                  local tidx   = math.floor(norm_x * (CONFIG.curve_points - 1)) + 1
                  paint_curve_interpolated(tvc, prev_tvc_erase_idx[role], 0.5, tidx, 0.5, brush)
                  prev_tvc_erase_idx[role] = tidx
                else
                  prev_tvc_erase_idx[role] = nil
                end

                -- Draw the timing variance curve line (cyan, same as velocity curve)
                for ci = 1, #tvc - 1 do
                  reaper.ImGui_DrawList_AddLine(
                    tvc_dl,
                    tvc_x + (ci - 1) / (#tvc - 1) * tvc_w, tvc_y + (1 - tvc[ci])     * tvc_h,
                    tvc_x + (ci)     / (#tvc - 1) * tvc_w, tvc_y + (1 - tvc[ci + 1]) * tvc_h,
                    0xFF00FFFF, 2.0
                  )
                end

                -- Reset button for this role's timing variance curve
                if reaper.ImGui_Button(ctx, "Reset##tvc_" .. role) then
                  for ri = 1, CONFIG.curve_points do
                    timing_var_curve[role][ri] = 0.5
                  end
                end

                reaper.ImGui_Spacing(ctx)

              end -- t.enabled
            end -- role loop

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)

            if reaper.ImGui_Button(ctx, "APPLY TIMING", -1, 36) then
              reaper.Undo_BeginBlock()
              local fresh_notes, _, _ = get_notes(take)
              apply_timing(take, fresh_notes, timing, timing_var_curve)
              reaper.MIDI_DisableSort(take)
              for _, n in ipairs(fresh_notes) do
                if n.new_ppq then
                  reaper.MIDI_SetNote(
                    take, n.idx,
                    nil, nil,
                    n.new_ppq, n.new_endppq,
                    nil, nil, nil,
                    false
                  )
                end
              end
              reaper.MIDI_Sort(take)
              reaper.Undo_EndBlock("DeHumanizer Pro: Timing", -1)
            end

          end -- timing_open

        end -- take_valid
      end -- vis

    end) -- pcall

    -- Log errors to console (once per unique error, not every frame)
    if not body_ok then
      if body_err ~= last_error then
        reaper.ShowConsoleMsg("DeHumanizer Pro: " .. tostring(body_err) .. "\n")
        last_error = body_err
      end
    else
      last_error = nil
    end

    -- ALWAYS call End -- guaranteed, regardless of what happened above.
    local end_ok, end_err = pcall(reaper.ImGui_End, ctx)
    if not end_ok then
      reaper.ShowConsoleMsg("DeHumanizer Pro: End() error: " .. tostring(end_err) .. "\n")
    end
    if open then reaper.defer(loop) end
  end

  loop()
end

run()
