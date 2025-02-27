
# to enable:
# source /root/RPi-tools/rorw/rorw.bashrc

# Fonction pour connaitre le mode en cours
function update_fs_mode {
  fs_mode=$(mount | sed -n -e "s/^.* on \/ .*(\(r[w|o]\).*/\1/p")
  if [ "$fs_mode" == "ro" ] ;then
    fs_mode_color=32m
  else
    fs_mode_color=31m
  fi
}
update_fs_mode

# alias ro/rw pour passer de l'un    l'autre
# alias ro='mount -o remount,ro / ; mount -o remount,ro /boot ; fs_mode=$(mount | sed -n -e "s/^.* on \/ .*(\(r[w|o]\).*/\1/p"); fs_mode_color=32m'
# alias rw='mount -o remount,rw / ; mount -o remount,rw /boot ; fs_mode=$(mount | sed -n -e "s/^.* on \/ .*(\(r[w|o]\).*/\1/p"); fs_mode_color=31m' #31m

alias ro='/usr/local/bin/ro; prompt_command'
alias rw='/usr/local/bin/rw; prompt_command'

# Modification du prompt pour afficher le mode en cours
export PS1='\[\033[01;$fs_mode_color\]\u@\h${fs_mode:+($fs_mode)}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '


# Update the prompt
function prompt_command {
  update_fs_mode
  PS1='\[\033[01;$fs_mode_color\]\u@\h${fs_mode:+($fs_mode)}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
}
PROMPT_COMMAND=prompt_command