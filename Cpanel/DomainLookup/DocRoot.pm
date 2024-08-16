package Cpanel::DomainLookup::DocRoot;

# cpanel - Cpanel/DomainLookup/DocRoot.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::userdata::Cache ();

my %DOCROOTS_BY_USER;
my $PERMIT_MEMORY_CACHE = 1;

=encoding utf-8

=head1 NAME

Cpanel::DomainLookup::DocRoot - Lookup docroots for a domain

=head1 SYNOPSIS

    use Cpanel::DomainLookup::DocRoot;

    my $domain_to_docroot_map_hr = Cpanel::DomainLookup::DocRoot::getdocroots();

=head2 getdocroots([$user])

Returns a hashref of domains to docroots.

For legacy compatibilty if called in array
context this function will return a hash
of domains to docroots.

If $user is not provided
the current user provided by Cpanel::current_username() or Cpanel::PwCache::getusername()
will be used.

=cut

sub getdocroots {
    my $user = shift;

    if ( !$user && $INC{'Cpanel.pm'} ) {
        $user = Cpanel::current_username();    # PPI NO PARSE - only need to set if already loaded
    }
    if ( !$user ) {
        require Cpanel::PwCache;
        $user = Cpanel::PwCache::getusername();
    }

    if ( !$user ) {
        die "Failed to determine username!";
    }

    if ( exists $DOCROOTS_BY_USER{$user} ) {
        return wantarray ? %{ $DOCROOTS_BY_USER{$user} } : $DOCROOTS_BY_USER{$user};
    }

    my $cache = Cpanel::Config::userdata::Cache::load_cache( $user, $PERMIT_MEMORY_CACHE );
    if ( $cache && %$cache ) {
        %{ $DOCROOTS_BY_USER{$user} } = map { $_ => $cache->{$_}->[4] } ( keys %$cache );
    }
    else {
        %{ $DOCROOTS_BY_USER{$user} } = ();
    }

    return wantarray ? %{ $DOCROOTS_BY_USER{$user} } : $DOCROOTS_BY_USER{$user};
}

#used from tests
sub _reset_caches {
    %DOCROOTS_BY_USER = ();
    return;
}

1;
