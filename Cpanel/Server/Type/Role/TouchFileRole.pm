package Cpanel::Server::Type::Role::TouchFileRole;

# cpanel - Cpanel/Server/Type/Role/TouchFileRole.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::TouchFileRole - Base class for a server role that creates and deletes a touchfile when being enabled and disabled

=head1 DESCRIPTION

This is an abstract class providing a simple implementation of a
C<Cpanel::Server::Type::Role> that utilizes a touchfile to determine when it
has been disabled.

It's designed so that subclasses need only implement internal C<_NAME> and
C<_TOUCHFILE> methods.

Note that if the touchfile exists, it indicates that the role is disabled. This
is so that on existing installations, where no touchfiles are expected to
exist, we default to assuming that all of the roles are enabled.

When implementing concrete subclasses of this role, they MUST be accompanied by
a corresponding C<Change> subclass. See the documentation in
C<Cpanel::Server::Type::Role> for more details.

=head1 SUBCLASSING

    package Cpanel::Server::Type::Role::ConcreteRole;

    use parent qw(
        Cpanel::Server::Type::Role::TouchFileRole
    );

    my $NAME;
    our $TOUCHFILE = "/path/to/touchfile";

    sub _NAME      {
        eval 'require Cpanel::LocaleString;'; ## no critic qw(BuiltinFunctions::ProhibitStringyEval) - hide from perlpkg
        $NAME ||= Cpanel::LocaleString("ConcreteRole"); ## no extract maketext
        return $NAME;
    }

    sub _TOUCHFILE { return $TOUCHFILE; }

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role
);

our $ROLES_TOUCHFILE_BASE_PATH = "/var/cpanel/disabled_roles";

=head2 _is_enabled()

The internal method that indicates (without a cache) whether the role is
enabled or not.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns 1 if the role is enabled, undef if not

=back

=back

=cut

sub _is_enabled {
    return !$_[0]->check_touchfile();
}

=head2 check_touchfile( )

Checks to see if the touchfile exists

=over 2

=item Input

=over 3

=item C<SCALAR>

A string containing the file system path for the touchfile

=back

=item Output

=over 3

Returns 1 if the touchfile exists, undef if not

=back

=back

=cut

sub check_touchfile {
    require Cpanel::Autodie;
    return Cpanel::Autodie::exists( $_[0]->_TOUCHFILE() );
}

=head2 _TOUCHFILE( )

An internal method to get the path to the touchfile of the implementing role.

This method must be implemented in the subclasses.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns a string representing the path to the touchfile for the role

=back

=back

=cut

sub _TOUCHFILE {
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

1;
