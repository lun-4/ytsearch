#!/usr/bin/env lua

local DBFILE = arg[1]
if DBFILE == nil then
  print('missing dbfile arg')
  return
end
local OUTFILE = './new_yt_search.db'

local tables = {
"channel_slots",
"schema_migrations",
"sponsorblock_segments",
"channel_slots_v3",
"search_slots",
"subtitles",
"chapters",
"search_slots_v3",
-- "thumbnails",
"links",
"slots",
"thumbnails_v2",
"playlist_slots",
"slots_v2",
"playlist_slots_v3",
"slots_v3",
}

os.execute('mkdir -p dump')

local full_sql_commands = ''

full_sql_commands = full_sql_commands .. (string.format('.out dump/00_schema.sql\n'))
full_sql_commands = full_sql_commands .. (string.format('.schema\n'))
for _, table in ipairs(tables) do
  full_sql_commands = full_sql_commands .. (string.format('.mode insert %s\n', table))
  full_sql_commands = full_sql_commands .. (string.format('.out dump/%s.sql\n', table))
  full_sql_commands = full_sql_commands .. (string.format('select * from %s;\n', table))
end


local tmpsql, err = io.open(".tmp.sql", "w")
if tmpsql == nil then
  print('failed to write tmpsql file ' .. tostring(err))
  return
end
tmpsql:write(full_sql_commands)
tmpsql:close()

-- Lua implementation of PHP scandir function
local function scandir(directory)
    local i, t, popen = 1, {}, io.popen
    local pfile = popen('ls --sort version -a "'..directory..'"')
    if pfile == nil then
      print('failed to run ls')
      return nil
    end
    for filename in pfile:lines() do
        local is_path = true
        if filename == '.' or filename == '..' then
          is_path = false
        end

        if is_path then
          i = i + 1
          t[i] = filename
        end
    end
    pfile:close()
    return t
end

--[[

local sqlpfile = io.popen("sqlite3 -init .tmp.sql ./yt_search_dev.db", "w")
if sqlpfile == nil then
  print('sqlite failed')
  return
end
sqlpfile:write(".q")
sqlpfile:close()
print('dump ok')
]]

print('do .q')
os.execute("sqlite3 -init .tmp.sql "..DBFILE)
print('dump ok')


local dump_paths = scandir("dump")
if dump_paths == nil then
  print('failed to list files in dump folder')
  return
end

local function writeall(s)
  io.write(s)
  io.flush()
end

for _, dump_path in pairs(dump_paths) do
  writeall('processing ' .. dump_path)
  local pfile = io.popen("sqlite3 "..OUTFILE, "w")
  if pfile == nil then
    print('failed to open sqlite3 for writing')
    return
  end

  local dumpfile = io.open('dump/'..dump_path, 'r')
  if dumpfile == nil then
    print('failed to open '..dump_path)
    return
  end

  writeall('writing...')
  local chunks = 0
  pfile:write("BEGIN TRANSACTION;\n")
  while true do
    local chunk = dumpfile:read(8192)
    if chunk then
      pfile:write(chunk)
      chunks = chunks + 1
    else
      break
    end
  end
  writeall(string.format('%d chunks...', chunks))
  writeall('commit...')
  pfile:write("COMMIT;\n")
  writeall('closing...')
  pfile:close()
  writeall('\n')
end

