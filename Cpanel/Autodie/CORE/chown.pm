package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/chown.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 chown( $UID, $GID, $PATH_OR_FH )

cf. L<perlfunc/chown>

=cut

#NOTE: This will only chown() one thing at a time. It refuses to support
#multiple chown() operations within the same call. This is in order to provide
#reliable error reporting.
#
#You, of course, can still do: Cpanel::Autodie::chown() for @items;
#
sub chown {
    my ( $uid, $gid, $target, @too_many_args ) = @_;

    #This is here because it's impossible to do reliable error-checking when
    #you operate on >1 filesystem node at once.
    die "Only one path at a time!" if @too_many_args;

    local ( $!, $^E );

    return CORE::chown( $uid, $gid, $target ) || do {
        my $err = $!;

        {
            local ( $@, $! );

            require Cpanel::Exception;
            require Cpanel::FHUtils::Tiny;
            require Cpanel::FileUtils::Attr;
        }

        my $path       = Cpanel::FHUtils::Tiny::is_a($target) ? undef : $target;
        my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes($target);

        die Cpanel::Exception::create( 'IO::ChownError', [ error => $err, uid => $uid, gid => $gid, path => $path, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
    };
}

1;
