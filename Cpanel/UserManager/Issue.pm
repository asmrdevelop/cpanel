package Cpanel::UserManager::Issue;

# cpanel - Cpanel/UserManager/Issue.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::UserManager::Issue

=head1 DESCRIPTION

This class manages an issue. Issues are flexible in that they include various application specific tagging. The core
property is the message. Some issues also have numeric usage and limits properties so applications using them can
perform more sophisticated rendering and actions since they have more details about whats wrong.

=head1 CONSTRUCTION

The constructor accepts a single argument, which is an hash ref containing the following possible properties:

    type    - string - name of the application specific type of the issue. Commonly: 'info', 'warning' or 'error' but there may be additional ones.
    area    - string - name of the application specific area for the issue. Commonly: 'quota' or 'permission' but there may be others.
    service - string - name of the service the issue is associated with. Commonly: 'email', 'ftp', 'webdisk', but there may be others.
    message - string - human readable message associated with the issue
    used    - number - Optional, numeric value associated with certain limits based issues. This is the used amount of what is being measured.
    limit   - number - Optional, numeric value associated with certain limits based issues. This is the max amount of what is being measured.

=cut

sub new {
    my ( $package, $args ) = @_;
    return bless $args, $package;
}

=head1 PROPERITES

=head2 type

string - Getter/setter name of the application specific type for the issue. Commonly: 'info', 'warning' or 'error' but there may be additional ones.

=cut

sub type {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{type} = $_[1]; return $_[1]; }
    return $_[0]->{type};
}

=head2 area

string - Getter/setter name of the application specific area for the issue. Commonly: 'quota' or 'permission' but there may be others.

=cut

sub area {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{area} = $_[1]; return $_[1]; }
    return $_[0]->{area};
}

=head2 service

string - Getter/setter name of the service the issue is associated with. Commonly: 'email', 'ftp', 'webdisk', but there may be others.

=cut

sub service {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{service} = $_[1]; return $_[1]; }
    return $_[0]->{service};
}

=head2 message

string - Getter/setter human readable message associated with the issue

=cut

sub message {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{message} = $_[1]; return $_[1]; }
    return $_[0]->{message};
}

=head2 used

number - Getter/setter for an optional numeric value associated with certain limits based issues. This is the used amount of what is being measured.

=cut

sub used {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{used} = $_[1]; return $_[1]; }
    return $_[0]->{used};
}

=head2 limit

number - Getter/setter for an optional, numeric value associated with certain limits based issues. This is the max amount of what is being measured.

=cut

sub limit {    ## no critic(RequireArgUnpacking)
    if ( 2 == @_ ) { $_[0]->{limit} = $_[1]; return $_[1]; }
    return $_[0]->{limit};
}

=head2 percent_used

number - Getter if used and limit are set, this is the percent of limit used.

=cut

sub percent_used {
    my ($self) = @_;
    my $used   = $self->{used};
    my $limit  = $self->{limit};
    if ( $used && $limit ) {
        return 100 * $used / $limit;
    }
    return 0.0;
}

=head1 METHODS

=head2 as_hashref

Helper method that converts the object into a simple hash reference.

=head3 RETURNS

hash ref - containing all the fields managed by this class.

=cut

sub as_hashref {    ## no critic(RequireArgUnpacking)
    return { %{ $_[0] } };    # unbless
}

1;
