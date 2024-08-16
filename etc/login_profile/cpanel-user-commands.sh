#cPanel Added User Commands -- BEGIN

# Insert an entry into the PATH after all of the user's home directory paths.
if [ -x "/usr/local/cpanel/3rdparty/bin/perl" ]; then
    NEW_PATH="$(/usr/local/cpanel/3rdparty/bin/perl -e 'print join ":", map { ( ( !/^\Q$ENV{HOME}\E/ && !$seen++ && $_ ne $ARGV[0] ? @ARGV : () ), $_ ) } split /:/, $ENV{PATH};' /usr/local/cpanel/3rdparty/lib/path-bin)"
    if [ ! -z "$NEW_PATH" ]; then
        PATH=$NEW_PATH
        export PATH
    fi
fi

#cPanel Added User Commands -- END
