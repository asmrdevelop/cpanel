package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/readlink.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $_last_path;

=head1 FUNCTIONS

=head2 readlink( .. )

cf. L<perlfunc/readlink>

=cut

sub readlink {
    return readlink_if_exists(@_) // do {

        local $! = _ENOENT();

        _die_readlink($_last_path);
    };
}

=head2 readlink_if_exists( .. )

Like C<readlink()> but will return undef on ENOENT rather than
throwing an exception.

=cut

sub readlink_if_exists {    ## no critic(RequireArgUnpacking)
    my $path = @_ ? shift : $_;

    die 'readlink(undef) makes no sense!' if !defined $path;

    local ( $!, $^E );
    my $value = CORE::readlink($path);

    return $value if defined $value;

    if ( $! == _ENOENT() ) {
        $_last_path = $path;
        return undef;
    }

    # return() is just to keep Perl::Critic happy
    return _die_readlink($path);
}

sub _die_readlink {
    my ($path) = @_;

    my $err = $!;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::SymlinkReadError', [ error => $err, path => $path ] );
}

1;
