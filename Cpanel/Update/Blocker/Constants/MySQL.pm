package Cpanel::Update::Blocker::Constants::MySQL;

# cpanel - Cpanel/Update/Blocker/Constants/MySQL.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Update::Blocker::Constants::MySQL - Provides constants for MySQL versions

=head1 SYNOPSIS

    use Cpanel::Update::Blocker::Constants::MySQL;

    foreach my $version (Cpanel::Update::Blocker::Constants::MySQL::BLOCKED_MYSQL_RELEASES()) {
        print "MySQL $version is blocked\n";
    }

=head1 DESCRIPTION

This module defines the blocked and supported version numbers for MySQL and MariaDB.

=cut

# NOTE: Prior to 11.44 we actually allowed these through because
# we didn't specifically blacklist them.
use constant BLOCKED_MYSQL_RELEASES => ( '3.23', '4.0', '4.1', '5.0', '5.1' );

# order matters
use constant SUPPORTED_MYSQL_RELEASES => ( '5.5', '5.6', '5.7', '8.0' );
use constant SUPPORTED_MARIADB_RELEASES => ( '10.0', '10.1', '10.2', '10.3', '10.5', '10.6', '10.11' );

use constant MYSQL_RELEASE_APPROACHING_EOL   => '';
use constant MARIADB_RELEASE_APPROACHING_EOL => '';

use constant MINIMUM_CURRENTLY_SUPPORTED_MYSQL   => '8.0';
use constant MINIMUM_CURRENTLY_SUPPORTED_MARIADB => '10.5';

=head1 METHODS

=head2 MINIMUM_RECOMMENDED_MYSQL_RELEASE()

Get the mininum supported MySQL version number.

B<Returns>: A string representing a MySQL version.

=cut

sub MINIMUM_RECOMMENDED_MYSQL_RELEASE {
    return (SUPPORTED_MYSQL_RELEASES)[0];
}

1;
