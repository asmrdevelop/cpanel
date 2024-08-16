
# cpanel - Cpanel/DAV/Principal.pm                 Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Principal;

use strict;
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Sys::Hostname                ();
use Cpanel::PwCache                      ();
use Cpanel::Locale::Lazy 'lh';

use Carp ();
use Class::Accessor 'antlers';    # lightweight Moose-style attributes

=head1 NAME

Cpanel::DAV::Principal

=head1 CONSTRUCTION

The constructor should be given a 'name' attribute, which is the name of the principal.

Examples:

  name => 'jane' (for a cPanel account named jane)

  name => 'jane@example.com' (for a webmail account named jane@example.com)

=cut

sub new {
    my ( $package, %args ) = @_;
    my $self = {};
    bless $self, $package;
    $self->_process_principal( \%args );
    return $self;
}

=head1 ATTRIBUTES

The attributes of a principal are accessible by getter/setter methods
of the same name as the attribute.

=head2 displayname

The human-presentable name (aka "real name") of the principal.

=cut

has displayname => ( is => 'rw', isa => 'Str' );

=head2 description

The human-presentable description for the principal.

=cut

has description => ( is => 'rw', isa => 'Str' );

=head2 owner

The cPanel account to which the principal belongs.

For webmail user principals, this is the owner of the webmail account. For cPanel
account principals, this is the same cPanel account name.

=cut

has owner => ( is => 'rw', isa => 'Str' );

=head2 owner_homedir

The home directory of the owner of the principal.

=cut

has owner_homedir => ( is => 'rw', isa => 'Str' );

=head2 email

The email address of the principal.

For webmail user principals, this is the same address. For cPanel account principals,
this is <account>@<servername>.

=cut

has email => ( is => 'rw', isa => 'Str' );

=head2 name

The name of the principal.

This is the same name that was used when constructing the object.

=cut

has name => ( is => 'rw', isa => 'Str' );

=head2 is_group

Flag indicating this is a group instead of a standard principal

=cut

has is_group => ( is => 'rw', isa => 'Bool' );

=head2 uri

The URI for the principal.

For our purposes, this will always be something like:

principals/<principalname>

Note: No leading slash on the URI.

=cut

has uri => ( is => 'rw', isa => 'Str' );

=head2 is_owner

Test is the current principal is the account owner.

Returns

true if the name and owner are the same, false otherwise

=cut

sub is_owner {
    my ($self) = @_;
    return $self->name eq $self->owner ? 1 : 0;
}

=head2 get_principal

STATIC

Helper method to setup a principal object. Defaults to the cpanel
user if no name is passed.

=cut

sub get_principal {
    my ( $package, $name ) = @_;
    $name = Cpanel::PwCache::getusername() if !$name;
    return $package->new( name => $name );
}

=head2 get_group_principal

STATIC

Helper method to setup a group principal object.

=cut

sub get_group_principal {
    my ( $package, $name, $owner ) = @_;
    return $package->new( name => $name, is_group => 1, owner => $owner );
}

=head2 resolve_principal

Returns a principal object if the current principal is either undefined or the name of a principal.
If its already a principal object, its just a pass-thru.

Arguments

  - principal - Cpanel::DAV::Principal | string | undef

Returns

    Cpanel::DAV::Principal

=cut

sub resolve_principal {
    my $principal = shift;
    if ( !$principal || !ref($principal) ) {
        $principal = Cpanel::DAV::Principal->get_principal(
            $principal    # It's OK for this to be undef. That means the principal will be for the cPanel account.
        );
    }
    return $principal;
}

# _process_principal
#
# Arguments:
#   - The principal name
#
# Behavior: Initializes the following attributes of the principal object:
#   - email: The email address of the principal.
#   - owner: The system user who owns the principal.
#   - owner_homedir: The home directory of the system user who owns the principal.
#   - name: The principal name that was specified during construction.
#   - uri: The URI of the principal.
#
# Returns: n/a
sub _process_principal {
    my ( $self, $args ) = @_;
    my $name        = delete $args->{name} || Carp::confess('Cannot construct a principal object without a name.');
    my $displayname = delete $args->{displayname};                                                                    # optional
    my ( $local, $domain ) = split /\@/, $name;
    if ( !$domain || $domain eq Cpanel::Sys::Hostname::gethostname() ) {
        $domain = '';

        # We want to support just a plain system user, trying to use domains here just muddies the waters
        $self->name($local);
    }
    else {
        $self->name($name);
    }

    $self->uri( 'principals/' . $name );

    if ( $args->{is_group} ) {
        if ( $args->{owner} ) {
            $self->is_group(1);
            $self->_setup_owner( $args->{owner} );
        }
        else {
            die lh()->maketext( 'You must specify an owner for the group: [_1]', $self->name );
        }
    }
    elsif ( !$domain ) {
        $self->is_group(0);
        $self->_setup_owner($local);
    }
    else {
        $self->is_group(0);
        $self->owner( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) );
        if ( $self->owner && $self->owner ne 'root' ) {
            $self->owner_homedir( scalar( ( Cpanel::PwCache::getpwnam( $self->owner ) )[7] ) );
            $self->email( $local . '@' . $domain );
            die lh()->maketext( "The system could not locate the home directory for the [asis,Webmail] user “[_1]”.", $self->owner ) if !$self->owner_homedir;
        }
        elsif ( $self->owner eq 'root' ) {
            $self->owner_homedir( scalar( ( Cpanel::PwCache::getpwnam( $self->owner ) )[7] ) );
            $self->email($name);
        }
        else {
            die lh()->maketext( 'The system could not locate the owner of the domain “[_1]”.', $domain );
        }
    }

    $self->displayname( $displayname || $self->name );

    return;
}

# _setup_owner
#
# Arguments:
#   - The owner name
#
# Behavior: Initializes the following attributes of the principal object:
#   - email: The email address of the principal.
#   - owner: The system user who owns the principal.
#   - owner_homedir: The home directory of the system user who owns the principal.
#
# Returns: n/a
sub _setup_owner {
    my ( $self, $name ) = @_;

    $self->owner_homedir( ( Cpanel::PwCache::getpwnam($name) )[7] || die lh()->maketext( "The system could not locate the home directory for the [asis,cPanel] user “[_1]”.", $name ) );
    $self->email( $name . '@' . Cpanel::Sys::Hostname::gethostname() );
    $self->owner($name);    # Since this is a principal for a cPanel user, the owner of the principal is that same cPanel user
    return;
}

sub TO_JSON {
    return { %{ $_[0] } };
}

1;
