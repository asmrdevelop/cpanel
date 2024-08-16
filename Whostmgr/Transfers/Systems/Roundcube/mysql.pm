package Whostmgr::Transfers::Systems::Roundcube::mysql;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.
use cPstrict;

use Try::Tiny;

use Cpanel::Autodie               ();
use Cpanel::Email::RoundCube      ();
use Cpanel::Email::RoundCube::DBI ();
use Cpanel::Exception             ();
use Cpanel::FileUtils::Read       ();
use Cpanel::LoadFile              ();
use Cpanel::Rand::Get             ();
use Cpanel::SafeRun::Errors       ();
use Cpanel::Services::Enabled     ();

my $EARLIEST_CPANEL_ROUNDCUBE_VERSION = '0.2b';
my $DB_NAME                           = 'roundcube';
my $DB_USER                           = 'roundcube';

sub do_restore ( $self, $cpconf_ref ) {
    my $src_version;

    my $extractdir         = $self->extractdir();
    my $rcube_version_file = "$extractdir/meta/rcube_version";
    if ( -s $rcube_version_file ) {
        $src_version = Cpanel::LoadFile::loadfile($rcube_version_file) or do {
            return ( 0, $self->_locale()->maketext( 'The system cannot determine the archive’s [output,asis,Roundcube] database schema version because the system failed to load the file “[_1]” because of an error: [_2]', $rcube_version_file, $! ) );
        };
    }
    else {
        $src_version = $EARLIEST_CPANEL_ROUNDCUBE_VERSION;
    }

    # Make sure any Roundcube SQLite dbs that may already exist in the user's homedir are upgraded
    if ( exists $cpconf_ref->{'roundcube_db'} && $cpconf_ref->{'roundcube_db'} eq 'sqlite' ) {

        # This situation can happen if the user had been on a SQLite roundcube server before the MySQL Roundcube server we're transferring them from
        # And if that user didn't do anything on the MySQL Roundcube server (thus not passing the 50 byte test below for the sql file) their SQLite files may be out of date
        _upgrade_sqlite_files_in_homedir($self);
    }

    my $sql_file = $self->_archive_mysql_dir() . "/$DB_NAME.sql";

    ## case 52397: possible that transferred user never used Roundcube; the roundcube.sql, per
    ##   pkgacct, will consist of '...place holder file' (a 40 byte file); safe to assume an
    ##   roundcube.sql file smaller than 50 bytes does not contain a working account
    return 1 if !Cpanel::Autodie::exists($sql_file);
    return 1 if ( -s _ ) < 50;

    Cpanel::Autodie::open( my $sql_fh, '<', $sql_file );

    ## case 98425: there was a bug in incremental backups when a user did not log into roundcube,
    ##   they would get multiple '...place holder file' messages in their roundcube.sql. This would
    ##   bring the total filesize above the check preceeding this one from case 52397.
    my ( $ok, $contains_non_dash_dash_lines, $err );
    try {
        $contains_non_dash_dash_lines = _file_contains_non_dash_dash_lines($sql_file);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return (
            0,
            $self->_locale()->maketext( 'The system failed to open the [output,asis,Roundcube] restore file due to an error: [_1]', Cpanel::Exception::get_string($err) )
        );
    }

    return 1 if !$contains_non_dash_dash_lines;

    # Wait until we’ve ascertained that the tarball has Roundcube/MySQL
    # data because it’s more useful to report to the user that “the archive
    # contains Roundcube data that won’t be restored” rather than merely
    # that the system has no MySQL.
    if ( !Cpanel::Services::Enabled::is_provided('mysql') ) {
        my $msg = $self->_locale()->maketext("This archive contains [asis,Roundcube] data stored as [asis,MySQL]/[asis,MariaDB] commands, but [asis,MySQL]/[asis,MariaDB] is not configured on this system.");
        $self->{'_utils'}->add_skipped_item($msg);

        return 1;
    }

    # Wait until we’ve ascertained that there is, in fact, MySQL data
    # to restore before we initialize the MySQL variables.
    $self->_init_self_variables();

    my ( $temp_ok, $temp_dbname ) = _get_temp_dbname($self);

    if ( !$temp_ok ) {
        my $err = "Unable to create temporary Roundcube database: $temp_dbname";
        $self->warn($err);
        return ( 0, $err );
    }

    $self->{'_dbname_updates'} = {
        $DB_NAME => $temp_dbname,
    };

    $self->out( $self->_locale()->maketext( "The system will create a temporary database named “[_1]” to import the [asis,Roundcube] data.", $temp_dbname ) );

    ( $ok, $err ) = $self->_create_db_and_import_as_newuser_from_fh(
        {
            name     => $temp_dbname,
            old_name => $DB_NAME,
            sql_fh   => $sql_fh,
        }
    );
    return ( 0, $err ) if !$ok;

    $self->out( $self->_locale()->maketext( "Merging grants from the temporary database named “[_1]” into [output,asis,Roundcube] …", $temp_dbname ) );
    my ($dest_version) = Cpanel::Email::RoundCube::get_cached_version();

    ( $ok, $err ) = Cpanel::Email::RoundCube::handle_mysql_roundcube_grants(
        $temp_dbname,
        $self->dbh_with_root_privs(),
    );
    return ( 0, $err ) if !$ok;

    if ( $src_version ne $dest_version ) {
        $self->out( $self->_locale()->maketext( "Upgrading [output,asis,Roundcube] data from “[_1]” to “[_2]” …", $src_version, $dest_version ) );
        my ( $roundcube_dbh, $err );

        try {
            $roundcube_dbh = $self->dbh_with_root_privs()->clone(
                {
                    database          => $temp_dbname,
                    Username          => $DB_USER,
                    Password          => scalar Cpanel::Email::RoundCube::get_roundcube_password(),
                    mysql_enable_utf8 => 1,
                }
            );
        }
        catch {
            $err = $_;
        };

        if ($err) {
            return (
                0,
                $self->_locale()->maketext( "The system failed to connect to the Roundcube data on the MySQL server as the user “[_1]” because of an error: [_2]", $DB_USER, Cpanel::Exception::get_string($err) )
            );
        }
        local $@;
        my $update_ok = Cpanel::Email::RoundCube::DBI::ensure_schema_update(
            $roundcube_dbh,
            'mysql',
            $dest_version,
            { installed_version => $src_version },
        );

        try {
            # case 106345:
            # libmariadb has been patched to send
            # and receive with MSG_NOSIGNAL
            # thus avoiding the need to trap SIGPIPE
            # on disconnect which can not be reliably
            # done in perl because perl will overwrite
            # a signal handler that was done outside
            # of perl and fail to restore a localized
            # one.

            $roundcube_dbh->disconnect();
        };

        # No need to catch disconnect errors here
        # as we do not care if a disconnect fails
        # because it would likely not be useful
        # information, and the object will
        # eventually be destroyed anyways.

        if ( !$update_ok ) {
            return ( 0, 'Roundcube schema update failed. Check system logs.' );
        }
    }

    $self->out( $self->_locale()->maketext( "Merging data from the temporary database named “[_1]” into [output,asis,Roundcube].", $temp_dbname ) );

    try {
        my $roundcube_dbh = $self->dbh_with_root_privs()->clone(
            {
                database          => $temp_dbname,
                Username          => $DB_USER,
                Password          => scalar Cpanel::Email::RoundCube::get_roundcube_password(),
                mysql_enable_utf8 => 1,
            }
        );

        ## handle case where source is mysql and dest is sqlite
        if ( ( $cpconf_ref->{roundcube_db} ) && ( 'sqlite' eq $cpconf_ref->{roundcube_db} ) ) {
            $self->out( $self->_locale()->maketext( "Converting [output,asis,Roundcube] data to [output,asis,sqlite] format.", $temp_dbname ) );
            ## note: future location of Case 16846; post process Roundcube MySQL when the username has changed

            #MYSQLADMIN
            _mysql_to_sqlite_conversion( $self, $temp_dbname );

            # case 106345:
            # libmariadb has been patched to send
            # and receive with MSG_NOSIGNAL
            # thus avoiding the need to trap SIGPIPE
            # on disconnect which can not be reliably
            # done in perl because perl will overwrite
            # a signal handler that was done outside
            # of perl and fail to restore a localized
            # one.
            $roundcube_dbh->disconnect();
        }
        else {
            $self->out( $self->_locale()->maketext("Resolving [output,asis,Roundcube] uids.") );

            #MYSQLADMIN
            require 'scripts/xfer_rcube_uid_resolver.pl';    ## no critic (RequireBarewordIncludes)
            scripts::xfer_rcube_uid_resolver::do_resolution(
                $roundcube_dbh,
                $temp_dbname,
                $self->{'_utils'}->local_username(),
                $self->{'_utils'}->original_username()
            );
        }
    }
    catch {
        $self->warn( $self->_locale()->maketext( 'Failed to merge temporary database named “[_1]” into [output,asis,Roundcube]: [_2]', $temp_dbname, Cpanel::Exception::get_string($_) ) );
    };

    $self->out( $self->_locale()->maketext( "Dropping the temporary database named “[_1]”.", $temp_dbname ) );
    try {
        $self->dbh_with_root_privs()->do( 'DROP DATABASE ' . $self->dbh_with_root_privs()->quote_identifier($temp_dbname) );
    }
    catch {
        $self->warn( $self->_locale()->maketext( 'The system failed to delete the temporary database “[_1]” because of an error: [_2]', $temp_dbname, $self->dbh_with_root_privs()->errstr() ) );
    };

    return 1;
}

