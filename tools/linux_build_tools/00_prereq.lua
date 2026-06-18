local has_curl = os.execute("curl --version > /dev/null")
local has_wget = os.execute("wget --version > /dev/null")

if not has_curl or not has_wget then
    panic("Neither curl nor wget are installed. Cannot continue!")
end

if has_curl then
    print("Using cURL for downloads.")
    function download(file, dst)
        return os.execute(string.format("curl %q -o %q", file, dst))
    end
else
    print("Using wget for downloads.")
    function download(file, dst)
        return os.execute(string.format("wget %q -o %q", file, dst))
    end
end

if not os.execute("git --version > /dev/null") then
    panic("Git not installed! (how did we get here?)")
end
