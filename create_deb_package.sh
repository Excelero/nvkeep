#!/bin/bash
#
# Nvkeep DEB Package Creator

DIST_DIR="dist"
PACKAGING_DIR="packaging"
VER_FILE=".version"

# Print usage info and exit
usage()
{
	echo "Nvkeep DEB Package Creator v${VERSION}"
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

# Remove any leftovers from previous deb build
cleanup_buildroot()
{
	rm -rf ./${PACKAGING_DIR}/BUILDROOT/* ./${PACKAGING_DIR}/nvkeep*.deb 
}

# Copy files to rpm buildroot
copy_to_buildroot()
{
	# copy files from "dist" directory to corresponding deb paths
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

# Prepare deb package info files
prepare_control_file()
{
	cp -r ${PACKAGING_DIR}/DEBIAN ${PACKAGING_DIR}/BUILDROOT/
	if [ $? -ne 0 ]; then
		echo "ERROR: Copying deb package metadata files failed. Aborting."
		exit 1
	fi
	
	cp ${PACKAGING_DIR}/BUILDROOT/DEBIAN/control.TEMPLATE \
		${PACKAGING_DIR}/BUILDROOT/DEBIAN/control

	sed -i "s/__VERSION__/${VERSION}/" ${PACKAGING_DIR}/BUILDROOT/DEBIAN/control
}

build_deb()
{
	dpkg-deb --root-owner-group --build ${PACKAGING_DIR}/BUILDROOT \
		${PACKAGING_DIR}/nvkeep_${VERSION}.deb

	if [ $? -ne 0 ]; then
		echo "ERROR: Building deb package failed."
		exit 1
	fi
}

show_deb_package()
{
	find packaging/ -name "*.deb"
}

# load version file
. $VER_FILE
if [ $? -ne 0 ]; then
	echo "ERROR: Unable to load version file ("$VER_FILE"). Aborting."
	exit 1
fi

# parse command line args
parse_args "$@"

echo "Nvkeep DEB Package Creator v${VERSION}"
echo

# change to installer dir
cd $(dirname $0)

if [ ! -e "dist" ]; then
	echo "ERROR: 'dist' directory not found."
	exit 1
fi

echo "* Cleaning up any previous deb build files..."
cleanup_buildroot

echo "* Preparing files for new deb package..."
copy_to_buildroot

echo "* Preparing debian package metadata..."
prepare_control_file

echo "* Building deb package..."
build_deb

echo
echo "All done. Your deb package is here:"
show_deb_package

echo
echo "NEXT STEP:"
echo "After installing the deb package, run nvkeep_apply_config as root on the first"
echo "host of this failover group."
