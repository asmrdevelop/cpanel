package Cpanel::Exception::System::RequiredRoleDisabled;

# cpanel - Cpanel/Exception/System/RequiredRoleDisabled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

=encoding utf-8

=head1 NAME

Cpanel::Exception::System::RequiredRoleDisabled

=head1 SYNOPSIS

    require Cpanel::Exception;
    Cpanel::Exception::create( 'System::RequiredRoleDisabled', [ role => $role ] );

=head1 DESCRIPTION

This exception indicates that a server doesn't have a specific role
or roles enabled.

=head1 ARGUMENTS

=over

=item * C<role> - Either a single string or a reference to an array of strings.

=back

=cut

sub _default_phrase {
    my ($self) = @_;

    require Cpanel::LocaleString;
    if ($>) {
        return Cpanel::LocaleString->new('This server does not support this functionality.');
    }

    my $role = $self->get('role');

    my @roles = ( ref $role ) ? @$role : $role;

    return Cpanel::LocaleString->new( 'This functionality is not available because the [list_and_quoted,_1] [numerate,_2,role is,roles are] disabled on this server.', \@roles, 0 + @roles );
}

1;
