package Cpanel::MysqlUtils::Dump;

# cpanel - Cpanel/MysqlUtils/Dump.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Dump

=cut

use Try::Tiny;

use Cpanel::CachedCommand                           ();
use Cpanel::Config::Constants::MySQL                ();
use Cpanel::Context                                 ();
use Cpanel::DbUtils                                 ();
use Cpanel::Exception                               ();
use Cpanel::Mysql::Constants                        ();    ## PPI NO PARSE - mis-parse
use Cpanel::MysqlUtils::Version                     ();
use Cpanel::IOCallbackWriteLine                     ();
use Cpanel::Try                                     ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();

=head1 FUNCTIONS

=cut

# This is ER_CANT_AGGREGATE_NCOLLATIONS, which in English comes out as
# “Illegal mix of collations for operation '%s'”. Ideally we’d look for
# something more than this pattern, but we can’t be sure the description
# will be in English, and “ER_CANT_AGGREGATE_NCOLLATIONS” won’t be part
# of the output.  We also need to match “ER_CANT_AGGREGATE_3COLLATIONS”
#
my $MYSQL_ILLEGAL_COLLATIONS_ERROR_STRING_REGEX = '\(127[01]';

my %minimum_version = (

    #https://dev.mysql.com/doc/refman/5.1/en/mysqldump.html
    '--events'   => '5.1.8',
    '--routines' => '5.1.2',

    #This is actually on by default, but hey.
    #https://dev.mysql.com/doc/refman/5.0/en/mysqldump.html#option_mysqldump_triggers
    '--triggers' => '5.0.11',

    # If we ever change the --default-character-set=
    # arg Cpanel::Pkgacct::Components::Mysql::_set_default_char_set_utf8
    # will likely need to be modified
    '--default-character-set=utf8mb4' => '5.5.3',
);

#returns a three-number version, or undef if it can't be determined
sub mysqldump_version {
    my $mysqldump    = Cpanel::DbUtils::find_mysqldump();
    my $version_line = Cpanel::CachedCommand::cachedcommand( $mysqldump, '-V' );

    return if $version_line !~ /(\d+\.\d+\.\d+)/;

    return $1;
}

#for testing
*_mysqldump_version = \&mysqldump_version;

#returns a list
sub get_flags_for_account_backup {
    Cpanel::Context::must_be_list();

    my $dump_version = _mysqldump_version();

    my @flags;

    for my $flag ( keys %minimum_version ) {
        my $min_version = $minimum_version{$flag};
        if ( Cpanel::MysqlUtils::Version::cmp_versions( $dump_version, $min_version ) >= 0 ) {
            push @flags, $flag;
        }
    }

    @flags = sort @flags;

    return @flags;
}

=head2 dump_database_schema( $DBNAME )

Return the MySQL commands to recreate $DBNAME’s schema in a text blob.

=cut

sub dump_database_schema {
    my ($dbname) = @_;

    my $ret;

    Cpanel::Try::try(
        sub { $ret = _dump_database_schema_with_encoding( $dbname, 'utf8mb4' ) },
        'Cpanel::Exception::Database::MysqlIllegalCollations' => sub {
            $ret = _dump_database_schema_with_encoding( $dbname, 'utf8' );
        },
    );

    return $ret;
}

sub _dump_database_schema_with_encoding {
    my ( $dbname, $encoding ) = @_;

    my $run = _run_mysqldump(
        $encoding,
        [
            '--skip-triggers',
            '--no-data',
            '--no-create-info',
            '--databases',
            '--',
            $dbname,
        ],
        [],
    );

    return $run->stdout();
}

=head2 stream_database_data_utf8mb4( $OUT_FH, $DBNAME )

Attempts to write the SQL commands to recreate $DBNAME’s
data to $OUT_FH, with C<utf8mb4> as MySQL’s default encoding.

Exceptions will be thrown as from L<Cpanel::SafeRun::Object>,
though collation errors will be thrown as
L<Cpanel::Exception::Database::MysqlIllegalCollations> instances.

