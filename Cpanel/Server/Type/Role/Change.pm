package Cpanel::Server::Type::Role::Change;

# cpanel - Cpanel/Server/Type/Role/Change.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::Change - Base class for implenting server role changes

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::Change;

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::ConcreteRole::Change ();

    Cpanel::Server::Type::Role::ConcreteRole::Change->enable();
    Cpanel::Server::Type::Role::ConcreteRole::Change->disable();

=head1 DESCRIPTION

This module defines a companion base class for C<Cpanel::Server::Type::Role>.

Since roles will not typically be enabled or disabled frequently, but will be
checked for their enabled or disabled state often, the logic for performing
the heavy lifting enabling or disabling the role is split out into a subclass
of this module;

=head1 SUBCLASSING

    package Cpanel::Server::Type::Role::ConcreteRole::Change;

    use parent qw(
        Cpanel::Server::Type::Role::Change
    );

    sub enable {
        # Logic for what to do when the role is enabled goes here
        return;
    }

    sub disable {
        # Logic for what to do when the role is disabled goes here
        return;
    }

=head1 SUBROUTINES

=cut

use cPstrict;

sub new {
    return bless {}, $_[0];
}

=head2 enable()

Called when a role is enabled for a server type, should define the necessary behvior to ensure a role is enabled.

By default this operation does nothing and returns 0.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns 1 if the role has to be enabled, 0 if it is already enabled.

=back

=back

=cut

sub enable { return 0; }

=head2 disable()

Called when a role is disabled for a server type, should define the necessary behavior to ensure a role is disabled

By default this operation does nothing and returns 0.

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

sub disable { return 0; }

=head2 I<OBJ_OR_CLASS>->role_module()

Gives the namespace of the corresponding role module. For example, if
I<OBJ_OR_CLASS> is C<Cpanel::Server::Type::Role::TheThing::Change> (or
an instance thereof), this returns C<Cpanel::Server::Type::Role::TheThing>.

=cut

sub role_module ($self_or_module) {

    # Allow call as either instance or class method:
    my $module = ref($self_or_module) || $self_or_module;

    $module =~ s<::Change\z><> or do {
        require Carp;
        Carp::confess("Invalid module or object given: $self_or_module");
    };

    return $module;
}

1;
