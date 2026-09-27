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
end
