package Cpanel::MysqlUtils::Version;

# cpanel - Cpanel/MysqlUtils/Version.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

#NOTE: Don’t use JSON here, even to lazy-load, because CpConfGuard pulls in
#this module, and CpConfGuard is specifically trying to avoid loading JSON.

use Cpanel::Exception                ();
use Cpanel::LoadFile                 ();
use Cpanel::LoadModule               ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MariaDB                  ();

our $cached_mysql_version;

# These must be strings or the "8.0" will be truncated to "8".
our $MINIMUM_RECOMMENDED_MYSQL_RELEASE   = '8.0';
our $MINIMUM_RECOMMENDED_MARIADB_RELEASE = '10.5';

our $DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED = $MINIMUM_RECOMMENDED_MYSQL_RELEASE;    # assume MySQL 5.7 is the default value
our $USE_LOCAL_MYSQL                              = 0;

#Allow to be overridden in tests
our $_VERSION_CACHE_PATH = '/var/cpanel/mysql_server_version_cache';

my $VERSION_CACHE_TTL = 4 * 60 * 60;                                                       #4 hours

=head1 NAME

Cpanel::MysqlUtils::Version - Find and compare MySQL server version

=head1 METHODS

=cut

#Returns -1, 0, or 1 (same conditions as Perl's <=> and cmp operators).
#NOTE: Trying to remember what -1 and 1 mean? Look at is_at_least().
sub cmp_versions ( $a, $b ) {
    for my $orig ( $a, $b ) {
        my $copy = $orig;
        for ($copy) {
            s<-.*><>;    #strip suffixes
            if ( !length || tr<0-9.><>c || m<\.\.> || m<\A\.> || m<\.\z> ) {
                die "Invalid MySQL version: “$orig”";
            }
        }

        $orig = $copy;
    }

    my ( $a_ar, $b_ar ) = map { [ split m<[.-]> ] } ( $a, $b );
    die "Uneven version numbers: $a, $b" if @$a_ar != @$b_ar;

    push @$_, (0) x 4 for ( $a_ar, $b_ar );

    ( $a, $b ) = map { join( '.', @{$_}[ 0 .. 3 ] ) } $a_ar, $b_ar;    ## no critic qw(Variables::RequireLocalizedPunctuationVar)

    Cpanel::LoadModule::load_perl_module('Cpanel::Version::Compare');
    return Cpanel::Version::Compare::cmp_versions( $a, $b );
}

#This is a bit more forgiving than cmp_versions();
#it "fills in the blanks" for uneven comparisons.
sub is_at_least ( $testee, $minimum ) {
    for ( $testee, $minimum ) {
        $_ = _expand_mysql_version($_);
    }

    return ( cmp_versions( $testee, $minimum ) >= 0 ) ? 1 : 0;
}

#
# This differs slightly from Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default()
# as it does not return the default version if no version is obtained
#
#NOTE: Only root can call this.
#
#  Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default MUST NOT generate an exception
#  Cpanel::MysqlUtils::Version::mysqlversion MAY generate an exception
#
#  See cases CPANEL-1956, CPANEL-3265, CPANEL-3458 for what
#  happens if this is not followed
#
sub mysqlversion {
    return $cached_mysql_version ||= current_mysql_version()->{'short'};
}

sub uncached_mysqlversion {
    undef $cached_mysql_version;

    unlink $_VERSION_CACHE_PATH;

    return mysqlversion();
}

