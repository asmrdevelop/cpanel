package Cpanel::Server::Type::Role::EnabledCache;

# cpanel - Cpanel/Server/Type/Role/EnabledCache.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::EnabledCache

=head1 SYNOPSIS

    Cpanel::Server::Type::Role::EnabledCache::set(
        'Cpanel::Server::Type::Role::FileStorage',
        1,
    );

=head1 DESCRIPTION

This module implements a simple in-memory cache to store whether
a given role is enabled or disabled.

=cut

#----------------------------------------------------------------------

use Carp ();

my %_THE_CACHE;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $value = set( $CLASS, $VALUE )

Sets $CLASS’s value in the cache as $VALUE (which must be 0 or 1).

Returns $VALUE.

=cut

sub set ( $class, $value ) {
    _validate_class($class);

    if ( $value ne '0' && $value ne '1' ) {
        _confess("Value must be 0 or 1, not “$value”.");
    }

    return $_THE_CACHE{$class} = $value;
}

=head2 $value = get( $CLASS )

Gets $CLASS’s value in the cache (or undef if no such value is set).

=cut

sub get ($class) {
    _validate_class($class);

    return $_THE_CACHE{$class};
}

=head2 $value = unset( $CLASS )

Unsets $CLASS’s value in the cache.
Returns the former value (or undef if no such value was set).

=cut

sub unset ($class) {
    _validate_class($class);

    return delete $_THE_CACHE{$class};
}

sub _confess ($msg) {
    local $Carp::Internal{ (__PACKAGE__) } = 1;
    return Carp::confess($msg);
}

sub _validate_class ($class) {
    _confess("Give a class name, not $class!") if ref $class;

    return;
}

#----------------------------------------------------------------------

sub _unset_all () {
    %_THE_CACHE = ();

    return;
}

1;
