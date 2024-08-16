package Cpanel::Server::Type::Role::MySQLClient;

# cpanel - Cpanel/Server/Type/Role/MySQLClient.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MySQLClient

=head1 SYNOPSIS

    if ( Cpanel::Server::Type::Role::MySQLClient->is_enabled() ) { .. }

=head1 DESCRIPTION

This is a “pseudo-role” that abstracts over the configured state of
MySQL/MariaDB client action on this machine. The role’s enabled-ness is
equivalent to whether MySQL/MariaDB client access for cPanel & WHM is
intended—either locally or remotely.

B<NOTE:> This role cannot be enabled or disabled directly,
and controls for such should not be exposed.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Server::Type::Role';

use Cpanel::Server::Type::Role::MySQL ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->is_enabled()

If the MySQL role is enabled, or if cPanel & WHM is configured to access
a remote MySQL/MariaDB server, this returns true.

Note that this returns true regardless of the state of the local MySQL
service. Contrast this with C<Cpanel::Services::Enabled::is_provided()>,
which cares only for the state of the MySQL service, not the role. (Both,
of course, return true when remote MySQL is configured.)

=cut

sub is_enabled {
    return Cpanel::Server::Type::Role::MySQL->is_enabled() || do {
        if ($>) {
            require Cpanel::Mysql::Version;
            Cpanel::Mysql::Version::get_server_information()->{'is_remote'};
        }
        else {
            require Cpanel::MysqlUtils::MyCnf::Basic;
            Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql();
        }
    };
}

#----------------------------------------------------------------------

sub _NAME {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return Cpanel::LocaleString->new('MySQL Client');
}

sub _DESCRIPTION {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    return Cpanel::LocaleString->new('A pseudo-role that indicates whether the system provides the [asis,MySQL]/[asis,MariaDB] service (whether local or remote).');
}

1;
