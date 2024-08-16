package Cpanel::DKIM::ValidityCache::Write;

# cpanel - Cpanel/DKIM/ValidityCache/Write.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::ValidityCache::Write

=head1 SYNOPSIS

    $created = Cpanel::DKIM::ValidityCache::Write->set('example.com');

    $deleted = Cpanel::DKIM::ValidityCache::Write->unset('example.com');

=head1 DESCRIPTION

The write logic for L<Cpanel::DKIM::ValidityCache>. See that module
for more details.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use parent qw( Cpanel::DKIM::ValidityCache );

use constant {
    _ENOENT    => 2,
    _BASE_MODE => 0711,
};

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 $created_yn = I<CLASS>->set( $DOMAIN )

Set $DOMAIN to a truthy value in the datastore. Returns the number
of entries newly created (1 or 0).

This will automatically create the datastore directory if it does
not exist.

This throws an exception on failure.

=cut

sub set {
    my ( $class, $entry ) = @_;

    my $did_init;

    my $ret;

  OPEN: {
        try {
            $ret = Cpanel::DKIM::ValidityCache::Write::_TouchFile->set_on($entry);
        }
        catch {
            if ( try { $_->isa('Cpanel::Exception::IO::FileOpenError') } ) {
                if ( !$did_init && try { $_->error_name() eq 'ENOENT' } ) {
                    $class->initialize();
                    $did_init = 1;
                }
                else {
                    local $@ = $_;
                    die;
                }
            }
        };

        redo OPEN if $did_init && !defined $ret;
    }

    return $ret;
}

=head2 $removed_yn = I<CLASS>->unset( $DOMAIN )

Removes $DOMAIN’s entry (if any) and returns the number of entries
removed (1 or 0).

This throws an exception on failure.

=cut

sub unset {
    my ( undef, $entry ) = @_;

    return Cpanel::DKIM::ValidityCache::Write::_TouchFile->set_off($entry);
}

=head2 I<CLASS>->initialize()

Ensures that the cache is configured correctly on disk, including
access controls.

Ordinarily this function shouldn’t need to be called
except in cases where the access control configuration changes; for
example, during initial v78 rollout the cache was readable only by
C<root> and C<mail> users; it later became apparent that world readability
was both desirable and safe, so this function then needed to be called on
upcp for machines that had already set up their validity caches.

=cut

sub initialize {
    my ($class) = @_;

    require Cpanel::Mkdir;
    my $created = Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $class->_BASE(),
        _BASE_MODE(),
    );

    return;
}

#----------------------------------------------------------------------

# An internal class that we don’t expose.
package Cpanel::DKIM::ValidityCache::Write::_TouchFile;

use parent qw( Cpanel::Config::TouchFileBase );

sub _TOUCH_FILE {
    my ( undef, $entry ) = @_;

    return Cpanel::DKIM::ValidityCache::Write->_BASE() . "/$entry";
}

1;
