package Cpanel::BandwidthDB::Upgrade;

# cpanel - Cpanel/BandwidthDB/Upgrade.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module implements “upgrades” to the database. This may include
# schema upgrades as well as other improvements like data transforms.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use Cpanel::BandwidthDB::Constants ();

my $ONE_DAY  = 86400;
my $ONE_HOUR = 3600;

#Returns the number of schema updates that it made.
#
#   Named options:
#
#       rrd_directory   - optional, for v2 upgrade, specifies where to find
#                         RRD files to import
#
sub upgrade_schema {
    my ( $username, %opts ) = @_;

    die 'Need “username”!' if !$username;

    my $db = Cpanel::BandwidthDB::Upgrade::_Object->new($username);

    return $db->do_upgrades(%opts);
}

#----------------------------------------------------------------------

package Cpanel::BandwidthDB::Upgrade::_Object;

use strict;

use parent qw( Cpanel::BandwidthDB::Write );

use Cpanel::BandwidthDB::Constants ();
use Cpanel::BandwidthDB::Schema    ();

sub do_upgrades {
    my ( $self, %opts ) = @_;

    #Set an exclusive transaction so that nothing else will
    #try to upgrade the schema at the same time.
    $self->{'_dbh'}->do('BEGIN EXCLUSIVE TRANSACTION');

    #XXX: An ugly hack to get around DBD::SQLite RT 106151.
    #Remove once a fix for that issue is in production.
    $self->set_attr( 'in_transaction', 1 );

    my $schema_version = $self->_get_schema_version();

    for my $next_version ( ( 1 + $schema_version ) .. $Cpanel::BandwidthDB::Constants::SCHEMA_VERSION ) {
        Cpanel::BandwidthDB::Schema::upgrade_schema( $self->{'_dbh'}, $next_version );

        my $method_name = "_migrate_for_v$next_version";
        $self->$method_name(%opts) if $self->can($method_name);
    }

    $self->{'_dbh'}->do('COMMIT');

    #XXX: An ugly hack to get around DBD::SQLite RT 106151.
    #Remove once a fix for that issue is in production.
    $self->delete_attr('in_transaction');

    return 1;    #would it be helpful to return the number of upgrades?
}

#Override parent class. Parent classes want to die() if the
#schema is outdated on instantiation, but this class exists
#specifically to *fix* outdated schemas, so.
sub _check_for_outdated_schema { }

#overridden in tests
sub _migrate_for_v2 {
    my ( $self, %opts ) = @_;

    $self->_delete_pre_cpanel_data();

    return 1;
}

#The conversion from flat files in 11.50 allowed in almost anything after 1970.
#For 11.52 we need to be more sensible.
sub _delete_pre_cpanel_data {
    my ($self) = @_;

    my $dbh = $self->{'_dbh'};

    for my $interval (@Cpanel::BandwidthDB::Constants::INTERVALS) {
        my $table   = $self->_interval_table($interval);
        my $table_q = $dbh->quote_identifier($table);

        $self->{'_dbh'}->do(
            "DELETE FROM $table_q WHERE unixtime < (0 + ?)",
            undef,
            $Cpanel::BandwidthDB::Constants::MIN_ACCEPTED_TIMESTAMP,
        );
    }

    return;
}

1;
