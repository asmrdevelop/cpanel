package Cpanel::Hostname::Resolution;

# cpanel - Cpanel/Hostname/Resolution.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::CacheFile );

=encoding utf-8

=head1 NAME

Cpanel::Hostname::Resolution - A cache module to check if the hostname resolves

=head1 SYNOPSIS

    use Cpanel::Hostname::Resolution ();

    if ( Cpanel::Hostname::Resolution->load() ) {
         print "The hostname has DNS\n";
    }

=cut

use constant {
    _TTL  => 86400,
    _MODE => 0644,
    _PATH => '/var/cpanel/hostname_resolves'
};

=head2 save($new_data, @args)

Save the cache if the hostname does resolve to a valid ip address
and we are running as root.

=cut

sub save {
    my ( $self, $new_data, @args ) = @_;
    return if !$new_data || $>;    # no negative cache and cannot save if not root
    return $self->SUPER::save( $new_data, @args );

}

sub _LOAD_FRESH {
    require Cpanel::Domain::ExternalResolver;
    require Cpanel::Hostname;
    return Cpanel::Domain::ExternalResolver::domain_is_on_local_server( Cpanel::Hostname::gethostname() );
}

# If /etc/hostname is newer than the cache file provided, then consider the
# cache to be invalid.  Otherwise, if /etc/hostname does not exist, consider the
# non-existent cache to be valid.
sub _INVALIDATE {
    my ( $self, $path ) = @_;

    if ( -f '/etc/hostname' ) {
        my $mtime_hostname  = ( stat _ )[9];
        my $mtime_cachefile = ( stat $path )[9];

        return $mtime_hostname > $mtime_cachefile;
    }

    return 0;
}

1;
