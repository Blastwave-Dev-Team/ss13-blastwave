#!/usr/bin/env lua

function panic(err)
	io.stderr:write("error: ",err,"\n")
	os.exit(1)
end

if not os.execute "[[ -e tgstation.dme ]]" then
	panic("Script must be run from repo root.")
end

os.execute("mkdir -p buildtmp")

local scripts = {}
for line in io.popen("ls tools/linux_build_tools", "r"):lines() do
	table.insert(scripts, line)
end

table.sort(scripts)

for i=1, #scripts do
	print("\27[1m:: "..scripts[i].."\27[0m")
	dofile("tools/linux_build_tools/"..scripts[i])
end

print [[
      |\/|    ____
   .__.. \   /\  /
    \_   /__/  \/
    _/  __   __/      
🥒 /___/____/
]]
print("Build complete!")