=cut

sub stream_database_data_utf8mb4 {
    my ( $out_fh, $dbname ) = @_;

    return _stream_database_data( $out_fh, $dbname, 'utf8mb4' );
}

#----------------------------------------------------------------------

=head2 stream_database_data_utf8( $OUT_FH, $DBNAME )

Like C<stream_database_data_utf8mb4()> but uses MySQL C<utf8> instead
of C<utf8mb4>.

=cut

sub stream_database_data_utf8 {
    my ( $out_fh, $dbname ) = @_;

    return _stream_database_data( $out_fh, $dbname, 'utf8' );
}

#----------------------------------------------------------------------

=head2 stream_database_nodata_utf8mb4( $OUT_FH, $DBNAME )

Like C<stream_database_data_utf8mb4()> but omits the database data.
(It includes the routines, events, triggers, and views.)

=cut

sub stream_database_nodata_utf8mb4 {
    my ( $out_fh, $dbname ) = @_;

    return _stream_database_data( $out_fh, $dbname, 'utf8mb4', '--no-data' );
}

#----------------------------------------------------------------------

=head2 stream_database_nodata_utf8( $OUT_FH, $DBNAME )

Like C<stream_database_data_utf8()> but omits the database data.
(It includes the routines, events, triggers, and views.)

=cut

sub stream_database_nodata_utf8 {
    my ( $out_fh, $dbname ) = @_;

    return _stream_database_data( $out_fh, $dbname, 'utf8', '--no-data' );
}

#----------------------------------------------------------------------

sub _stream_database_data {
    my ( $out_fh, $dbname, $encoding, @opts ) = @_;

    die "Need DB name!" if !length $dbname;

    # Hopefully this won't buffer too much...
    my $filter_fh = Cpanel::IOCallbackWriteLine->new(
        sub {
            print {$out_fh} $_[0] unless $_[0] =~ /^USE \`?\Q$dbname\E\`?;$/;
        }
    );

    _run_mysqldump(
        $encoding,
        [
            '--routines',
            '--events',
            '--triggers',    # on by default, but just for consistency
            @opts,
            '--no-create-db',
            '--databases',
            '--force',
            '--',
            $dbname,
        ],
        [
            stdout => $filter_fh,
        ],
    );

    return;
}

sub _mysqldump_bin {
    require Cpanel::DbUtils;
    return Cpanel::DbUtils::find_mysqldump();
}

sub _run_mysqldump {
    my ( $encoding, $args_ar, $run_opts_ar ) = @_;

    my $bin = _mysqldump_bin() or die "Can’t find mysqldump!\n";

    require Cpanel::SafeRun::Object;

    my $run;

    try {

        if ( Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->is_active_profile_cpcloud() ) {
            my @cpcloud_args = qw{
              --set-gtid-purged=OFF
              --skip-generated-invisible-primary-key=ON
            };
            unshift( $args_ar->@*, @cpcloud_args );
        }

        $run = Cpanel::SafeRun::Object->new_or_die(
            program      => $bin,
            timeout      => 86400,                                                  # 24 hours
            read_timeout => $Cpanel::Config::Constants::MySQL::TIMEOUT_MYSQLDUMP,
            args         => [
                '--complete-insert',
                '--quote-names',
                '--force',
                '--quick',
                '--single-transaction',

                "--default-character-set=$encoding",

                '--max-allowed-packet=' . Cpanel::Mysql::Constants::MAX_ALLOWED_PACKET,

                @$args_ar,
            ],
            @$run_opts_ar,
        );
    }
    catch {
        my $err = $_->get('stderr');

        if ( $err =~ m<$MYSQL_ILLEGAL_COLLATIONS_ERROR_STRING_REGEX>o ) {
            die Cpanel::Exception::create_raw(
                'Database::MysqlIllegalCollations',
                "collations error: $err",
            );
        }

        local $@ = $_;
        die;
    };

    return $run;
}

1;
