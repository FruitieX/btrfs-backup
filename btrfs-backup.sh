#!/bin/bash

# Licensed under the GNU GPLv2 by the Free Software Foundation
# Copyright: Rasmus Eskola 2014

# DISCLAIMER: READ THROUGH AND UNDERSTAND THE SCRIPT BEFORE RUNNING
# I take no responsibility if this script destroys your data, damages hardware,
# or kills your cat etc.

# btrfs-backup.sh
# This script creates local snapshot backups of given subvolumes and sends them
# to a remote server. Before sending, the script will look for the most recent
# "common" snapshot of a subvolume, ie. a snapshot that exists both locally and
# on the remote. The script then proceeds to send only an incremental update
# from the common snapshot to the newly created snapshot.

# Setup
# All btrfs subvolumes from LOCAL_SUBVOLS will first be snapshotted into the
# respective directories in LOCAL_BACKUP_PATHS, which must reside on the
# subvolume itself. Each snapshot will then be sent to the remote to the
# respective directories in REMOTE_BACKUP_PATHS.

# Make sure all of these paths exist
LOCAL_SUBVOLS=(			"/"							"/home"						"/btrfs/vm"					)
LOCAL_BACKUP_PATHS=(	"/backup"					"/home/backup"				"/btrfs/vm/backup"			)
REMOTE_BACKUP_PATHS=(	"/btrfs/backup_bulky/root"	"/btrfs/backup_bulky/home"	"/btrfs/backup_bulky/vm"	)

REMOTE="root@s"

# abort on error
set -e

# must be in a format that can be sorted
TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)

echo "creating snapshots of the following subvolumes: \"${LOCAL_SUBVOLS[@]}\""
echo -e "are you sure you want to continue? (y/N)"
read answer
if [[ "$answer" != "y" ]]; then
	echo "aborting."
	exit
fi
echo

for i in "${!LOCAL_SUBVOLS[@]}"; do
	echo "subvolume: \"${LOCAL_SUBVOLS[$i]}\", remote path: \"${REMOTE_BACKUP_PATHS[$i]}\""

	# fetch backup directory listings for both hosts
	LOCAL_LIST=$(ls -1 "${LOCAL_BACKUP_PATHS[$i]}")
	REMOTE_LIST=$(ssh "$REMOTE" ls -1 "${REMOTE_BACKUP_PATHS[$i]}")

	# find most recent subvolume which is on both hosts by first taking the
	# intersection of $LOCAL_LIST and $REMOTE_LIST, then sorting it in reverse
	# order (newest first), then picking the first row out
	MOST_RECENT=$(comm -1 -2 <(echo "$LOCAL_LIST") <(echo "$REMOTE_LIST") | sort -r | head -n1)

	# no common snapshot found, send entire subvolume
	if [[ $MOST_RECENT == "" ]]; then
		echo "no common snapshot found for subvolume: \"${LOCAL_SUBVOLS[$i]}\""
		echo "do you want to send the entire subvolume instead?"
		echo "this will probably take a long time. (y/N)"

		read answer
		if [[ "$answer" != "y" ]]; then
			echo "skipping subvolume: \"${LOCAL_SUBVOLS[$i]}\""
		else
			# create snapshot
			sudo btrfs subvolume snapshot -r "${LOCAL_SUBVOLS[$i]}" "${LOCAL_BACKUP_PATHS[$i]}/$TIMESTAMP"
			sync

			echo "sending subvolume: \"${LOCAL_SUBVOLS[$i]}\""
			sudo btrfs send -v "${LOCAL_BACKUP_PATHS[$i]}/$TIMESTAMP" | ssh "$REMOTE" "btrfs receive -v \"${REMOTE_BACKUP_PATHS[$i]}/\""
			echo
		fi
	else
		# create snapshot
		sudo btrfs subvolume snapshot -r "${LOCAL_SUBVOLS[$i]}" "${LOCAL_BACKUP_PATHS[$i]}/$TIMESTAMP"
		sync

		echo "sending incremental snapshot from: \"$MOST_RECENT\" to: \"$TIMESTAMP\""
		sudo btrfs send -v -p "${LOCAL_BACKUP_PATHS[$i]}/$MOST_RECENT" "${LOCAL_BACKUP_PATHS[$i]}/$TIMESTAMP" | ssh "$REMOTE" "btrfs receive -v \"${REMOTE_BACKUP_PATHS[$i]}/\""
		echo
	fi
done

echo "All done!"
