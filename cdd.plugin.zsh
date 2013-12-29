# you need to run below before source this script:
#
#    autoload -U compinit compinit
#

source ${0:r:r}

zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}Completing %B%d%b%f'

chpwd_functions+=_cdd_chpwd
