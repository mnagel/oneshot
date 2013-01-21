# oneshot

Upload files via SSH (SFTP) easily and provide HTTP(S) links to download them.

SFTP access and a properly configured webserver
are required on the server side.

All files are tagged with an expiry date
so obsolete files can be removed on demand.

## Installation

Make the script executable and drop it somewhere in your $PATH.

Run ```oneshot -i``` to create a new configuration file.

## Usage

```
# standard usage
clustergit [options] filenames...

# pastebin mode
clustergit -b
```

## Options

```
    -f	specify remote filename for next file
    -d	specify remote description for next file
    -t	specify title used in URL
    -x	specify ttl, days until remote file may be removed
    -c	specify local configfile
    -o	specify sftp host, "nil" triggers local copying, ignoring user&port
    -u	specify sftp user
    -l	specify remote base location
    -p	specify sftp port
    -e	specify http prefix
    -v	increase verbosity
    -w	increase fakeness
    -b	pastebin mode opens a textedit window
    -g	gallery with jpg thumbs
    -i	create new config file, nondestructive
    -s	run serverside test, searching outdated files
    -h	print help message
```

## Contact

via https://github.com/mnagel

## License

Copyright 2008-2013 Michael Nagel ubuntu@nailor.devzero.de

License: GPL-3