# Description:
#   Performs the MySQL to SQLite roundcube conversion. This is broken out
#   into a separate function so that the tests may use the modulino to
#   allow the conversion script to play nice with our testing environment.
#
# Arguments:
#   $self - This class.
#   $temp_dbname - The temporary roundcube database created for conversion.
#
# Exceptions:
#   None at present.
#
# Returns:
#   An array of all the output of the conversion script.
#
sub _mysql_to_sqlite_conversion ( $self, $temp_dbname ) {

    #MYSQLADMIN
    # This is what the test file will use
    # require 'scripts/convert_roundcube_mysql2sqlite';    ## no critic (RequireBarewordIncludes)
    # Script::RCube::Mysql2Sqlite->script( $self->newuser(), $temp_dbname );
    my @output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/convert_roundcube_mysql2sqlite', $self->newuser(), $temp_dbname );
    return @output;
}

sub _upgrade_sqlite_files_in_homedir ($self) {
    my @output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/bin/update-roundcube-sqlite-db', '--foreground', '--user', $self->newuser() );
    return @output;
}

sub _get_temp_dbname ($self) {
    my $temp_dbname;
    my $cnt = 10;

    while ( $cnt-- ) {
        my $rand        = Cpanel::Rand::Get::getranddata( 16, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );    # Avoid '_'
        my $_try_dbname = sprintf( "cptmpdb_%s_%s", $self->newuser(), $rand );

        if ( !$self->mysql_obj_with_root_privs()->db_exists($_try_dbname) ) {
            $temp_dbname = $_try_dbname;
            last;
        }
    }

    if ( !$temp_dbname ) {
        return ( 0, "The system could not find an unused name for a temporary database." );
    }

    return ( 1, $temp_dbname );
}

