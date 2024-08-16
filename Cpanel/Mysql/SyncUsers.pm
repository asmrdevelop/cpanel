package Cpanel::Mysql::SyncUsers;

# cpanel - Cpanel/Mysql/SyncUsers.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::SyncUsers

=head1 SYNOPSIS

    sync_grant_files_to_db( output => \*STDOUT );

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Config::Users       ();
use Cpanel::Locale              ();
use Cpanel::Exception           ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::Mysql::Create       ();
use Cpanel::Set                 ();
use Cpanel::DB::GrantsFile      ();
use Cpanel::DB::Utils           ();
use Cpanel::MysqlUtils::Grants  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync_grant_files_to_db( %OPTS )

This function compensates for the scenario where a user was created
while MySQL/MariaDB was inactive but now needs to be active. It does
this by reading the password hash from the grants file (which records
users’ password hashes even if MySQL/MariaDB is disabled) and creating
users for them.

=cut

*_get_dbi_handle = \*Cpanel::MysqlUtils::Connect::get_dbi_handle;
*_getcpusers     = \*Cpanel::Config::Users::getcpusers;

sub sync_grant_files_to_db {
    my (%opts) = @_;

    my $lfh = $opts{'output'};

    my $log_cr = sub {
        $lfh && print {$lfh} @_, "\n";
    };

    my $missing_ar = _determine_missing_cpusers();

    my $lh = Cpanel::Locale->get_handle();

  CPUSER:
    for my $cpuser (@$missing_ar) {
        $log_cr->( "\n" . $lh->maketext( 'Missing user: [_1]', $cpuser ) );

        my $grants_db = eval { Cpanel::DB::GrantsFile::read_for_cpuser($cpuser) };

        if ( !$grants_db ) {
            if ($@) {
                warn( Cpanel::Exception::get_string_no_id($@) . "\n" );
            }
            else {
                warn( $lh->maketext( 'No database grants file exists for “[_1]”.', $cpuser ) . "\n" );
            }

            next;
        }

        my $dbowner = Cpanel::DB::Utils::username_to_dbowner($cpuser);

        my $grants_ar = $grants_db->{'MYSQL'}{$dbowner} or do {
            warn( $lh->maketext( '“[_1]”’s grants file contains no [asis,MySQL]/[asis,MariaDB] grants to restore.', $cpuser ) . "\n" );
            next;
        };

        for my $sql (@$grants_ar) {
            my $did_set;

            try {
                my $grant_obj = Cpanel::MysqlUtils::Grants->new($sql);

                my $dbowner = Cpanel::DB::Utils::username_to_dbowner($cpuser);

                my $grant_is_ok = $grant_obj->db_user() eq $dbowner;

                $grant_is_ok &&= ( $grant_obj->db_privs() =~ tr<a-z><A-Z>r ) eq 'USAGE';

                $grant_is_ok &&= ( $grant_obj->quoted_db_name() eq '*' );

                if ($grant_is_ok) {
                    my $pw_hash = $grant_obj->hashed_password();

                    $log_cr->( $lh->maketext( 'Creating [asis,MySQL]/[asis,MariaDB] user “[_1]” …', $dbowner ) );

                    my $mysql = Cpanel::Mysql::Create->new( { 'cpuser' => $cpuser, 'allow_create_dbmap' => 1 } );

                    # create_dbowner() expects the REMOTE_PASSWORD
                    # environment variable to be set.
                    local $ENV{'REMOTE_PASSWORD'} = rand;

                    # create_dbowner also sets up any remote hosts
                    # making updatehosts unneeded.
                    $mysql->create_dbowner($dbowner);

                    # 1 means to create the user.
                    $mysql->passwduser_hash( $dbowner => $pw_hash, 1 );

                    $log_cr->( "\t" . $lh->maketext('Success!') );

                    $did_set = 1;
                }
            }
            catch {
                warn $_;
            };

            next CPUSER if $did_set;
        }
    }

    return;
}

# mocked in tests
sub _determine_missing_cpusers {
    my $dbh = _get_dbi_handle();

    my @cpusers = sort( _getcpusers() );

    # Rather than do a separate existence check for each username,
    # let’s batch the usernames to minimize the number of queries.
    # Each individual query will be heavier, but that should still
    # be a win versus separate queries.
    my $BATCH_SIZE = 200;

    my $places_batch = join( ',', ('?') x $BATCH_SIZE );

    my $exists_sth = $dbh->prepare("SELECT GROUP_CONCAT(DISTINCT User SEPARATOR '\\n') FROM mysql.user WHERE BINARY User in ($places_batch)");

    my @missing;

    while ( my @batch = splice( @cpusers, 0, $BATCH_SIZE ) ) {
        my %dbowner_to_cpuser;

        for my $cpuser ( @batch[ 0 .. ( $BATCH_SIZE - 1 ) ] ) {
            if ( defined $cpuser ) {
                my $dbowner = Cpanel::DB::Utils::username_to_dbowner($cpuser);
                $dbowner_to_cpuser{$dbowner} = $cpuser;
                $cpuser = $dbowner;
            }

            # If we do a batch size of 100, and there are 105 entries,
            # then the 2nd query will only have 5 variables to plug in.
            # Rather than asking MySQL to PREPARE a separate query, though,
            # let’s reuse the existing query. For that to work we need the
            # correct number of bind variables.
            else {
                $cpuser = q<>;
            }
        }

        # At this point, @batch contains a list of dbowners.
        # This is what we need to query on.

        $exists_sth->execute(@batch);

        my ($found_txt) = $exists_sth->fetchrow_array();
        my @found       = split m<\n>, $found_txt // '';

        # We need to convert dbowners back to cpusers. Thankfully, we forbid
        # dbowner conflicts on cpuser creation, so we can be confident that
        # the cpuser-dbowner relationship is one-to-one, even though the
        # conversion logic itself allows multiple cpusers per dbowner.

        push @missing, map { $dbowner_to_cpuser{$_} // () } Cpanel::Set::difference( \@batch, \@found );
    }

    return \@missing;
}

1;
