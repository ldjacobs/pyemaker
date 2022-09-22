#!/bin/bash

get_versions() {
  # Function to get an array of all installed versions that pyenv knows about.
  # Puts results in global ${pyenv_versions}.
  readarray -t pyenv_versions < <(pyenv versions | sed 's/\*//g' | sed 's/^\w+//g' | grep -v system)
}

get_versions_without_set_by() {
  # Function to get an array of all installed versions that pyenv knows about.
  # Puts results in global ${pyenv_versions}.
  readarray -t pyenv_versions < <(pyenv versions | sed 's/^\*//g' | sed 's/^\w+//g' | sed 's/ (set by .*)//' | grep -v system)
}

show_versions_get_file_line() {
  # Function to show the current list of versions; also gets the "set by" line number.
  # Line number gets put in global ${var_file_line}.
  ver_file_line=-1
  look_for='set by'
  echo && echo "Currently-installed pyenv versions:"
  for i in ${!pyenv_versions[@]}; do
    echo ${pyenv_versions[$i]}
    if [[ "${pyenv_versions[$i]}" == *"$look_for"* ]]; then
      ver_file_line=$i
    fi
  done
}

show_versions_get_list_dict() {
  # Function to show the current list of versions; also gets a dictionary of envs.
  # Env list gets put in global ${envs}, dictionaries entries in ${env_dict}.
  envs=()
  env_dict=()
  echo && echo "Currently-installed pyenv versions:"
  for i in ${!pyenv_versions[@]}; do
    curval=$(echo ${pyenv_versions[$i]} | sed 's/^\w+//g')
    echo ${curval}
    if [[ "${curval}" =~ "/envs/" ]]; then
      key=$(echo ${curval} | cut -d/ -f3 | sed 's/^\w+//g')
      val=$(echo ${curval} | cut -d/ -f1 | sed 's/^\w+//g')
      env_dict[$key]=$val
      #declare -p env_dict
    else
      if ! [[ -n ${env_dict[${curval}]} ]]; then
        envs+=(${curval})
      fi
      #declare -p envs
    fi
  done
}

read_config_file() {
  # Function to read the user's ~/.pyemaker file, or ./sample.pyemaker otherwise.
  # Config dictionary gets put in global ${config}.
  config_file=''
  cfg_envs=()
  config=()
  if [ -f "~/.pyemaker" ]; then
    config_file="~/.pyemaker"
  elif [ -f "./sample.pyemaker" ]; then
    config_file="./sample.pyemaker"
  fi
  # FIXME -- Make this work!
  echo && echo "Reading config file ${config_file}"
  mapfile -t cfg_envs < <(jq -r 'keys[]' ${config_file})
  #declare -p cfg_envs
  for env in ${cfg_envs[@]}; do
    for ver in $(jq -r ".\"${env}\"[]" ${config_file}); do
      config[${ver}]=${env}
    done
  done
  #declare -p config
}

function arraydiff() {
  # From https://fabianlee.org/2020/09/06/bash-difference-between-two-arrays/
  awk 'BEGIN{RS=ORS=" "}
       {NR==FNR?a[$0]++:a[$0]--}
       END{for(k in a)if(a[k])print k}' <(echo -n "${!1}") <(echo -n "${!2}")
}

get_versions
show_versions_get_file_line

# If there is a "set by" file currently in effect, as the user if they want it gone.
if [[ $ver_file_line -gt 0 ]]; then
  ver_file=$(echo ${pyenv_versions[$ver_file_line]} | cut -d' ' -f4 | sed 's/)//')
  echo && read -n 1 -p "Remove ${ver_file} file (y/n)? " answer
  case ${answer:0:1} in
    y|Y )
        rm ${ver_file}
        echo && echo "File ${ver_file} removed."
    ;;
    * )
        echo && echo "File ${ver_file} remains."
    ;;
  esac
fi

# Declare an array and a dictionary to hold the existing env data.
envs=()
declare -A env_dict
# Declare an array and a dictionary to hold the config data.
cfg_envs=()
declare -A config

get_versions_without_set_by
show_versions_get_list_dict
read_config_file

# FIXME -- Get comparisons and reporting working, then add the ability to do things.
env_diff=($(arraydiff envs[@] cfg_envs[@]))
#declare -p env_diff
if [[ ${#env_diff[@]} -eq 0 ]]; then
  echo "Env lists match."
else
  echo "Env lists DO NOT match."
fi
