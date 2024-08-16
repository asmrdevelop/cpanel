
# cpanel - Cpanel/UserManager/Storage/Versions.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Storage::Versions;

use strict;
use Carp ();

my %versions = (
    '1' => [
        'ALTER TABLE users ADD COLUMN has_invite integer',
        'ALTER TABLE users ADD COLUMN invite_expiration integer',
        'UPDATE users SET has_invite = 0',
    ],
);

=head1 NAME

Cpanel::UserManager::Storage::Versions

=head1 DESCRIPTION

This module manages upgrade statement to apply to specific versions of the database.

=head1 FUNCTIONS

=head2 versions

Getter for the list of upgrades by version number.

=head3 RETURNS

hash ref - with the following organization:

  VERSION => [ SQL1, SQL2, ... SQLN ]

  Where:

  VERSION - string - define the version number where the SQL statements need to be
  applied. The value of each VERSION is an array ref containing a list of strings SQL#
  as defined below:

  SQL#    - string - a valid SQL statement that modifies the user manager database
  schema or data.

=cut

sub versions {
    return \%versions;
}

=head2 latest_version

Getter for the highest version number available from this module.

=head3 RETURNS

string - The highest version number managed by this module.

=cut

sub latest_version {
    my $latest = ( sort { $a <=> $b } keys %versions )[-1];
    return $latest;
}

=head2 create_meta_table_if_needed(ARGS)

Helper method that will create the table 'meta' if it does not exists.

=head3 ARGUMENTS

ARGS - hash - with the following possible elements:

    dbh        - DB_HANDLE - required handle to the database.
    initialize - boolean   - required if truthy will initialize the meta table with the latest version.
                             if falsey, will just create the table.

=head3 RETURNS

n/a

=cut

sub create_meta_table_if_needed {
    my %args       = @_;
    my $dbh        = $args{dbh}        // Carp::croak('Provide dbh');
    my $initialize = $args{initialize} // Carp::croak('Provide initialize');

    _do( $dbh, 'CREATE TABLE IF NOT EXISTS meta (key text, value text)' );
    if ($initialize) {
        _do( $dbh, 'INSERT INTO meta (key, value) VALUES("version", ?)', {}, latest_version() );
    }
    return;
}

sub _do {
    my ( $dbh, @do_args ) = @_;
    return $dbh->do(@do_args);
}

1;
