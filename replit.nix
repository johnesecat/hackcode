}
  };
    CARGO_HOME          = "/home/runner/.cargo";
    RUSTUP_HOME         = "/home/runner/.rustup";
    # Rustup: store toolchains outside the workspace so they persist

    AIRLLM_INT8         = "1";
    # AirLLM: use int8 quantisation by default (halves peak RAM)

    OLLAMA_HOST         = "http://127.0.0.1:11434";
    # Tell hackcode's Rust binary where to find the Ollama-compatible server

    PKG_CONFIG_PATH     = "${pkgs.openssl.dev}/lib/pkgconfig";
    OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
    OPENSSL_LIB_DIR     = "${pkgs.openssl.out}/lib";
    OPENSSL_DIR         = "${pkgs.openssl.dev}";
    # OpenSSL — required by Rust crates openssl-sys and ring
  env = {
  # These are set in every shell session inside this Repl.
  # ── Environment variables ─────────────────────────────────────────────────

  ];
    pkgs.ncdu          # disk usage
    pkgs.htop          # process monitor
    pkgs.bat           # syntax-highlighted cat
    pkgs.tree          # directory listing
    pkgs.fd            # fast find
    pkgs.ripgrep       # rg — fast grep (used by hackcode's grep_search)
    pkgs.screen        # alternative multiplexer
    pkgs.tmux          # terminal multiplexer
    # ── Miscellaneous utilities ───────────────────────────────────────────

    pkgs.radare2       # reverse-engineering framework
    pkgs.ltrace        # library call tracer
    pkgs.strace        # syscall tracer
    pkgs.gdb           # GNU debugger
    pkgs.binutils      # strings, objdump, nm, readelf
    # ── Forensics / analysis ──────────────────────────────────────────────

    pkgs.base64        # base64 CLI
    pkgs.xxd           # hex dump
    pkgs.gnupg         # gpg
    pkgs.openssl       # openssl CLI (enc, genrsa, s_client …)
    # ── Crypto / encoding ─────────────────────────────────────────────────

    pkgs.metasploit    # msfconsole, msfvenom
    pkgs.exploitdb     # searchsploit
    # ── Exploitation ──────────────────────────────────────────────────────

    pkgs.hydra         # online brute-force
    pkgs.hashcat       # GPU password cracker
    pkgs.john          # John the Ripper
    # ── Password attacks ──────────────────────────────────────────────────

    pkgs.wpscan        # WordPress scanner
    pkgs.nuclei        # template-based scanner
    pkgs.sqlmap        # SQL injection
    pkgs.ffuf          # web fuzzer
    pkgs.gobuster      # directory/DNS brute-force
    pkgs.nikto         # web server scanner
    # ── Web application testing ───────────────────────────────────────────

    pkgs.wireshark-cli # tshark — CLI Wireshark
    pkgs.tcpdump       # packet capture
    pkgs.masscan       # fast port scanner
    pkgs.arp-scan      # ARP host discovery
    pkgs.inetutils     # ping, telnet, ftp, hostname
    pkgs.whois
    pkgs.dnsutils      # dig, nslookup, host
    pkgs.socat         # socat — versatile relay
    pkgs.netcat-gnu    # nc — reverse shells, port tests
    pkgs.nmap          # port scanner
    # ── Network / recon tools ─────────────────────────────────────────────

    pkgs.python3Packages.pip
    pkgs.python3       # Python 3 (latest in channel)
    # ── Python (for AirLLM) ───────────────────────────────────────────────

    pkgs.jq            # JSON parsing in shell scripts
    pkgs.less
    pkgs.lsof
    pkgs.procps        # ps, top, kill
    pkgs.which
    pkgs.file          # file(1) — MIME detection
    pkgs.unzip
    pkgs.gzip
    pkgs.gnutar
    pkgs.bash
    pkgs.wget
    pkgs.curl
    pkgs.git
    # ── Core Unix tools ───────────────────────────────────────────────────

    pkgs.openssl.dev   # headers for openssl-sys
    pkgs.openssl       # runtime OpenSSL
    pkgs.pkg-config    # needed by openssl-sys and ring crates
    pkgs.rustup        # manages Rust toolchains (cargo, rustc, rustfmt, clippy)
    # ── Rust build chain ──────────────────────────────────────────────────
  deps = [
{ pkgs }: {
