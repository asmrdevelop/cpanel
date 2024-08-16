package Cpanel::Server::Type::Role::TouchFileRole::Change;

# cpanel - Cpanel/Server/Type/Role/TouchFileRole/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie                           ();
use Cpanel::Debug                             ();
use Cpanel::FileUtils::TouchFile              ();
use Cpanel::Locale                            ();
use Cpanel::Server::Type::Role::TouchFileRole ();
use Cpanel::Server::Type::Role::EnabledCache  ();

use parent qw(
  Cpanel::Server::Type::Role::Change
);

BEGIN {
    *check_touchfile = *Cpanel::Server::Type::Role::TouchFileRole::check_touchfile;
    *_NAME           = Cpanel::Server::Type::Role::TouchFileRole->can('_NAME');
    *_TOUCHFILE      = Cpanel::Server::Type::Role::TouchFileRole->can('_TOUCHFILE');
}

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::TouchFileRole::Change - Methods for enabling and disabling C<TouchFileRole> based roles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::SomeConcreteTouchFileRole::Change ();

    my $self = Cpanel::Server::Type::Role::SomeConcreteTouchFileRole::Change->new();
    $self->enable( );
    $self->disable( );

=head1 DESCRIPTION

This module contains the logic to do the expensive tasks associated with enabling or disabling a server role that
is based on the C<Cpanel::Server::Type::Role::TouchFileRole>.

This logic was broken out of C<Cpanel::Server::Type::Role::TouchFileRole> in order to keep the implementing role
classes as lean as possible since 99% of the time they will only be used to determine if the role is enabled. The
actual enabling or disabling of a server role only happens when a server profile is changed, and will likely
never happen once a server has accounts and is in use.

=head2 enable( )

Checks to see if the touchfile exists and if it does, executes the callback and removes the touchfile

=over 2

=item Input

=over 3

None

=back

=back

=over 2

=item Output

=over 3

Returns 1 if the role has to be enabled, 0 if it is already enabled.

=back

=back

=cut

sub enable {

    my ($self) = @_;

    my $locale = Cpanel::Locale->get_handle();

    if ( $self->check_touchfile() ) {
        Cpanel::Debug::log_info( $locale->maketext( "Enabling “[_1]” …", $self->_NAME()->to_string() ) );
        $self->_enable();
        Cpanel::Autodie::unlink_if_exists( $self->_TOUCHFILE() );

        Cpanel::Server::Type::Role::EnabledCache::unset( $self->role_module() );

        return 1;
    }
    else {
        Cpanel::Debug::log_info( $locale->maketext( "“[_1]” is already enabled.", $self->_NAME()->to_string() ) );
    }

    return 0;
}

=head2 disable( )

Checks to see if the touchfile exists and if it does not, executes the callback and creates the touchfile

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns 1 if the role has to be disabled, 0 if it is already disabled.

=back

=back

=cut

sub disable {

    my ($self) = @_;

    my $locale = Cpanel::Locale->get_handle();

    if ( !$self->check_touchfile() ) {
        Cpanel::Debug::log_info( $locale->maketext( "Disabling “[_1]” …", $self->_NAME()->to_string() ) );
        $self->_disable();
        Cpanel::FileUtils::TouchFile::touchfile( $self->_TOUCHFILE() );
        return 1;
    }
    else {
        Cpanel::Debug::log_info( $locale->maketext( "“[_1]” is already disabled.", $self->_NAME()->to_string() ) );
    }

    return 0;
}

sub _enable {

    # By default this does nothing and the role just modifies the touchfile
}

sub _disable {

    # By default this does nothing and the role just modifies the touchfile
}

1;
