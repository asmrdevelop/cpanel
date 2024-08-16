package Cpanel::MysqlUtils::Diff;

# cpanel - Cpanel/MysqlUtils/Diff.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::MysqlUtils::MyCnf::Basic     ();
use Cpanel::MysqlUtils::MyCnf::Serialize ();
use Cpanel::Binaries                     ();
use Cpanel::Exception                    ();
use Cpanel::SafeRun::Object              ();
use Cpanel::TempFile                     ();
use Cpanel::Transaction::File::Raw       ();

# Constants
our $NO_DROP_TABLE    = 0;
our $ALLOW_DROP_TABLE = 1;

sub mysqldiff {
    my ( $existing_db, $sql_file, $table_regex, $socket, $password, $force ) = @_;

    return _mysqldiff_return( _mysqldiff( $existing_db, $sql_file, $table_regex, $socket, $password, $force ) );
}

sub mysqldiff_no_drop_column {
    my ( $existing_db, $sql_file, $table_regex, $socket, $password ) = @_;

    my $diff_r = _mysqldiff( $existing_db, $sql_file, $table_regex, $socket, $password );

    # Prevent columns from being dropped.
    # This is useful in case a database is shared between multiple remotes.
    my $drop_col_re = qr<\n[\t ]*ALTER[\t ]TABLE.*DROP[\t ]COLUMN>si;
    if ( $$diff_r =~ $drop_col_re ) {
        $$diff_r =~ s/$drop_col_re [^\n]*/\n/xgs;
    }

    return _mysqldiff_return($diff_r);
}

sub _mysqldiff_return {
    my ($diff_r) = @_;

    # Remove comments
    $$diff_r =~ s/^\s*#.*//mg;

    # Trim
    $$diff_r =~ s<\A\s+><>;
    $$diff_r =~ s<\s+\z><>;

    return if !length $$diff_r;
    return $$diff_r;
}

sub _mysqldiff {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $existing_db, $sql_file, $table_regex, $socket, $password, $force ) = @_;

    if ( $> != 0 ) {
        die "mysqldiff may only be run as root with this module.";
    }

    if ( !-s $sql_file ) {    #NB: -z means "exists and is empty"
        die "The source SQL file “$sql_file” does not exist or is empty.";
    }

    my $mysqlhost = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';

    my ( $temp_file_obj, $fake_homedir ) = _create_temp_my_cnf( $socket, $password );

    my $diff_run = Cpanel::SafeRun::Object->new(
        program     => Cpanel::Binaries::path('mysqldiff'),
        before_exec => sub {
            if ($socket) { $ENV{'HOME'} = $fake_homedir; }
        },
        args => [
            ( $table_regex ? ( '--table-re' => $table_regex ) : () ),
            "db:$existing_db",
            $sql_file,
        ],
    );

    if ( $diff_run->CHILD_ERROR() ) {
        die "mysqldiff failed: " . $diff_run->autopsy() . "\nOutput was: " . $diff_run->stderr();
    }

    my $stdout_r = $diff_run->stdout_r();

    if ( $$stdout_r =~ m/\n[\t ]*DROP/is && !$force ) {
        die "mysqldiff told us to drop a table: $$stdout_r";
    }

    return $stdout_r;
}

#Returns a temp file object and the homedir.
sub _create_temp_my_cnf {
    my ( $socket, $password ) = @_;

    my $temp_file_obj = Cpanel::TempFile->new();
    my $fake_homedir  = $temp_file_obj->dir();

    my $my_cnf_str = Cpanel::MysqlUtils::MyCnf::Serialize::serialize(
        {
            client => {
                ( $socket            ? ( socket   => $socket )   : () ),
                ( defined($password) ? ( password => $password ) : () ),
            }
        }
    );

    local $!;

    my $xaction = Cpanel::Transaction::File::Raw->new(
        path => "$fake_homedir/.my.cnf",
    );

    $xaction->set_data( \$my_cnf_str );

    my ( $ok, $err ) = $xaction->save_and_close();
    die Cpanel::Exception->create_raw($err) if !$ok;

    return ( $temp_file_obj, $fake_homedir );
}

1;
