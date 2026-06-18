local function copy(from, to)
	print(string.format("%s -> %s", from, to))
	os.execute(string.format("cp -a %q %q", from, to))
end

copy(RUSTG_PATH, "librust_g.so")
copy(AUXTOOLS_PATH, "libauxtools.so")