#Caches the version requests so we don’t lag when MySQL is slow or
#unduly bog down the MySQL server.
#
#Returns a hashref of:
#
#   host        - string, the MySQL server hostname
#   is_remote   - 0/1, whether “host” is a remote server
#   full        - the full version string   - ex. 5.5.23-abc
#   long        - numbers/dots only         - ex. 5.5.23
#   short       - major/minor only          - ex. 5.5
#
sub current_mysql_version {
    my ($host) = @_;

    $host = 'localhost'                   if $USE_LOCAL_MYSQL;
    $host = _getmydbhost() || 'localhost' if !$host;

    if ($>) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("Only run as root!") if $>;
    }

    my $is_remote = Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql($host);

    my ( $version_string, $maj, $min, $pt );

    if ( ( -s $_VERSION_CACHE_PATH ) && ( ( stat _ )[9] > ( time - $VERSION_CACHE_TTL ) ) ) {
        try {
            ( my $cache_host, $version_string ) = _load_cache_file();

            if ( $version_string && $cache_host eq $host ) {
                try {
                    ( $maj, $min, $pt ) = _split_mysql_version($version_string);
                }
                catch {
                    warn "Invalid MySQL version cache: “$version_string”";
                };
            }
        }
        catch {
            warn "Failed to read “$_VERSION_CACHE_PATH”: " . $_->to_string();
        };
    }

    if ( !$maj ) {
        undef $version_string;
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Unprivileged');

        try {
            $version_string = Cpanel::MysqlUtils::Unprivileged::get_version_from_host($host);
        }

        #DB server can’t be reached by socket, hm?
        catch {
            my $exc = $_;
            local $@ = $exc;

            #Well, if the server’s remote, there’s nothing more to do.
            die if $is_remote;
        };

        # An exception may not have been thrown upon failure to get the
        # version, and local version tests are not valid for a remote server
        if ( !$version_string && $is_remote ) {
            die Cpanel::Exception->create( 'The system failed to determine the “[_1]” version on remote host “[_2]”.', [ 'mysqld', $host ] );
        }

        if ( !$version_string ) {

            #If the server is local, though,
            #then we can try the old-fashioned way of fork()/exec().

            #NOTE: Should we warn() about the failed socket connection?
            #Something else will almost certainly scream about it …

            Cpanel::LoadModule::load_perl_module('Cpanel::DbUtils');
            if ( my $mysqld_bin = Cpanel::DbUtils::find_mysqld() ) {

                Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
                my $run = Cpanel::SafeRun::Object->new_or_die(
                    program => $mysqld_bin,
                    args    => ['--version'],
                );

                if ( $run->stdout() =~ m<\A\S+mysqld[^0-9]+([0-9]+\.[0-9]+\.[0-9]+(?:-\S+)?)> ) {
                    $version_string = $1;
                }
            }
        }

        $version_string ||= get_version_from_frm_files();
        $version_string ||= get_version_from_mysql_upgrade_info();

        if ( !$version_string ) {
            die Cpanel::Exception->create( 'The system failed to determine the “[_1]” version.', ['mysqld'] );
        }

        ( $maj, $min, $pt ) = _split_mysql_version($version_string);

        try {
            require Cpanel::FileUtils::Write;
            Cpanel::FileUtils::Write::overwrite( $_VERSION_CACHE_PATH, "$host\n$version_string" );
        }
        catch {
            warn $_;
        };
    }

    return {
        host      => $host,
        is_remote => $is_remote ? 1 : 0,
        full      => $version_string,
        long      => "$maj.$min.$pt",
        short     => "$maj.$min",
    };
}

sub get_short_mysql_version_from_data_files {
    my $version = get_version_from_frm_files() || get_version_from_mysql_upgrade_info();
    if ( length $version ) {
        my ( $maj, $min, $pt ) = _split_mysql_version($version);
        return "$maj.$min";
    }
    return undef;
}

sub get_version_from_mysql_upgrade_info {
    my $mysql_dir = _mysql_data_dir() or return undef;

    my $contents = Cpanel::LoadFile::loadfile("$mysql_dir/mysql_upgrade_info");

    # Occasionally there is a trailing NUL byte in this file’s contents.
    # We aren’t sure of the pattern.
    $contents =~ tr{\0}{}d if length $contents;

    return $contents;
}

