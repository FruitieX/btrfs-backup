btrfs-backup.sh
============
This script creates local snapshot backups of given subvolumes and sends them
to a remote server. Before sending, the script will look for the most recent
"common" snapshot of a subvolume, ie. a snapshot that exists both locally and
on the remote. The script then proceeds to send only an incremental update
from the common snapshot to the newly created snapshot.

TODO: currently the script only works with incremental snapshots, it should
support sending a full snapshot if no common snapshot was found.
