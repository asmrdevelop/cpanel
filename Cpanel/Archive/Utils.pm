package Cpanel::Archive::Utils;

# cpanel - Cpanel/Archive/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Autodie   ();
use Cpanel::Exception ();
use Cpanel::Fcntl     ();
use Cpanel::SafeFind  ();

use Try::Tiny;

my $MAX_FILES_ALLOWED = 2_000_000;    # die if they try to restore > 2M files

my $forbidden_mode_flags = Cpanel::Fcntl::or_flags(qw( S_IWOTH S_ISUID S_ISGID ));

my $sysopen_flags_for_chmod = Cpanel::Fcntl::or_flags(qw( O_RDONLY O_NOFOLLOW ));

#This will:
#   - unlink anything that's not:
#       - a regular file
#       - a directory
#       - a symlink that points to something in the current directory
#   - remove the following mode flags from anything not unlinked:
#       - world-writable
#       - setuid
#       - setgid
#
#The %opts are:
#   - preprocess: As given to the underlying File::Find call.
#
#An attempt at race safety is made here, but it's not foolproof;
#in particular, unlink() could inadvertently affect the wrong node.
#
#Return is multi-part:
#   - 1 or 0    success/failure
#   - message   string
#   - {
#       modified        => [ .. ]   #paths of nodes whose permissions changed
#       unlinked        => [ .. ]   #paths of nodes that were unlinked
#       files_examined  => ..       #integer, count of examined nodes
#   }
#
#Failure indicates a filesystem I/O error, which triggers an immediate
#cessation of work.
#
sub sanitize_extraction_target {
    my ( $extract_target_dir, %opts ) = @_;

    my ( @unlinked, @modified, $err );
    my $counter = 0;
    try {
        die "“$extract_target_dir” does not exist" if !-e $extract_target_dir;

        # The unsafe_to_read_archive directory gets converted to safe_to_read_archive directory in this step.
        Cpanel::SafeFind::finddepth(
            {
                preprocess => $opts{'preprocess'},

                'wanted' => sub {
                    ++$counter;
                    if ( $counter > $MAX_FILES_ALLOWED ) {
                        die "Exceeded max filesystem nodes while making permissions safe";
                    }

                    my ( $dev, $ino, $mode ) = Cpanel::Autodie::lstat($File::Find::name);

                    #Only allow files & dirs (no symlinks, dev nodes, etc.)
                    if ( !( -d _ || -f _ ) ) {
                        if ( !_is_same_dir_link($File::Find::name) ) {
                            Cpanel::Autodie::unlink($File::Find::name);
                            push @unlinked, $File::Find::name;
                        }

                        return;
                    }

                    #Remove setuid, setgid, and world-writable flags.
                    if ( $mode & $forbidden_mode_flags ) {
                        Cpanel::Autodie::sysopen( my $fh, $File::Find::name, $sysopen_flags_for_chmod );

                        my ( $dev2, $ino2 ) = Cpanel::Autodie::stat($fh);

                        if ( $dev != $dev2 || $ino != $ino2 ) {
                            die "Filesystem node “$File::Find::name” has changed!";
                        }

                        Cpanel::Autodie::chmod( ( $mode & 0775 ), $fh );
                        push @modified, $File::Find::name;
                    }
                },
                'no_chdir' => 1
            },
            $extract_target_dir,
        );
    }
    catch {
        $err = $_;
    };

    my $ret = {
        'modified'       => \@modified,
        'unlinked'       => \@unlinked,
        'files_examined' => $counter,
    };

    if ($err) {
        return ( 0, Cpanel::Exception::get_string($err), $ret, );
    }

    return ( 1, "Make permissions safe to read", $ret, );
}

sub _is_same_dir_link {
    my ($fh_or_file) = @_;

    return undef if !-l $fh_or_file;

    my $target = Cpanel::Autodie::readlink($fh_or_file);

    return ( ( $target !~ m<\A\.\.?\z> ) && ( $target !~ tr</><> ) ) ? 1 : 0;
}

1;
