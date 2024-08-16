package Cpanel::FileUtils::Symlinks;

# cpanel - Cpanel/FileUtils/Symlinks.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Read ();
use Cpanel::Autodie         ();

sub remove_dangling_symlinks_in_dir {
    my ( $dir, $opts ) = @_;

    my $verbose = $opts && $opts->{'verbose'};
    my $removed = 0;

    Cpanel::FileUtils::Read::for_each_directory_node(
        $dir,
        sub {
            return if !Cpanel::Autodie::exists_nofollow("$dir/$_");
            return if !-l _;

            my $dest = Cpanel::Autodie::readlink("$dir/$_");

            if ( substr( $dest, 0, 1 ) ne '/' ) {
                substr( $dest, 0, 0, "$dir/" );
            }

            return if Cpanel::Autodie::exists_nofollow($dest);

            if ($verbose) {
                print "Removing dangling symlink “$dir/$_”\n";
            }
            $removed += Cpanel::Autodie::unlink("$dir/$_");
        },
    );

    return $removed;
}

1;
