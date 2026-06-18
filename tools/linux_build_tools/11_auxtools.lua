if not os.execute "[[ -e buildtmp/auxtools ]]" then
    os.execute("git clone https://github.com/willox/auxtools buildtmp/auxtools")
else
    os.execute("cd buildtmp/auxtools; git pull")
end

os.execute("cd buildtmp/auxtools; PKG_CONFIG_ALLOW_CROSS=1 cargo build --release --target i686-unknown-linux-gnu")
--RUSTG_PATH = "buildtmp/auxtools/target/i686-unknown-linux-gnu/release/librust_g.so"
AUXTOOLS_PATH = "buildtmp/auxtools/target/i686-unknown-linux-gnu/release/libauxtools.so"
