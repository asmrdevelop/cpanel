package Cpanel::Pkgacct::Components::Postgresql;

# cpanel - Cpanel/Pkgacct/Components/Postgresql.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Write      ();
use Cpanel::PostgresAdmin::Backup ();
use Cpanel::PostgresAdmin::Basic  ();
use Cpanel::PostgresAdmin::Check  ();
use Cpanel::PostgresUtils::PgPass ();
use Cpanel::CpuWatch::Suspend     ();
use Cpanel::FileUtils::TouchFile  ();
use Cpanel::Logger                ();

use Try::Tiny;

#TODO: This logic was moved from the scripts/pkgacct script and should
#be audited for error responsiveness.

sub perform {
    my ($self) = @_;

    my $work_dir   = $self->get_work_dir();
    my $user       = $self->get_user();
    my $uid        = $self->get_uid();
    my $output_obj = $self->get_output_obj();
    my $cpconf     = $self->get_cpconf();
    my $OPTS       = $self->get_OPTS();         # See /usr/local/cpanel/bin/pkgacct process_args for a list of possible OPTS

    # The arguments are documented in /usr/local/cpanel/bin/pkgacct.pod
    # In this module, we use
    # - running_under_cpbackup
    # - db_backup_type

    return 1 unless Cpanel::PostgresAdmin::Check::is_configured()->{'status'};

    my $postgresuser = Cpanel::PostgresUtils::PgPass::getpostgresuser() or return 1;

    # The connection to the PostgreSQL server may timeout if
    # we allow cpuwatch to suspend us.
    if ( $OPTS->{'running_under_cpbackup'} ) {
        $output_obj->out( "Entering timeout safety mode for PostgreSQL (suspending cpuwatch)\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }
    my $cpuwatch_suspend = Cpanel::CpuWatch::Suspend->new();    # will unsuspend cpuwatch when the object is destroyed

    my $data_ref;
    my $postgresadmin = -e '/usr/local/cpanel/bin/postgresadmin.pl' ? '/usr/local/cpanel/bin/postgresadmin.pl' : '/usr/local/cpanel/bin/postgresadmin';
    try {
        if ( $> != 0 ) {
            $data_ref = $self->run_admin_backupcmd( '/usr/local/cpanel/bin/postgreswrap', 'BACKUPJSON' );
        }
        else {
            $data_ref = $self->_fetch_postgres_backup();
        }

    }
    catch {
        local $@ = $_;
        warn;
    };

    my $pg_active = $data_ref->{'PING'};
    chomp $pg_active if defined $pg_active;

    # define variables if undefined
    for my $k (qw{LISTDBS DUMPSQL_USERS DUMPSQL_GRANTS}) {
        next if defined $data_ref->{$k};
        $data_ref->{$k} = '';
    }

    if ( $pg_active && $pg_active eq 'PONG' ) {
        my @DBS = @{ $data_ref->{'LISTDBS'} };
        $output_obj->out( "Grabbing PostgreSQL databases...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );
        if (@DBS) {    #only fork if we have to
            $self->run_dot_event(
                sub {
                    foreach my $db (@DBS) {
                        $db =~ s/\n//g;
                        if ( $OPTS->{'db_backup_type'} eq 'name' ) {
                            Cpanel::FileUtils::TouchFile::touchfile("$work_dir/psql/$db.tar");
                        }
                        else {
                            $self->simple_exec_into_file(
                                "$work_dir/psql/$db.tar",
                                (
                                    $> == 0

                                      #TODO: This could just invoke Cpanel::PostgresAdmin .. ?
                                    ? [ $postgresadmin, $uid, 'PGDUMP', $db, $OPTS->{'db_backup_type'} ]
                                    : [ '/usr/local/cpanel/bin/postgreswrap', 'PGDUMP', $db, $OPTS->{'db_backup_type'} ]
                                )
                            );
                        }
                        if ( !-e "$work_dir/psql/$db.tar" ) {
                            Cpanel::Logger::warn("Unable to write archive: $!");
                        }
                    }
                },
            );
        }
        $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

        $output_obj->out( "Grabbing PostgreSQL privileges...", @Cpanel::Pkgacct::PARTIAL_TIMESTAMP );
        Cpanel::FileUtils::Write::overwrite( "$work_dir/psql_users.sql",  join( '', @{ $data_ref->{'DUMPSQL_USERS'} } ),  0600 );
        Cpanel::FileUtils::Write::overwrite( "$work_dir/psql_grants.sql", join( '', @{ $data_ref->{'DUMPSQL_GRANTS'} } ), 0600 );
        $output_obj->out( "Done\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }

    if ( $OPTS->{'running_under_cpbackup'} ) {
        $output_obj->out( "Leaving timeout safety mode for PostgreSQL (suspending cpuwatch)\n", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
    }

    return 1;
}

sub _fetch_postgres_backup {
    my ($self) = @_;
    my $user   = $self->get_user();
    my $cpconf = $self->get_cpconf();
    my $ob     = Cpanel::PostgresAdmin::Basic->new( { 'cpconf' => $cpconf, 'cpuser' => $user, 'ERRORS_TO_STDOUT' => 1 } );
    return Cpanel::PostgresAdmin::Backup::fetch_backup_as_hr($ob);
}

1;