# Description:
# Tries to determine if the passed in file contains lines that do not
# start with '-- '. This does not check for ALL comment types, just the one we may add.
# Please be aware of that if this function is ever repackaged.
#
# Arguments:
#   $dbfile - the full path to the sql file
#
# Exceptions:
#   Cpanel::Exception::IO::FileNotFound   - Thrown if the file was not found
#   Cpanel::Exception::IO::FileOpenError  - Thrown if there was an error opening the file
#   Cpanel::Exception::IO::FileCloseError - Thrown if there was an error closing the file
#
# Returns:
#   A integer representing a boolean value that indicates if the file contains non whitespace
#   lines that do not begin with '-- '.
#
sub _file_contains_non_dash_dash_lines ($dbfile) {
    return 0 if !-f $dbfile || ( -s _ ) == 0;

    my $found_non_whitespace_non_dash_dash_line = 0;
    Cpanel::FileUtils::Read::for_each_line(
        $dbfile,
        sub {
            my ($obj) = @_;
            my $line = $_;
            return if $line =~ /^[ \t]*[-]{2} /;
            return if $line =~ /^\s*$/;
            $found_non_whitespace_non_dash_dash_line = 1;
            $obj->stop();
        }
    );

    return $found_non_whitespace_non_dash_dash_line;
}

1;
