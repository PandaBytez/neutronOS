# Pure Fish shell configuration for neutronOS
# No external prompt framework bloat - clean, responsive default fish prompt.

if status is-interactive
    # Auto-initialize Linuxbrew if present
    if test -d /home/linuxbrew/.linuxbrew
        eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    end

    # Handy defaults
    set -g fish_greeting ""

    # Ctrl+Left/Right word movement, like every other terminal
    bind \e\[1\;5D backward-kill-word
    bind \e\[1\;5C forward-kill-word

    # Container dev environments. This image is immutable, so language
    # toolchains live in distrobox containers rather than on the host.
    # The container is named after the current directory, so each project gets its
    # own toolchain without editing this file. These are functions, not aliases:
    # a fish alias body is expanded once at definition time, so $(basename $PWD)
    # in an alias would freeze on the shell's startup directory.
    function dinit
        distrobox create --name (basename $PWD) --image fedora:latest --yes
    end
    function dsh
        distrobox enter (basename $PWD)
    end
end
