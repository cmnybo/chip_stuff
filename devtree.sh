#!/bin/bash

#  Copyright 2016 Cody Nybo
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#


# This is an interactive script for compiling, loading, & unloading device tree overlays
# This script requires dtc 1.41 or newer and a kernel compiled with CONFIG_OF_CONFIGFS
# The "arch/arm/boot/dts/include/dt-bindings" directory needs to be copied from the kernel source to "/usr/include/"
# Note: Avoid using spaces in .dts file names

dtboDir="/lib/firmware/dtbo"                        # contains compiled overlays
devTree="/sys/kernel/config/device-tree/overlays"   # device tree of_configfs
startDir="$(pwd)"                                   # starting directory

if [ $EUID -ne 0 ]; then echo >&2 "This script must be run as root."; quit 1; fi
if [ ! -d $devTree ]; then echo >&2 "This script requires a kernel compiled with CONFIG_OF_CONFIGFS"; quit 1; fi
command -v dtc >/dev/null 2>&1 || { echo >&2 "This script requires dtc but it's not installed."; quit 1; }
command -v cpp >/dev/null 2>&1 || { echo >&2 "This script requires cpp but it's not installed."; quit 1; }

# make overlay directory if it does not exist
if [ ! -d $dtboDir ]; then mkdir -p "$dtboDir"; fi

# show menu
menu () {
  cd "$startDir"
	tput setab 4
	tput setaf 7
	clear
	echo "      ┌─────────────────────────────────────────────────────────────────┐"
	echo "      │                  Device Tree Management Script                  │"
	echo "      ├─────┬──────────────────────────┬─────┬──────────────────────────┤"
	echo "      │  1  │  Compile Overlay         │  2  │  Edit Overlay            │"
	echo "      ├─────┼──────────────────────────┼─────┼──────────────────────────┤"
	echo "      │  3  │  Load Overlay            │  4  │  Unload Overlay          │"
	echo "      ├─────┼──────────────────────────┼─────┼──────────────────────────┤"
	echo "      │  5  │  List Overlays           │  6  │  Delete Overlay          │"
	echo "      ├─────┼──────────────────────────┼─────┼──────────────────────────┤"
	echo "      │  q  │  Quit                    │     │                          │"
	echo "      └─────┴──────────────────────────┴─────┴──────────────────────────┘"

	read -n1 -p "Option: " option
	echo ""
	case "$option" in
	"1" ) compileOverlay;;
	"2" ) editOverlay;;
	"3" ) loadOverlay;;
	"4" ) unloadOverlay;;
	"5" ) listOverlays;;
	"6" ) deleteOverlay;;
	"q" | "Q" ) quit;;
	* ) menu;;
	esac
}

# compile an overlay
compileOverlay () {
	clear

	if [ -z $1 ]; then
		echo "What overlay do you want to compile:"
		read -e file
	else
		file="$1"
	fi

	if [ -z $file ]; then
		# nothing entered; return to menu
		menu
	elif [ ! -f $file ]; then
		# file not found
		echo "Error: \"$file\" not found"
		continuePrompt "-t 3"
	else
		# compile file
		echo "Compiling $file"
		cpp -nostdinc -I /usr/include -undef -x assembler-with-cpp $file > preproc.tmp    # run preprocessor on device tree source
		cppExit=$?
		dtc -O dtb -o $dtboDir/${file%%.*}.dtbo -b0 -@ preproc.tmp                        # compile preprocessed source
		dtcExit=$?
		rm preproc.tmp                                                                    # remove temp file

		# check for errors
		if [ $cppExit -ne 0 ] || [ $dtcExit -ne 0 ]; then
			echo "There was an error during compilation"
			continuePrompt
		else
			echo "Compilation Successful"
		fi
	fi

	sleep 1
	menu
}

