package Cpanel::Server::Type::Role;

# cpanel - Cpanel/Server/Type/Role.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role - Base class for defining a role on the server

=head1 DESCRIPTION

C<Cpanel::Server::Type::Role> is the base class for defining roles on the
server. It MUST be accompanied by a corresponding C<Change> module that
describes what happens when the enabled or disabled.

Implementations that subclass the C<Cpanel::Server::Type::Role> should
only contain the smallest amount of code necessary to determine if the
role is enabled or disabled. Dependencies should be kept to a minimum.

Any logic or heavy lifting that the role needs to perform when it is
enabled or disabled should go into the accompanying C<Change> module. See
the L<SUBCLASSING> section below for split between the base role and its
corresponding C<Change> module.

For simple implementations, a C<Cpanel::Server::Type::Role::TouchFileRole>
abstract class has been provided that uses a touchfile to identify when a
role has explicitly been disabled.

=head1 SUBCLASSING

    package Cpanel::Server::Type::Role::ConcreteRole;

    use parent qw(
        Cpanel::Server::Type::Role
    );

    sub _NAME { return $instance_of_Cpanel_LocaleString }
    sub _DESCRIPTION { return $instance_of_Cpanel_LocaleString }

    sub _is_enabled {
        my $is_enabled;

        # Logic for how to determine if the role is enabled goes here.
        # The base class implements a cache of this value.

        return $is_enabled;
    }

    # Optional; default implementation returns truthy.
    sub _is_available { ... }

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

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::ConcreteRole;

    my $role = Cpanel::Server::Type::Role::ConcreteRole->new();
    my $is_enabled = $role->is_enabled();

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Profile            ();
use Cpanel::Server::Type::Profile::Constants ();
use Cpanel::Server::Type                     ();
use Cpanel::Server::Type::Role::EnabledCache ();

=head2 new()

Constructor

=cut

sub new {
    return bless {}, $_[0];
}

=head2 is_enabled()

Determines if the role is currently enabled on the server.

Note that this incorporates a check of availability:
an unavailable role will never be enabled.

This caches the results for each subclass.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns a boolean to indicate whether the role is enabled.

=back

=back

=cut

sub is_enabled {
    my ($obj_or_class) = @_;

    my $ref = ref($obj_or_class) || $obj_or_class;

    my $product_type = Cpanel::Server::Type::get_producttype();

    # Ideally this would die since DNSONLY should not be using the server roles to verify
    # its capabilities, but for now just log a warning to uncover any lurking issues.
    if ( $product_type eq Cpanel::Server::Type::Profile::Constants::DNSONLY() ) {

        # Uncomment this during testing to determine when the role checks are mistakenly called on DNSONLY
        # require Cpanel::Debug;
        # Cpanel::Debug::log_warn("Attempt to check the enabled status of the “$ref” role on DNSONLY.");
        return Cpanel::Server::Type::Role::EnabledCache::set( $ref, 1 );
    }

    # If the product type is not STANDARD (a full cPanel license), then the state
    # of the enabled and disabled roles are locked by the license and can be
    # determined by the metadata.
    if ( $product_type ne Cpanel::Server::Type::Profile::Constants::STANDARD() ) {
        my $META = Cpanel::Server::Type::Profile::get_meta();
        return Cpanel::Server::Type::Role::EnabledCache::set( $ref, 1 ) if grep  { $_ eq $ref } @{ $META->{$product_type}{enabled_roles} };
        return Cpanel::Server::Type::Role::EnabledCache::set( $ref, 0 ) if !grep { $_ eq $ref } @{ $META->{$product_type}{optional_roles} };
    }

    # Otherwise we need to determine the state of the role from the system

    # Check is_available() here so that subclasses don’t have to.
    my $val = Cpanel::Server::Type::Role::EnabledCache::get($ref);

    $val //= Cpanel::Server::Type::Role::EnabledCache::set(
        $ref,
        $obj_or_class->is_available() && $obj_or_class->_is_enabled() ? 1 : 0,
    );

    return $val;
}

=head2 is_available()

Determines if the role is available on the server.
This caches the results for each subclass.

An available role is a role that can be enabled. Most roles are available;
for a role to be “unavailable” it has to have some prerequisite that the
system doesn’t meet. An example of this is the PostgreSQL role, in which
the system must have PostgreSQL installed and configured before the role
can be enabled.

Note that a role can be “disabled” but still “available”. A role cannot,
though, be enabled and unavailable; an enabled role is, by definition,
available.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns whatever the subclass’s C<_is_available()> implementation returns.

=back

=back

=cut

# exposed for testing
our %_AVAILABLE_CACHE;

sub is_available {
    my ($obj_or_class) = @_;
    my $ref = ref($obj_or_class) || $obj_or_class;
    return $_AVAILABLE_CACHE{$ref} //= $obj_or_class->_is_available();
}

#----------------------------------------------------------------------

=head2 I<CLASS>->enabled_or_die()

Throws an exception if the current class’s role is disabled on the server.

=cut

sub verify_enabled {
    my ($class) = @_;

    if ( !$class->is_enabled() ) {
        my $role = substr( $class, 1 + rindex( $class, ':' ) );

        require Cpanel::Exception;
        die Cpanel::Exception::create( 'System::RequiredRoleDisabled', [ role => $role ] );
    }

    return;
}

#----------------------------------------------------------------------

=head2 SERVICES

Gets the list of services that are needed to fulfil the role

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an C<ARRAYREF> of strings representing the services that the role needs

=back

=back

=cut

sub SERVICES { return [] }

=head2 RESTART_SERVICES

Gets the list of services that need to be restarted when this role is enabled or disabled

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an C<ARRAYREF> of strings representing the services that need to be restarted

=back

=back

=cut

sub RESTART_SERVICES { return [] }

#----------------------------------------------------------------------

=head2 SERVICE_SUBDOMAINS

An array reference of service subdomains that should be created if
(and only if) the role is enabled.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an C<ARRAYREF> of strings representing the service subdomains.

=back

=back

=cut

sub SERVICE_SUBDOMAINS {
    return shift()->_SERVICE_SUBDOMAINS();
}

use constant _SERVICE_SUBDOMAINS => [];

#----------------------------------------------------------------------

=head2 RPM_TARGETS

Returns an array reference of RPM targets (e.g., C<powerdns>) to synchronize
whenever the role is enabled or disabled.

=cut

sub RPM_TARGETS {
    return shift()->_RPM_TARGETS();
}

use constant _RPM_TARGETS => [];

#----------------------------------------------------------------------

# By default, assume that the role is available for use. Certain subclasses may need to
# override this if they need to check for 3rd party or non-standard resources.
# E.G. The PostgreSQL role needs to make sure that PostgreSQL is actually installed.

sub _is_available { return 1 }

# These get accessed publicly.
# XXX TODO: Provide public accessors, or just rename them.
sub _NAME {
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}
*_DESCRIPTION = *_NAME;

1;
