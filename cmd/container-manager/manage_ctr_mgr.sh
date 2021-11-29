#!/bin/bash -e
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

DOCKER_BIN=docker
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
SCRIPT_NAME=${0##*/}
source "${SCRIPT_PATH}/../../.ci/lib.sh"
source /etc/os-release || source /usr/lib/os-release

force=false
ctr_manager=""
subcommand=""
runtime=""
tag=""

usage(){
	cat << EOF
This script helps you install the correct version of docker
to use with Clear Containers.
WARNING: Using this tool with -f flag, will overwrite any docker configuration that you may
have modified.
Usage: $SCRIPT_NAME [docker] [configure|info|install|remove] <options>
Options:
	-f                         : Force action. It will replace any installation
                                     or configuration that you may have.
	-h                         : Help, show this information.
	-r <runtime>               : Supported runtimes: runc and kata-runtime.
	-s <storage_driver>        : Supported storage driver: overlay2(default), devicemapper, etc.
	-t <tag>                   : Tags supported: latest. If you do not specify
                                     a tag, the script will use latest as default.
Example:
	./$SCRIPT_NAME docker install -t latest -f
EOF
}

die(){
	msg="$*"
	echo "$SCRIPT_NAME - ERROR: $msg" >&2
	exit 1
}

warning(){
	msg="$*"
	echo "$SCRIPT_NAME - WARNING: $msg" >&2
}

message(){
	msg="$*"
	echo "$SCRIPT_NAME - INFO: $msg" >&2
}

log_message(){
	message="$1"
	logger -s -t "$(basename $0)" "$message"
}

parse_subcommand_options(){
	while getopts ":fr:s:t:" opt; do
		case $opt in
			f)
				force=true
				;;
			r)
				runtime="${OPTARG}"
				;;
			s)
				storage_driver="${OPTARG}"
				;;
			t)
				tag="${OPTARG}"
				;;
			\?)
				echo "Invalid option: -${OPTARG}" >&2
				usage
				exit 1
		esac
	done
}

# This function handles the installation of the required docker version.
install_docker(){
	# Get system architecture
	arch=$(go env GOARCH)
	# Check if docker is present in the system
	if [ "$(info_docker)" ] && [ ${force} == false ]; then
		die "Docker is already installed. Please use -f flag to force new installation"
	elif [ "$(info_docker)" ] && [ ${force} == true ]; then
		remove_docker
	fi

	if [ "$arch" == "s390x" ]; then
		# download.docker.com does not build for s390x, need to install through other means
		install_docker_s390x
	elif [ "$arch" == "ppc64le" ]; then
		install_docker_ppc64le
	elif [ -z "$tag" ] || [ "$tag" == "latest" ] ; then
		# If no tag is recevied, install latest compatible version
		log_message "Installing docker"
		pkg_name="docker-ce"
		if [ "$ID" == "ubuntu" ]; then
			sudo -E apt-get -y install apt-transport-https ca-certificates software-properties-common apt-utils
			repo_url="https://download.docker.com/linux/ubuntu"
			curl -fsSL "${repo_url}/gpg" | sudo apt-key add -
			sudo -E add-apt-repository "deb [arch=${arch}] ${repo_url} $(lsb_release -cs) stable"
			sudo -E apt-get -y install "${pkg_name}"
		elif [ "$ID" == "fedora" ]; then
			repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
			sudo -E dnf -y install dnf-plugins-core
			sudo -E dnf config-manager --add-repo "$repo_url"
			sudo -E dnf makecache
			sudo -E dnf -y install "${pkg_name}"
		elif [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
			sudo -E yum install -y yum-utils
			repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
			sudo yum-config-manager --add-repo "$repo_url"
			sudo yum makecache
			sudo -E yum -y install "${pkg_name}"
		elif [[ "$ID" =~ ^opensuse.*$ ]] || [ "$ID" == "sles" ]; then
			sudo zypper removelock docker
			sudo zypper -n  install "${pkg_name}"
			sudo zypper addlock docker
		fi
	else
		# If tag received is invalid, then return an error message
		die "Unrecognized tag."
	fi
	sudo systemctl daemon-reload
	sudo systemctl start docker.socket
	restart_docker_service
	sudo gpasswd -a ${USER} docker
	sudo chmod g+rw /var/run/docker.sock
}

install_docker_s390x(){
	log_message "Installing docker"
	case "$ID" in
		ubuntu) sudo apt-get install -y docker.io ;;
		sles|opensuse*) sudo zypper install -y docker ;;
		*) die "Unsupported distribution: $ID" ;;
	esac
}

install_docker_ppc64le(){
	log_message "Installing Docker"
	case "$ID" in
		ubuntu) sudo apt-get install -y docker.io ;;
		*) die "Unsupported distribution: $ID" ;;
	esac
}

