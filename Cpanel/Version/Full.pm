package Cpanel::Version::Full;

# cpanel - Cpanel/Version/Full.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

=encoding utf-8

=head1 NAME

Cpanel::Version::Full - Tiny module for returning the full version

=head1 SYNOPSIS

    use Cpanel::Version::Full;

    print Cpanel::Version::Full::getversion();
    # 11.64.0.1

=head1 DESCRIPTION

A tiny module for reading the /usr/local/cpanel/version file
and falling back to Cpanel::Version::Tiny::VERSION_BUILD when
it is not available

=cut

my $full_version;

our $VERSION_FILE = '/usr/local/cpanel/version';

=head2 getversion

Returns the full version of cPanel in the format 11.64.0.1

=cut

sub getversion {
    if ( !$full_version ) {

        # No LoadFile here due to memory, but we still
        # fallback to the much slower require if needed
        if ( open my $ver_fh, '<', $VERSION_FILE ) {
            if ( read $ver_fh, $full_version, 32 ) {
                chomp($full_version);
            }
            elsif ($!) {
                warn "read($VERSION_FILE): $!";
            }
        }
        else {
            warn "open($VERSION_FILE): $!";
        }

        # The read failed so must fallback to the slower require
        if ( !$full_version || $full_version =~ tr{.}{} < 3 ) {
            require Cpanel::Version::Tiny;
            $full_version = $Cpanel::Version::Tiny::VERSION_BUILD;
        }
    }

    return $full_version;
}

# For testing only
sub _clear_cache {
    undef $full_version;
    return;
}

1;