sub get_version_from_frm_files {
    my $mysql_dir = _mysql_data_dir() or return undef;
    my $newest_mysql_version_id;
    foreach my $potential_file (qw(user table_stats slow_log column_stats db)) {
        my $contents = Cpanel::LoadFile::loadfile("$mysql_dir/mysql/${potential_file}.frm")
          or next;

        # cannot trust 0x0033 for MariaDB
        if ( $contents =~ qr{^mariadb-version=(\d{4,})}mai ) {
            return mysql_version_id_to_version("$1");
        }

        my $MYSQL_VERSION_ID = unpack( 'L', substr( $contents, 0x0033, 4 ) );    # see https://dev.mysql.com/doc/internals/en/frm-file-format.html
        if ( !$newest_mysql_version_id || $MYSQL_VERSION_ID gt $newest_mysql_version_id ) {
            $newest_mysql_version_id = $MYSQL_VERSION_ID;
        }
    }

    return undef if !$newest_mysql_version_id;
    return mysql_version_id_to_version($newest_mysql_version_id);
}

sub mysql_version_id_to_version ( $newest_mysql_version_id, $limit = 3 ) {
    my @VERSION;

    while ( length $newest_mysql_version_id ) {
        unshift @VERSION, int substr( $newest_mysql_version_id, -2, 2, '' );
    }

    # trim the first significant digits
    if ( $limit > 0 && scalar @VERSION > $limit ) {
        splice( @VERSION, $limit );
    }

    return join( '.', @VERSION );
}

#NOTE: converts MySQL version strings to numbers, of the format
#given by DBD::mysql mysql_serverversion.
sub string_to_number ($version) {
    my ( $maj, $min, $pt ) = _split_mysql_version($version);

    return 0 + sprintf( "%d%02d%02d", $maj, $min || 0, $pt || 0 );
}

# Just like is_at_least, except do a vendor check as well.
# Vendor is either 'mysql' or 'mariadb'.
sub is_at_least_version_and_of_vendor ( $testee, $minimum, $vendor ) {
    $vendor = lc($vendor);
    die "Unknown vendor: $vendor" if !grep { $_ eq $vendor } qw{mysql mariadb};

    require Cpanel::MysqlUtils::Version;
    require Cpanel::MariaDB;

    # TODO -- using the version to determine vendor is not future proof.
    # At some point MySQL will have a 10.x. Then we'll need to check vendor
    # in some other manner.
    my $installed_vendor = Cpanel::MariaDB::version_is_mariadb($testee) ? 'mariadb' : 'mysql';
    return Cpanel::MysqlUtils::Version::is_at_least( $testee, $minimum ) && $vendor eq $installed_vendor;
}

sub version_is_mysql {

    # MySQL may not be installed when this is called -- CPANEL-32652.
    # If getting the version fails, it is ok. Just assume you are on mysql
    # in that doomed state.
    my $version;
    try { $version = mysqlversion() };
    return !Cpanel::MariaDB::version_is_mariadb($version) if $version;
    return 'mysql';
}

=head2 version_dispatch

A simple dispatch table which runs some given code depending on the installed MySQL version.

=over 2

=item Input

=over 3

=item C<HASH>

A hash containing a dispatch table for which the keys are MySQL "short" version numbers and the values are anonymous subroutines or coderefs.

C<< version_dispatch('5.5' => sub {return}) >>

C<< version_dispatch('5.5' => $coderef) >>

=back

=item Output

=over 3

=item The return(s) of the dispatched coderef.

=back

=back

=cut

sub version_dispatch (%table) {
    my $version  = current_mysql_version()->{'short'};
    my $dispatch = $table{$version};

    return unless $dispatch;

    if ( ref($dispatch) eq 'CODE' ) {
        return $dispatch->();
    }
    else {
        return $table{$dispatch}->();
    }
}

=head2 get_mysql_version_with_fallback_to_default

Returns the current installed mysql version. If the version
cannot be determined, we return the default version.

 This differs slightly from Cpanel::MysqlUtils::Version::mysqlversion()
 as it returns the default version for legacy compatibility.

  Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default MUST NOT generate an exception
  Cpanel::MysqlUtils::Version::mysqlversion MAY generate an exception