# This function removes the installed docker package.
remove_docker(){
	pkg_name=$(get_docker_package_name)
	if [ -z "$pkg_name" ]; then
		die "Docker not found in this system"
	else
		sudo systemctl stop docker.socket || true
		sudo systemctl stop docker
		version=$(get_docker_version)
		log_message "Removing package: $pkg_name version: $version"
		if [ "$ID" == "ubuntu" ]; then
			sudo apt -y purge ${pkg_name}
		elif [ "$ID" == "fedora" ]; then
			sudo dnf -y remove ${pkg_name}
		elif [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
			sudo yum -y remove ${pkg_name}
		elif [[ "$ID" =~ ^opensuse.*$ ]] || [ "$ID" == "sles" ]; then
			sudo zypper removelock ${pkg_name}
			sudo zypper -n remove ${pkg_name}
		else
			die "This script doesn't support your Linux distribution"
		fi
	fi
}

get_docker_default_runtime(){
	sudo docker info 2> /dev/null | awk '/Default Runtime/ {print $3}'
}

get_docker_version(){
	sudo docker version | awk '/Engine/{getline; print $2 }'
}

get_docker_package_name(){
	if [ "$ID" == "ubuntu" ]; then
		dpkg --get-selections | awk '/docker/ {print $1}'
	elif [ "$ID" == "fedora" ] || [ "$ID" == "centos" ] || [ "$ID" == "rhel" ] || [[ "$ID" =~ ^opensuse.*$ ]] || [ "$ID" == "sles" ]; then
		rpm -qa | grep docker | grep -v selinux
	else
		die "This script doesn't support your Linux distribution"
	fi
}

# This function gives information about:
# - Installed docker package and version
# - docker default runtime
info_docker(){
	if command -v "$DOCKER_BIN"; then
		message "docker_info: version: $(get_docker_version)"
		message "docker_info: default runtime: $(get_docker_default_runtime)"
		message "docker_info: package name: $(get_docker_package_name)"
	else
		warning "docker is not installed on this system"
		return 1
	fi
}

# Modify docker service using of $docker_options
modify_docker_service(){
	docker_options=$1
	docker_service_dir="/etc/systemd/system/docker.service.d/"
	if [ "$(ls -A $docker_service_dir)" ] && [ ${force} == false ]; then
		die "Found a service configuration file. Please use -f flag to overwrite the service configuration"
	elif [ "$(ls -A $docker_service_dir)" ] && [ ${force} == true ]; then
		rm -rf "${docker_service_dir}/*"
	fi
	echo "Stopping the docker service"
	sudo systemctl stop docker
	dir="/var/lib/docker"
	echo "Removing $dir"
	[ -d "$dir" ] && sudo rm -rf "$dir"
	echo "Changing docker service configuration"
	sudo mkdir -p "$docker_service_dir"
	cat <<EOF | sudo tee "$docker_service_dir/kata-containers.conf"
[Service]
Environment="$docker_http_proxy"
Environment="$docker_https_proxy"
ExecStart=
ExecStart=/usr/bin/dockerd ${docker_options}
EOF
	echo "Reloading unit files and starting docker service"
	sudo systemctl daemon-reload
	restart_docker_service
}

# This function configures docker to work by default with the
# specified runtime.
configure_docker(){
	[ -z "$runtime" ] && die "please specify a runtime with -r"

	# Default storage driver is overlay2
	[ -z "$storage_driver" ] && storage_driver="overlay2"

	if [ ! "$(info_docker)" ]; then
		die "Docker is not installed. Please install it before configuring the runtime"
	fi

	if [ "$(get_docker_default_runtime)" == "$runtime" ]; then
		message "configure_docker: $runtime is already configured as default runtime"
	else
		log_message "configure_docker: configuring $runtime as default docker runtime"
		# Check if the system has set http[s] proxy
		if [ -n "$http_proxy" ] && [ -n "$https_proxy" ] ;then
			docker_http_proxy="HTTP_PROXY=$http_proxy"
			docker_https_proxy="HTTPS_PROXY=$https_proxy"
		fi

		default_runtime="runc"

		if [ "$runtime" == "kata-runtime" ]  ; then
			# Try to find kata-runtime in $PATH, if it is not present
			# then the default location will be /usr/local/bin/kata-runtime
			if [ "$ID" == "fedora" ] || [ "$ID" == "centos" ]; then
				kata_runtime_bin="$(whereis $runtime | cut -f2 -d':' | tr -d "[:space:]")" || \
					die "$runtime cannot be found in $PATH, please make sure it is installed"
			else
				kata_runtime_bin="$(which $runtime)" || \
					die "$runtime cannot be found in $PATH, please make sure it is installed"
			fi
			docker_options="-D --add-runtime $runtime=$kata_runtime_bin --default-runtime=$default_runtime --storage-driver=$storage_driver"
			modify_docker_service "$docker_options"
		elif [ "$runtime" == "runc" ]  ; then
			docker_options="-D --storage-driver=$storage_driver"
			modify_docker_service "$docker_options"
		else
			die "configure_docker: runtime $runtime not supported"
		fi
	fi
}

main(){
	# Check if the script is run without arguments
	[ "$#" -eq 0 ] && usage && exit 1

	# Parse Usage options:
	while getopts ":h" opt; do
		case ${opt} in
			h )
				usage
				exit 0
				;;
			\? )
				echo "Invalid Option: -$OPTARG" 1>&2
				usage
				exit 1
				;;
		esac
	done
	shift $((OPTIND -1))

	ctr_manager=$1; shift
	case "$ctr_manager" in
	# Parse options
		docker)
			subcommand=$1; shift
			parse_subcommand_options "$@"
			;;
		*)
			warning "container manager \"$ctr_manager\" is not supported."
			usage
			exit 1
	esac

	shift "$((OPTIND - 1))"

	case "$subcommand" in
		configure )
			configure_docker
			;;

		info )
			info_docker
		;;

		install )
			install_docker
			;;

		remove )
			remove_docker
			;;

		*)
			echo "Invalid subcommand: \"$subcommand\""
			usage
			exit 1

	esac
	echo "Script finished"
}

main "$@"
