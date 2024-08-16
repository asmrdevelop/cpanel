package Cpanel::SimpleSync;

# cpanel - Cpanel/SimpleSync.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SimpleSync::CORE ();

sub syncfile {
    no warnings 'redefine';

    *syncfile = \&Cpanel::SimpleSync::CORE::syncfile;
    goto &Cpanel::SimpleSync::CORE::syncfile;
}

sub copy {
    no warnings 'redefine';

    *copy = \&Cpanel::SimpleSync::CORE::copy;
    goto &Cpanel::SimpleSync::CORE::copy;
}

# globsyncfile -
#    Params:
#         source   : csh style glob expression for file matching.
#         dest     : Directory to copy the files into.
#         no_sym   : 1 to not follow symlinks, 0 to follow.
#         no_chown : 1 to disable chowning, 0 to chown.
sub globsyncfile {
    my ( $source, $dest, $no_sym, $no_chown ) = @_;

    my @files = glob $source;
    foreach my $file (@files) {

        #TODO: respond to failures here
        () = Cpanel::SimpleSync::CORE::syncfile( $file, $dest, $no_sym, $no_chown );
    }
    return \@files;
}
1;
