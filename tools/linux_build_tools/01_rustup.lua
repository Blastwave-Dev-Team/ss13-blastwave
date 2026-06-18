if not os.execute("rustup --version > /dev/null") then
    download("https://sh.rustup.rs", "buildtmp/rustup-init.sh")
    os.execute("chmod +x buildtmp/rustup-init.sh")
    os.execute("cd buildtmp; ./rustup-init.sh")
    panic("Follow the above instructions and rerun the tool.")
else
    print("Rustup already installed, no need to reinstall.")
end
os.execute("rustup target add i686-unknown-linux-gnu")