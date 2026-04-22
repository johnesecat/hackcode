{ pkgs }: {
  deps = [
    # Build tools for compiling the hackcode Rust binary from source
    pkgs.rustup
    pkgs.pkg-config
    pkgs.openssl
    pkgs.openssl.dev

    # Runtime
    pkgs.git
    pkgs.curl

    # Python 3.12 for AirLLM
    pkgs.python312
    pkgs.python312Packages.pip

    # Security tools available to hackcode via bash
    pkgs.nmap
    pkgs.dnsutils
    pkgs.whois
    pkgs.netcat-gnu
  ];

  env = {
    OPENSSL_DIR         = "${pkgs.openssl.dev}";
    OPENSSL_LIB_DIR     = "${pkgs.openssl.out}/lib";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
    PKG_CONFIG_PATH     = "${pkgs.openssl.dev}/lib/pkgconfig";
    OLLAMA_HOST         = "http://127.0.0.1:11434";
  };
}
