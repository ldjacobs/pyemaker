#!/bin/bash
# Requires Bash 4+, along with utilities sed, grep, cut, awk, and jq.

# Color definitions for use in output.
gray='[01;30m'
red='[01;31m'
green='[01;32m'
yellow='[01;33m'
blue='[01;34m'
magenta='[01;35m'
cyan='[01;36m'
white='[01;37m'
yellow_red='[01;41;33m'
none='[01;40;37m[00m'

# Declare an array and a dictionary to hold the existing env data.
ext_envs=()
declare -A env_dict
# Declare an array and a dictionary to hold the config data.
cfg_envs=()
declare -A cfg_dict
# Declare arrays for Python versions and named versions that need to be installed or removed.
py_to_install=()
py_to_remove=()
named_to_install=()
named_to_remove=()

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
  echo && echo "${white}Currently-installed pyenv versions:${yellow}"
  for i in ${!pyenv_versions[@]}; do
    echo ${pyenv_versions[$i]}
    if [[ "${pyenv_versions[$i]}" == *"$look_for"* ]]; then
      ver_file_line=$i
    fi
  done
  echo ${none}
}

show_versions_get_list_dict() {
  # Function to show the current list of versions; also gets a dictionary of envs.
  # Env list gets put in global ${ext_envs}, dictionaries entries in ${env_dict}.
  ext_envs=()
  env_dict=()
  echo && echo "${white}Currently-installed pyenv versions:${yellow}"
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
        ext_envs+=(${curval})
      fi
      #declare -p ext_envs
    fi
  done
  echo ${none}
}

get_versions_and_list_dict() {
  # Function to get the current list of versions and a dictionary of envs.
  # Env list gets put in global ${ext_envs}, dictionaries entries in ${env_dict}.
  ext_envs=()
  env_dict=()
  for i in ${!pyenv_versions[@]}; do
    curval=$(echo ${pyenv_versions[$i]} | sed 's/^\w+//g')
    if [[ "${curval}" =~ "/envs/" ]]; then
      key=$(echo ${curval} | cut -d/ -f3 | sed 's/^\w+//g')
      val=$(echo ${curval} | cut -d/ -f1 | sed 's/^\w+//g')
      env_dict[$key]=$val
      #declare -p env_dict
    else
      if ! [[ -n ${env_dict[${curval}]} ]]; then
        ext_envs+=(${curval})
      fi
      #declare -p ext_envs
    fi
  done
}

read_config_file() {
  # Function to read the user's ~/.pyemaker file, or ./pyemaker.json otherwise.
  # Config dictionary gets put in global ${cfg_dict}.
  config_file=''
  cfg_envs=()
  cfg_dict=()
  if [ -f "~/.pyemaker" ]; then
    config_file="~/.pyemaker"
  elif [ -f "./pyemaker.json" ]; then
    config_file="./pyemaker.json"
  else
    echo "${red}Config file not found!${none}"
    exit 1
  fi
  echo && echo "Reading config file ${config_file}"
  mapfile -t cfg_envs < <(jq -r 'keys[]' ${config_file})
  #declare -p cfg_envs
  for env in ${cfg_envs[@]}; do
    for ver in $(jq -r ".\"${env}\"[]" ${config_file}); do
      cfg_dict[${ver}]=${env}
    done
  done
  #declare -p cfg_dict
}

get_python_versions_installed_but_not_configured() {
  # Function to re-read current state and determine which, if any, Python versions need to go.
  get_versions_without_set_by
  get_versions_and_list_dict

  py_to_remove=()
  for ver in ${ext_envs[@]}; do
    if [[ ! " ${cfg_envs[*]} " =~ " ${ver} " ]]; then
      py_to_remove+=(${ver})
    fi
  done
}

get_python_versions_configured_but_not_installed() {
  # Function to re-read current state and determine which, if any, Python versions need to be installed.
  get_versions_without_set_by
  get_versions_and_list_dict

  py_to_install=()
  for ver in ${cfg_envs[@]}; do
    if [[ ! " ${ext_envs[*]} " =~ " ${ver} " ]]; then
      py_to_install+=(${ver})
    fi
  done
}

get_named_versions_to_remove() {
  # Function to re-read current state and determine which, if any, named versions need to be uninstalled.
  get_versions_without_set_by
  get_versions_and_list_dict

  #declare -p env_dict
  #declare -p cfg_dict
  named_to_remove=()
  for key in "${!env_dict[@]}"; do
    if [[ ${cfg_dict[$key]} != ${env_dict[$key]} ]]; then
      named_to_remove+=(${key})
    fi
  done
  #declare -p named_to_remove
}

