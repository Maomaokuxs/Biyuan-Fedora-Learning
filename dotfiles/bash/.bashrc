# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

# shortkey
alias ff='fastfetch'
alias up='sudo dnf upgrade'

# starship
eval "$(starship init bash)"

# 自动同步配置文件脚本
# Stow 版 dpush 别名
alias dpush='cd ~/Documents/github/Biyuan-Fedora-Learning && git add . && git commit -m "Update" && git push origin main'

# Biyuan Manager Path
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"

# Biyuan CLI Tools
export PATH="$HOME/.local/bin:$PATH"
