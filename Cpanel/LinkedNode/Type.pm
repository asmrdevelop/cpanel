package Cpanel::LinkedNode::Type;

# cpanel - Cpanel/LinkedNode/Type.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Type - Base class for implementing linked node logic

=head1 SYNOPSIS

    package Cpanel::LinkedNode::Type::ConcreteType;

    use parent qw(Cpanel::LinkedNode::Type);

    sub _get_and_validate_options_for_type {
        my ($self, %opts) = @_;

        die Cpanel::Exception::create( 'MissingParameters' [ names => qw(option1) ]) if !length $opts{option1};

        return ( option1 => $opts{option1} );
    }

    sub _get_required_services {
        return qw(service1 service2 service3);
    }

    sub _get_type_name {
        return "ConcreteType";
    }

    sub _get_minimum_supported_version {
        return "11.81.0.0";
    }

    1;

=head1 DESCRIPTION

This module is a base class for implementing concrete linked server node types.

=cut

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

=head2 %extended_options = $type_obj->get_and_validate_options_for_type( %input_args );

Get and validate any special options that this concrete type needs.

By default, this method returns an empty list signifying that no special/extended
arguments are required for the node type.

=over

=item Input

=over

A list of key/value pairs that were provided by the user.

=back

=item Output

=over

Returns the special arguments the concrete type requires as a list of key/value pairs.

=back

=back

=cut

sub get_and_validate_options_for_type {
    my ( $self, %opts ) = @_;
    return $self->_get_and_validate_options_for_type(%opts);
}

sub _get_and_validate_options_for_type {

    # By default this method does/returns nothing.
    # It can be overridden by subclasses that need options beyond the host, user
    # and API tokens.
    return ();
}

=head2 my @required_services = $type_obj->get_required_services()

Gets a list of services that a node is required to provide in order
to be linked as a node of the implementing type.

By default, this returns an empty list signifying the remote server is
not required to support any specific services.

These services should correspond to the service names returned by the
C<get_service_list> method in the L<Cpanel::Services::List> module.

=over

=item Input

=over

None

=back

=item Output

=over

In list context, this method returns a list of strings representing the required services.

In scalar context, this method returns the number of required services.

=back

=back

=cut

sub get_required_services {
    my ($self) = @_;
    return $self->_get_required_services();
}

sub _get_required_services {
    return ();
}

=head2 my $type_name = $type_obj->get_type_name()

Gets a pretty string providing the name for the implementing type.

By default this method dies with an AbstractClass exception.

=over

=item Input

=over

None

=back

=item Output

=over

A string representing the name of the implementing type suitable for displaying to the user

=back

=back

=cut

sub get_type_name {
    my ($self) = @_;
    return $self->_get_type_name();
}

sub _get_type_name {
    require Cpanel::Exception;
    die Cpanel::Exception::create('AbstractClass');
}

=head2 my $min_version = $type_obj->get_minimum_supported_version()

Returns the minimum version that a node must be running in order
to be linked as a node of the implementing type.

By default this method returns the current cPanel version.

Concrete types that link to non-cPanel nodes should override this
method to return undef.

=over

=item Input

=over

None

=back

=item Output

=over

Returns a string representing the minimum required version, or undef to indicate
that no version check should be performed.

=back

=back

=cut

sub get_minimum_supported_version {
    my ($self) = @_;
    return $self->_get_minimum_supported_version();
}

sub _get_minimum_supported_version {
    require Cpanel::Version::Full;

    my $full_version = Cpanel::Version::Full::getversion();

    $full_version =~ m<\A([0-9]+ \. [0-9]+) \. [0-9]+ \. [0-9]+\z>x or do {
        die "Unrecognized full version: “$full_version”!";
    };

    return "$1.0.0";
}

=head2 $type_obj->do_extended_validation( %opts )

Perform any additional validation the implementing type requires to
verify that the node can be linked as a specific type of node.

=over

=item Input

=over

=item A list of key/value pairs

The options list will contain user, host, and api_token keys, plus any additional
options returned by the C<get_and_validate_options_for_type>.

=back

=item Output

=over

None

=back

=back

=cut

sub do_extended_validation {
    my ( $self, %opts ) = @_;
    return $self->_do_extended_validation(%opts);
}

sub _do_extended_validation {

    # By default this method does nothing.
    # It can be overridden by subclasses that need to support validation other than
    # just an API token and server profile type check.
    return;
}

1;