get_named_versions_to_install() {
  # Function to re-read current state and determine which, if any, named versions need to be installed.
  get_versions_without_set_by
  get_versions_and_list_dict

  #declare -p env_dict
  #declare -p cfg_dict
  named_to_install=()
  for key in "${!cfg_dict[@]}"; do
    if [[ ${env_dict[$key]} != ${cfg_dict[$key]} ]]; then
      named_to_install+=(${key})
    fi
  done
  #declare -p named_to_install
}

# Actual execution starts here.
get_versions
show_versions_get_file_line

# If there is a "set by" file currently in effect, as the user if they want it gone.
if [[ $ver_file_line -gt 0 ]]; then
  ver_file=$(echo ${pyenv_versions[$ver_file_line]} | cut -d' ' -f4 | sed 's/)//')
  read -n 1 -p "${green}Remove ${ver_file} file (y/n)? ${none}" answer
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

# Only need to do this once.
read_config_file

something_to_do=1
while [[ ${something_to_do} == 1 ]]; do
  get_python_versions_configured_but_not_installed
  get_python_versions_installed_but_not_configured

  if [[ ${#py_to_install[@]} == 0 && ${#py_to_remove[@]} == 0 ]]; then
    echo "${green}Python version lists match.${none}"
    something_to_do=0
  else
    echo "${red}Python version lists DO NOT match.${none}"
    # When this is the case, offer to update things to match the intended config.
    for ver in ${py_to_install}; do
      read -n 1 -p "${green}Python ${ver} is configured but not installed -- install it now (y/n)? ${none}" answer
      case ${answer:0:1} in
        y|Y )
          echo && echo "${green}Installing Python ${ver} now.${none}"
          pyenv install ${ver}
        ;;
        * )
          echo && echo "${yellow}Python version ${ver} NOT installed.${none}"
        ;;
      esac
    done
    named_env_found=0
    for ver in ${py_to_remove}; do
      if [[ ! " ${cfg_envs[*]} " =~ " ${ver} " ]]; then
        echo "${yellow}Python ${ver} is installed but not configured!${none}"
        # If there are any named envs based on this version, uninstall them first.
        for key in "${!env_dict[@]}"; do
          if [[ ${env_dict[${key}]} == ${ver} ]]; then
            named_env_found=1
            read -n 1 -p "${yellow}Env ${key} is based on Python ${ver} -- uninstall it now (y/n)? ${none}" answer
            case ${answer:0:1} in
              y|Y )
                echo && echo "${green}Uninstalling ${key} now.${none}"
                pyenv uninstall ${key}
              ;;
              * )
                echo && echo "${yellow}Env ${key} NOT uninstalled.${none}"
              ;;
            esac
          fi
        done
        # If we get here, there are no named versions, so we can offer to uninstall the Python version.
        if [[ ${named_env_found} -eq 0 ]]; then
          read -n 1 -p "${yellow}Python ${ver} is installed but not configured -- uninstall it now (y/n)? ${none}" answer
          case ${answer:0:1} in
            y|Y )
              echo && echo "${green}Uninstalling Python ${ver} now.${none}"
              pyenv uninstall ${ver}
              break
            ;;
            * )
              echo && echo "${yellow}Python ${ver} NOT uninstalled.${none}"
            ;;
          esac
        fi
      fi
    done
  fi
done

something_to_do=1
while [[ ${something_to_do} == 1 ]]; do
  get_named_versions_to_install
  get_named_versions_to_remove

  if [[ ${#named_to_install[@]} == 0 && ${#named_to_remove[@]} == 0 ]]; then
    echo "${green}Named version lists match.${none}"
    something_to_do=0
  else
    echo "${red}Named version lists DO NOT match.${none}"
    # If there are any installed named versions that are not configured, offer to remove them.
    for key in "${named_to_remove[@]}"; do
      read -n 1 -p "${yellow}Version ${key} is installed but not configured -- uninstall it now (y/n)? ${none}" answer
      case ${answer:0:1} in
        y|Y )
          echo && echo "${green}Uninstalling version ${key} now.${none}"
          pyenv uninstall ${key}
        ;;
        * )
          echo && echo "${yellow}Version ${key} NOT uninstalled.${none}"
        ;;
      esac
    done
    # Find a missing named version, and offer to set it up.
    for key in "${named_to_install[@]}"; do
      read -n 1 -p "${yellow}Version ${key} is configured but not installed -- install it now (y/n)? ${none}" answer
      case ${answer:0:1} in
        y|Y )
          echo && echo "${green}Installing version ${key} now.${none}"
          pyenv virtualenv ${cfg_dict[$key]} ${key}
        ;;
        * )
          echo && echo "${yellow}Version ${key} NOT installed.${none}"
        ;;
      esac
    done
  fi
done