See cases CPANEL-1956, CPANEL-3265, CPANEL-3458 for what
happens if this is not followed

=over 2

=item Input

None

=item Output

=over 3

=item C<SCALAR>

    The currently installed mysql version or the default guessed version.

=back

=back

=cut

sub get_mysql_version_with_fallback_to_default {
    local $@;
    return (
        eval { mysqlversion() }                               #
          || get_short_mysql_version_from_data_files()        #
          || $DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED    #
    );
}

=head2 get_local_mysql_version_with_fallback_to_default

Returns the current locally installed mysql version. If the version
cannot be determined, we return the default version.

This differs slightly from Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default()
as it will specifically query localhost for the version.

=over 2

=item Input

None

=item Output

=over 3

=item C<SCALAR>

    The currently installed mysql version or the default guessed version.

=back

=back

=cut

sub get_local_mysql_version_with_fallback_to_default {
    local $@;
    my $localhost = eval { current_mysql_version("localhost"); };    # This can die if it fails to connect
    return $localhost ? $localhost->{short} : get_short_mysql_version_from_data_files() || $DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
}

#----------------------------------------------------------------------

*_getmydbhost = \&Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost;

#overridden in tests
sub _load_cache_file {
    my $cache = Cpanel::LoadFile::loadfile($_VERSION_CACHE_PATH);
    return split m<\n>, $cache, 2;                                   #host => version_string
}

sub _split_mysql_version ($version) {

    $version //= '';

    # Some versions of MariaDB may report versions like 5.5.5-10.1.6-MariaDB,
    # which apparently indicates a corresponding MySQL version,
    # *then* the actual MariaDB version.
    # cf. https://mariadb.atlassian.net/browse/MDEV-4088
    if ( $version =~ m/mariadb/i ) {
        if (
            $version =~ m/
                \A[0-9]+
                \.[0-9]+
                (?:\.[0-9]+)?
                -[0-9]+\.
            /x
        ) {
            $version =~ s/
                \A[0-9]+
                \.[0-9]+
                (?:\.[0-9]+)?-
            //x;    # Remove corresponding MySQL version prefix.
        }

        # More recent versions of MariaDB no longer follow the pattern of
        # indicating a corresponding MySQL version.
        # https://mariadb.com/docs/server/ref/mdb/system-variables/version/
        elsif (
            $version =~ m/
                \A[0-9]+
                \.[0-9]+
                \.[0-9]+
                -MariaDB
            /xi
        ) {
            ($version) = split( ':', $version );    # Remove distribution tag if supplied (10.5.22-MariaDB-1:10.5.22+maria~ubu2004)
            $version =~ s/(?<=MariaDB)-.+//gi;      # Remove build/config suffix if supplied (10.1.1-MariaDB-mariadb1precise-log)
        }
    }

    # Percona can report versions like 5.6.16-64.2-56
    my $version_splitter_re = qr<
        \A
        \s*
        ([0-9]+)
        (?:
            \.
            ([0-9]+)
            (?:
                \.
                ([0-9]+)
                (?:
                    -
                    ([0-9a-z\.\-~+]+)
                )?
            )?
        )?
        \s*
        \z
    >xi;

    my ( $major, $minor, $point, $build ) = ( $version =~ m<$version_splitter_re> ) or do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("Invalid version: $version");
    };

    return ( $major, $minor, $point, $build );
}

sub _expand_mysql_version ($version) {
    my ( $major, $minor, $point, $build ) = _split_mysql_version($version);

    $_     ||= 0 for ( $major, $minor, $point );
    $build ||= 'a';

    return "$major.$minor.$point-$build";
}

sub _mysql_data_dir {
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Dir');
    return 'Cpanel::MysqlUtils::Dir'->can('getmysqldir')->();
}

1;
