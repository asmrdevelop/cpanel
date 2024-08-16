package Cpanel::Inotify::Wrap;

# cpanel - Cpanel/Inotify/Wrap.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Inotify::Wrap - wrap load of L<Linux::Inotify2>

=head1 DESCRIPTION

This loads the CPAN L<Linux::Inotify2> module, subject to certain limitations.

You may want to use C<Cpanel::Inotify> instead, which interfaces directly with
the system calls and thus avoids XS.

=head1 FUNCTIONS

=head2 load()

Loads L<Linux::Inotify2> if C</var/cpanel/conserve_memory> doesn’t exist
and if C<bin/inotify_test> indicates that we’re ok to load the module.

=cut

sub load {
    return 1 if ( exists $INC{'Linux/Inotify2.pm'} );
    return 0 if ( -e '/var/cpanel/conserve_memory' );

    # Previously we called inotify_test because the older
    # versions of this module under perl v5.6 crashed if inotify was not
    # working.  Thats long been fixed so an eval test is just fine here.
    local $@;
    eval {
        local $SIG{'__DIE__'};
        local $SIG{'__WARN__'};
        require Linux::Inotify2;
    };
    return 0 if $@;
    return 1 if ( exists $INC{'Linux/Inotify2.pm'} );
    return 0;
}

1;
