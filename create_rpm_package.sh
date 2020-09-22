#!/bin/bash
#
# Nvkeep RPM Package Creator

DIST_DIR="dist"
PACKAGING_DIR="packaging"
VER_FILE=".version"

# Print usage info and exit
usage()
{
	echo "Nvkeep RPM Package Creator v${VERSION}"
	echo
	echo "Usage:"
	echo "  $ $0"
	echo

	exit 1
}

# Parse command line arguments and set defaults
parse_args()
{
	local OPTIND # local to prevent effects from other subscripts

	while getopts ":h" opt; do
		case "${opt}" in
		h)
			# User requested help
			usage
			;;
		*)
			# Other option arguments are invalid
			usage
			;;
		esac
	done

	shift $((OPTIND-1))
}

# Remove any leftovers from previous rpm build
cleanup_buildroot()
{
	rm -rf ./${PACKAGING_DIR}/BUILDROOT/* ./${PACKAGING_DIR}/SPECS/rpm.spec \
		./${PACKAGING_DIR}/RPMS/*
}

# Copy files to rpm buildroot
copy_to_buildroot()
{
	# copy files from "dist" directory to corresponding rpm paths
	for src_path in $(find dist -type f); do 
		# remove leading DIST_DIR from paths
		dest_base_path="${PACKAGING_DIR}/BUILDROOT"
		dest_relative_path=$(echo $src_path | sed -e "s@^${DIST_DIR}/@@g");
		dest_path="${dest_base_path}/${dest_relative_path}"
		
		mkdir -pv $(dirname "$dest_path")
		if [ $? -ne 0 ]; then
			echo "ERROR: Directory creation failed. Aborting."
			exit 1
		fi

		if [ $(basename "$dest_path") = ".gitignore" ]; then
			continue; # skip .gitignore files
		fi
		
		cp -v --no-dereference --preserve=links,timestamps "$src_path" "$dest_path"
		if [ $? -ne 0 ]; then
			echo "ERROR: File copy failed. Aborting."
			exit 1
		fi

	done
}

prepare_spec_file()
{
	cp ${PACKAGING_DIR}/SPECS/rpm.spec.TEMPLATE ${PACKAGING_DIR}/SPECS/rpm.spec
	
	sed -i "s/__VERSION__/${VER_MAJOR}.${VER_MINOR}.${VER_PATCHLEVEL}/" \
		${PACKAGING_DIR}/SPECS/rpm.spec
}

build_rpm()
{
	rpmbuild ${PACKAGING_DIR}/SPECS/rpm.spec --bb --define "_topdir $(pwd)/${PACKAGING_DIR}" \
		--define "__spec_install_pre /bin/true" --buildroot=$(pwd)/${PACKAGING_DIR}/BUILDROOT

	if [ $? -ne 0 ]; then
		echo "ERROR: Building rpm package failed."
		exit 1
	fi
}

show_rpm_package()
{
	find packaging/RPMS -name "*.rpm"
}

# load version file
. $VER_FILE
if [ $? -ne 0 ]; then
	echo "ERROR: Unable to load version file ("$VER_FILE"). Aborting."
	exit 1
fi

# parse command line args
parse_args "$@"

echo "Nvkeep RPM Package Creator v${VERSION}"
echo

# change to installer dir
cd $(dirname $0)

if [ ! -e "dist" ]; then
	echo "ERROR: 'dist' directory not found."
	exit 1
fi

echo "* Cleaning up any previous rpm build files..."
cleanup_buildroot

echo "* Preparing files for new rpm package..."
copy_to_buildroot

echo "* Preparing rpm spec file..."
prepare_spec_file

echo "* Building rpm package..."
build_rpm

echo
echo "All done. Your rpm package is here:"
show_rpm_package

echo
echo "NEXT STEP:"
echo "After installing the rpm package, run nvkeep_apply_config as root on the first"
echo "host of this failover group."
