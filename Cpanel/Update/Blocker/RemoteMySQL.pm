package Cpanel::Update::Blocker::RemoteMySQL;

# cpanel - Cpanel/Update/Blocker/RemoteMySQL.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Update::Blocker::RemoteMySQL - Determine if a remote MySQL/MariaDB server is supported

=head1 SYNOPSIS

    use Cpanel::Update::Blocker::RemoteMySQL();

    my $obj = Cpanel::Update::Blocker::RemoteMySQL->new();

    if ($obj->is_remote_mysql()) {
        my $err;
        eval {
            $obj->is_mysql_supported_by_cpanel();
            1;
        } or do {
            $err = $@ || 'cPanel & WHM does not support your remote MySQL/MariaDB version.';
        };
        if ($err) {
            print $err;
        } else {
            print 'Your MySQL/MariaDB version is supported';
        }
    }

=head1 DESCRIPTION

This module determines if a remote MySQL/MariaDB server is supported by our product.

=cut

use Cpanel::Update::Logger                    ();
use Cpanel::MysqlUtils::Version               ();
use Cpanel::Update::Blocker::Constants::MySQL ();

=head1 CLASS METHODS

=head2 new($args_hr)

Object Constructor.

=over 3

=item C<< \%args_hr >> [in, optional]

A hashref with the following keys:

=over 3

=item C<< logger => Cpanel::Update::Logger->new() >> [in, optional]

The logger object used by the Cpanel::Update::Blocker classes.

=back

=back

B<Returns>: Returns a new object.

=cut

sub new {
    my ( $class, $args ) = @_;

    my $self = $class->init($args);
    return bless $self, $class;
}

=head2 init($args_hr)

Returns the new object which is part of the constructor.

=over 3

=item C<< \%args_hr >> [in, optional]

A hashref with the following keys:

=over 3

=item C<< logger => Cpanel::Update::Logger->new() >> [in, optional]

The logger object used by the Cpanel::Update::Blocker classes. If not passed in,
one will be created for you.

=back

=back

B<Returns>: Returns a hashref with the logger object.

=cut

sub init {
    my ( $class, $args ) = @_;

    my $logger = $args->{'logger'} || Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'debug' } );
    return {
        'logger' => $logger,
    };
}

=head2 is_mysql_supported_by_cpanel()

Determines if MySQL or MariaDB is supported by cPanel & WHM.

B<Returns>: On success, returns 1. On failure, it dies with an appropriate error message.

=cut

sub is_mysql_supported_by_cpanel {
    my $self = shift or die;

    my $current_version = Cpanel::MysqlUtils::Version::mysqlversion();

    foreach my $version ( Cpanel::Update::Blocker::Constants::MySQL::BLOCKED_MYSQL_RELEASES() ) {
        my $supported = Cpanel::MysqlUtils::Version::cmp_versions( $version, $current_version );
        if ( !$supported ) {
            die "Newer releases of cPanel & WHM are not compatible with your remote MySQL version: $version. You must upgrade your remote MySQL server to a version greater or equal to " . Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_RECOMMENDED_MYSQL_RELEASE() . ".\n";
        }
    }

    foreach my $version ( Cpanel::Update::Blocker::Constants::MySQL::SUPPORTED_MYSQL_RELEASES(), Cpanel::Update::Blocker::Constants::MySQL::SUPPORTED_MARIADB_RELEASES() ) {
        my $supported = Cpanel::MysqlUtils::Version::cmp_versions( $version, $current_version );
        return 1 if $supported;
    }

    die "cPanel & WHM does not support your remote MySQL/MariaDB version: $current_version.\n";
}

=head2 is_remote_mysql()

Determines if they system is using a remote MySQL or MariaDB server.

B<Returns>: Returns a truthy or falsy value.

=cut

sub is_remote_mysql {
    my $current_version = Cpanel::MysqlUtils::Version::current_mysql_version();
    return $current_version->{'is_remote'};
}

1;