# load an overlay
loadOverlay () {
	clear
	cd $dtboDir
	echo "What overlay do you want to load:"
	read -e file

	if [ -z $file ]; then menu; fi
	file=${file%%.*}.dtbo

	if [ ! -f $file ]; then
		# file not found
		echo "Error: \"$file\" not found"
		continuePrompt "-t 3"
	elif [ ! -d $devTree/${file%%.*} ]; then
		# install overlay
		echo "Installing $file"
		mkdir $devTree/${file%%.*}
		cat $file > $devTree/${file%%.*}/dtbo
		echo "Overlay: $(cat $devTree/${file%%.*}/status)"
	else
		# overlay already loaded
		echo "Error: Overlay already loaded"

		read $1 -n1 -p "Reload [y/N]: " key
		case "$key" in
			"y" | "Y" ) reloadOverlay "$file"; echo "";;
			* ) menu;;
		esac
	fi

	# make sure overlay loaded
	if [ "$(cat $devTree/${file%%.*}/status)" != "applied" ]; then
		echo "Error: Overlay failed to load"
		continuePrompt
	fi

	sleep 1
	menu
}

# unload an overlay
unloadOverlay () {
	clear
	cd $devTree
	echo "What device tree do you want to unload:"
	read -e file

	if [ -z $file ]; then
		# nothing entered; return to menu
		menu
	elif [ ! -d $devTree/$file ]; then
		# file not found
		echo "Error: \"$file\" not loaded"
		continuePrompt "-t 3"
	else
		# unload overlay
		echo "Unloading $file"
		rmdir $devTree/$file
	fi

	# make sure overlay loaded
	if [ -d $devTree/$file ]; then
		echo "Error: Unable to unload overlay"
		continuePrompt
	else
		echo "Overlay Unloaded"
	fi

	sleep 1
	menu
}

# delete an overlay
deleteOverlay () {
	clear
	cd $dtboDir
	echo "What overlay do you want to delete:"
	read -e file

	if [ -z $file ]; then menu; fi
	file=${file%%.*}.dtbo

	if [ ! -f $file ]; then
		# file not found
		echo "Error: \"$file\" not found"
		continuePrompt "-t 3"
	else
		# delete overlay
		read $1 -n1 -p "Are You Sure [y/N]: " key
		case "$key" in
			"y" | "Y" ) rm "$file"; menu;;
			* ) menu;;
		esac
	fi
}

# reload an overlay
reloadOverlay() {
	echo "Reloading Overlay"
	# unload
	rmdir $devTree/${1%%.*}
	# verify unloaded
	if [ -d $devTree/${1%%.*} ]; then
		echo "Error: Unable to unload overlay"
		continuePrompt
	fi

	# reload
	mkdir $devTree/${1%%.*}
	cat $1 > $devTree/${1%%.*}/dtbo
	echo "Overlay: $(cat $devTree/${1%%.*}/status)"
	# verify reloaded
	if [ "$(cat $devTree/${1%%.*}/status)" != "applied" ]; then
		echo "Error: Overlay failed to load"
		continuePrompt
	else
		echo "Overlay Reloaded"
	fi

	sleep 1
	menu
}

# list loaded and available overlays
listOverlays () {
	clear
	echo "Loaded Overlays:"
	ls -1 $devTree

	echo ""
	echo "Available Overlays:"

	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	for file in `ls $dtboDir | egrep '\.(dtbo)'`; do
		echo ${file%%.*}
	done
	IFS=$SAVEIFS

	continuePrompt
}

editOverlay () {
	clear
	echo "What overlay do you want to edit:"
	read -e file

	if [ -z $file ]; then
		# nothing entered; return to menu
		menu
	elif [ ! -f $file ]; then
		# file not found
		echo "Error: \"$file\" not found"
		continuePrompt "-t 3"
	else
		# edit file
		oldHash=$(md5sum "$file" | grep -oe "[0-9a-f]\{32\}")
		vi "+syntax on" "+set nu" "+set tabstop=4" "+set shiftwidth=4" "+set nowrap" "$file"
		newHash=$(md5sum "$file" | grep -oe "[0-9a-f]\{32\}")

		if [ $oldHash != $newHash ]; then
			read $1 -n1 -p "File Modified, Recompile [Y/n]: " key
			case "$key" in
				"y" | "Y" )
					compileOverlay "$file"
					echo "";;
				* ) menu;;
			esac

		fi
	fi

	menu
}

# show a continue prompt
continuePrompt () {
	read $1 -n1 -p "Continue [Y/n]: " key
	case "$key" in
		"n" | "N" ) echo ""; quit;;
		* ) menu;;
	esac
}

# reset the colors and exit
quit () {
	if [ -z $1 ]; then
		stat=0;
	else
		stat=$1;
	fi

	tput sgr0
	clear
	exit $stat
}

# show the menu
menu
