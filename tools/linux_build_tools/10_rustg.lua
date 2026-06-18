if not os.execute "[[ -e buildtmp/rust-g ]]" then
    os.execute("git clone "..RUSTG_URL.." buildtmp/rust-g")
else
    os.execute("cd buildtmp/rust-g; git pull")
end

os.execute("cd buildtmp/rust-g; PKG_CONFIG_ALLOW_CROSS=1 cargo build --release --target i686-unknown-linux-gnu")
RUSTG_PATH = "buildtmp/rust-g/target/i686-unknown-linux-gnu/release/librust_g.so"
