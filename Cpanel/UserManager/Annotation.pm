
# cpanel - Cpanel/UserManager/Annotation.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Annotation;

use strict;
use warnings;

=head1 NAME

Cpanel::UserManager::Annotation

=head1 DESCRIPTION

This class manages a single service annotation. Services include Email, FTP, WebDisk
services. It's used to build up a list of services associated with a specific
sub-account or cpanel user.

=head1 CONSTRUCTION

The constructor accepts a single argument, which is an hash ref containing the following possible properties:

    service          - string - name of the service
    username         - string - name of the user
    domain           - string - domain for the user
    owner_guid       - string - guid associated with the user who owns this service
    merged           - boolean - true if merged, false if not merged.
    dismissed_merge  - boolean - true if dismissed, false if not dismissed.

=cut

sub new {
    my ( $package, $args ) = @_;
    return bless $args, $package;
}

=head1 PROPERITES

=head2 service

Getter/setter for the service name: email, ftp, webdisk, ...

=cut

sub service {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{service} = $_[1]; return $_[1]; }
    return $_[0]->{service};
}

=head2 username

Getter/setter for the username of a user.

=cut

sub username {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{username} = $_[1]; return $_[1]; }
    return $_[0]->{username};
}

=head2 domain

Getter/setter for the domain associated with a user.

=cut

sub domain {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{domain} = $_[1]; return $_[1]; }
    return $_[0]->{domain};
}

=head2 owner_guid

Getter/setter for the unique id associated with a user.

=cut

sub owner_guid {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{owner_guid} = $_[1]; return $_[1]; }
    return $_[0]->{owner_guid};
}

=head2 merged

Getter/setter for the boolean merged. If truthy this service is part
of a user account. Otherwise, the service is independent from a user.
It may or may not be dismissed.

=cut

sub merged {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{merged} = $_[1]; return $_[1]; }
    return $_[0]->{merged};
}

=head2 dismissed_merge

Getter/setter for the boolean. If truthy this service was previously identified as
a mergable serice but was dismissed by a user and is not considered related to any
other services with the same username.

=cut

sub dismissed_merge {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{dismissed_merge} = $_[1]; return $_[1]; }
    return $_[0]->{dismissed_merge};
}

=head2 full_username

Getter for the full username of a user in the form: <username>@<domain>.

=cut

sub full_username {
    my ($self) = @_;
    return $self->username . '@' . $self->domain;
}

=head1 METHODS

=head2 as_insert

Helper that generates an SQL insert statement for this service annotation to insert it into the database.

=head3 RETURNS

list - containing the following positional values:

  [0] - string - Parameterized SQL statement.
  [1] - array ref - Containing the values that can be substituted into the parameterized SQL statement.

=cut

sub as_insert {
    my ($self)    = @_;
    my $statement = 'INSERT INTO annotations (service, username, domain, owner_guid, merged, dismissed_merge) VALUES (?, ?, ?, ?, ?, ?)';
    my @values    = map { $self->$_ } qw(service username domain owner_guid merged dismissed_merge);
    return ( $statement, \@values );
}

=head2 as_update

Helper that generates an SQL update statement for this service annotation to insert it into the database.

=head3 RETURNS

list - containing the following positional values:

  [0] - string - Parameterized SQL statement.
  [1] - array ref - Containing the values that can be substituted into the parameterized SQL statement.

=cut

sub as_update {
    my ($self)    = @_;
    my $statement = 'UPDATE annotations SET owner_guid = ?, merged = ?, dismissed_merge = ? WHERE service = ? AND username = ? AND domain = ?';
    my @values    = map { $self->$_ } qw(owner_guid merged dismissed_merge service username domain );
    return ( $statement, \@values );
}

1;
