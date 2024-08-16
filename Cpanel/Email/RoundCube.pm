package Cpanel::Email::RoundCube;

# cpanel - Cpanel/Email/RoundCube.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::ConfigFiles            ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::DbUtils                ();
use Cpanel::Exception              ();
use Cpanel::Fcntl                  ();
use Cpanel::FileUtils::Copy        ();
use Cpanel::FileUtils::Dir         ();
use Cpanel::FileUtils::TouchFile   ();
use Cpanel::LoadFile               ();
use Cpanel::Logger                 ();
use Cpanel::LoadModule             ();
use Cpanel::MysqlUtils::Connect    ();
use Cpanel::MysqlUtils::Grants     ();
use Cpanel::MysqlUtils::Quote      ();
use Cpanel::Path                   ();
use Cpanel::Pkgr                   ();
use Cpanel::Rand::Get              ();
use Cpanel::SafetyBits::Chown      ();
use Cpanel::SafeDir::MK            ();
use Cpanel::FileUtils::Write       ();
use Cpanel::SafeFile               ();
use Cpanel::Database               ();

#Exposed publicly for testing purposes.
our $ROUNDCUBE_DEST_DIR = "$Cpanel::ConfigFiles::CPANEL_ROOT/base/3rdparty/";

#TODO: Remove non-testing references to this variable.
our $ROUNDCUBE_DATA_DIR = '/var/cpanel/roundcube';

my $MAX_ARCHIVES_TO_RETAIN = 6;

use constant PACKAGE_NAME => 'cpanel-roundcubemail';

our $logger = Cpanel::Logger->new();

sub get_version_info {
    my $version_string = get_active_version();
    if ( !$version_string ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess( PACKAGE_NAME . ' package is not installed or there is a problem with it' );
    }
    my ( $version, $release ) = $version_string =~ m/(.+?)-(.+)/;
    return ( $version, $release );
}

sub write_version_file {
    my ( $version, $release ) = get_version_info();
    my $rcube_cpanel_version = "$version-$release";

    my $ok = Cpanel::FileUtils::Write::overwrite_no_exceptions(
        "$ROUNDCUBE_DATA_DIR/version",
        $rcube_cpanel_version,
        0644
    );

    if ( !$ok ) {
        $logger->warn("Failed to write to “$Cpanel::Email::RoundCube::ROUNDCUBE_DATA_DIR/version”: $!");
    }

    return $ok;
}

sub get_stored_version {
    my $version_file = "$ROUNDCUBE_DATA_DIR/version";
    return undef if !-e $version_file;

    local $!;
    my $version = Cpanel::LoadFile::loadfile($version_file);
    if ( !defined($version) && $! ) {
        die Cpanel::Exception->new( 'The system failed to read the file “[_1]” because of an error: [_2]', [ $version_file, $! ] );
    }
    chomp $version;

    return $version;
}

sub _package_version {
    state $package_version = Cpanel::Pkgr::get_package_version(PACKAGE_NAME);

    return $package_version;
}

sub get_cached_version {

    state $version;

    if ( !defined $version ) {
        $version = _package_version();
        if ( defined $version ) {
            ($version) = split( /-/, $version, 2 );
        }
    }

    return $version;
}

sub get_active_version {

    # when the RPM is installing/updating we pass in the version as the installed version will be the previous or unavailable #
    return $ENV{'CPANEL_ROUNDCUBE_INSTALL_VERSION'} if $ENV{'CPANEL_ROUNDCUBE_INSTALL_VERSION'};

    return _package_version();
}

sub is_main_php_file_installed {
    return 1 if !-s "$ROUNDCUBE_DEST_DIR/roundcube/config/main.inc.php";

    return 0;
}

sub init_roundcube_data_dir {
    Cpanel::SafeDir::MK::safemkdir( $ROUNDCUBE_DATA_DIR, 0750 ) or do {
        die Cpanel::Exception->create_raw("mkdir($ROUNDCUBE_DATA_DIR) failed: $!");
    };

    my $rc_uid = ( getpwnam 'cpanelroundcube' )[2];
    my $rc_gid = ( getgrnam 'cpanelroundcube' )[2];

    chown 0, $rc_gid, $ROUNDCUBE_DATA_DIR or do {
        die Cpanel::Exception->create_raw("chown($ROUNDCUBE_DATA_DIR, root, cpanelroundcube) failed: $!");
    };

    my @roundcube_var_dirs = map { "$ROUNDCUBE_DATA_DIR/$_" } qw( tmp log );

    for my $dir (@roundcube_var_dirs) {
        Cpanel::SafeDir::MK::safemkdir( $dir, 0700 ) or do {
            die Cpanel::Exception->create_raw("mkdir($dir) failed: $!");
        };

        chown $rc_uid, $rc_gid, $dir or do {
            die Cpanel::Exception->create_raw("chown($dir) failed: $!");
        };
    }

    return 1;
}

sub _get_roundcube_config_mysql {
    my ($dbh) = @_;

    my $roundcubepass = Cpanel::Email::RoundCube::get_roundcube_password();
    $roundcubepass = _escape_dsn_part_for_mdb2($roundcubepass);

    my ( $mysql_host, $mysql_port );

    #Prefer the socket notation, for clarity.
    my $socket = $dbh->attributes()->{'mysql_socket'};
    if ($socket) {
        $mysql_host = _escape_dsn_part_for_mdb2($socket);
        $mysql_host = "unix($mysql_host)";
    }
    else {
        $mysql_host = $dbh->attributes()->{'host'};
        $mysql_port = $dbh->attributes()->{'port'};
        $mysql_host = _escape_dsn_part_for_mdb2($mysql_host);
    }

    #NOTE: Would it be worthwhile to pass in the socket here instead?
    return {
        'mysql' => {
            '__db_dsnw__'        => "'mysql://roundcube:$roundcubepass\@$mysql_host" . ( defined $mysql_port ? ":$mysql_port" : "" ) . "/roundcube'",
            '__default_host__'   => q{'localhost'},
            '__smtp_server__'    => q{'localhost'},
            '__smtp_user__'      => q{'%u'},
            '__smtp_pass__'      => q{'%p'},
            '__smtp_auth_type__' => q{'LOGIN'},
            '__temp_dir__'       => "'$ROUNDCUBE_DATA_DIR/tmp'",
            '__log_dir__'        => "'$ROUNDCUBE_DATA_DIR/log'",
        },
    };
}

sub generate_roundcube_config_mysql {
    my ( $DIR, $dbh ) = @_;
    my $TEMPVARS = _get_roundcube_config_mysql($dbh);
    return _generate_roundcube_config( $DIR, $TEMPVARS, 'mysql' );
}

sub _get_roundcube_config_sqlite {
    return {
        'sqlite' => {
            ## note: HOME environment variable is supplied by cpsrvd
            ## note: the string interpolation gets a little hairy for variables that need homedir. These
            ##   are handled as 'finicky' interpolations in the _generate* call.
            ## case 22086: change mode=0600 (was 0646). This also required a small addition to the roundcubemail
            ##   patch, and a bug report to the developers.
            '__db_dsnw__'        => q{'sqlite:///' . getenv('HOME') . '/etc/' . getenv('_RCUBE') . '.rcube.db?mode=0600'},
            '__smtp_server__'    => q{'localhost'},
            '__smtp_user__'      => q{'%u'},
            '__smtp_pass__'      => q{'%p'},
            '__smtp_auth_type__' => q{'LOGIN'},
            '__temp_dir__'       => q{getenv('HOME') . '/tmp'},
            '__log_dir__'        => q{getenv('HOME') . '/logs/roundcube/'},
        }
    };
}

sub generate_roundcube_config_sqlite {
    my ( $DIR, $llogger ) = @_;

    local $logger = $llogger if $llogger;
    my $TEMPVARS = _get_roundcube_config_sqlite();
    return _generate_roundcube_config( $DIR, $TEMPVARS, 'sqlite' );
}

sub generate_hybrid_config {
    my ( $dir, $dbh ) = @_;
    my %cfgs = (
        %{ _get_roundcube_config_mysql($dbh) },
        %{ _get_roundcube_config_sqlite() },
    );
    return _generate_roundcube_config( $dir, \%cfgs, 'mysql_plus_sqlite' );
}

#Lazy-load these to avoid potential perl 5.6 compiler issues.
my %uri_escaping_mdb2_dsn;
my $uri_escaping_mdb2_dsn_pattern;

sub _escape_dsn_part_for_mdb2 {
    my ($str) = @_;

    #cf. http://pear.php.net/manual/en/package.database.mdb2.intro-dsn.php
    if ( !$uri_escaping_mdb2_dsn_pattern ) {
        %uri_escaping_mdb2_dsn = qw[
          &   %26
          (   %28
          )   %29
          +   %2b
          /   %2f
          :   %3a
          =   %3d
          ?   %3f
          @   %40
        ];
        $uri_escaping_mdb2_dsn_pattern = join( '|', map quotemeta, keys %uri_escaping_mdb2_dsn );
    }

    $str =~ s[(uri_escaping_mdb2_dsn_pattern)][$uri_escaping_mdb2_dsn{$1}]g;

    return $str;
}

## extracted from bin/update-roundcube-db; called from bin/update-roundcube*-db and scripts/convert_rcube*
sub _generate_roundcube_config {
    my ( $DIR, $hr_TEMPVARS, $context ) = @_;

    my $special_mode = $context eq 'mysql_plus_sqlite';
    $context = 'mysql' if $special_mode;
    my $temp_regex = join( '|', map { '(' . quotemeta . ')' } keys %{ $hr_TEMPVARS->{$context} } );
    my ( $template, $dest ) = ( "$DIR/roundcube/config/defaults.inc.php", "$DIR/roundcube/config/config.inc.php" );
    open( my $tin_fh, '<', $template ) or die "Can't open $template for reading: $!";

    # XXX is this really necessary? Can we just read then write atomically?
    my $lock = Cpanel::SafeFile::safesysopen( my $tout_fh, $dest, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT )), 0640 ) or warn "sysopen($dest) failed: $!";

    local $!;
    my $been_here;
    while ( readline($tin_fh) ) {
        my $line     = $_;
        my $to_print = '';

        # So, I'm being a bit hacky here, but that's somewhat the ask here.
        # Were I wanting to do this in a "cleaner" way I'd instead have all
        # but the DSN line for mysql be "already present" in the config
        # files in the RPM and just read from cpanel.config as to "what to use".
        # There's no *good* reason we're generating all these lines in config
        # at all other than to maybe avoid a file read on cpanel.config, which
        # seems pretty shaky ground to optimize around given we're already
        # loading 100+ modules with composer soon after loading the config.
        # Main reasoning here is that the less code we have to have here to
        # wrangle/generate, the better. Less moving parts = less breakage when
        # we have to update things. Template Toolkit usage might also be good
        # as an alternative, and somewhat poetic, given what PHP is --
        # "Yo dawg, I heard you like templating..."
        my ($key) = grep { defined } ( $line =~ $temp_regex );
        if ( !$key ) {
            $to_print = $line;
        }
        elsif ( $key eq '__db_dsnw__' && $special_mode ) {
            my $dsn_file = '/usr/local/cpanel/base/3rdparty/roundcube/config/mysql_dsnw.inc.php';
            $to_print .= <<"EREH";
\$has_sqlite = file_exists(getenv('HOME') . '/etc/' . getenv('_RCUBE') . '.rcube.db');
if(\$has_sqlite) {
    \$config['db_dsnw'] = $hr_TEMPVARS->{'sqlite'}{$key};
}
else {
    require_once('$dsn_file');
}
EREH
            Cpanel::FileUtils::Write::overwrite( $dsn_file, "<?php\n\$config['db_dsnw'] = $hr_TEMPVARS->{'mysql'}{$key}\n?>", 0640 );
            Cpanel::SafetyBits::Chown::safe_chown( 'cpanelroundcube', 'cpanelroundcube', $dsn_file ) or do {
                $logger->warn("chown(cpanelroundcube $dest) failed: $!");
            };
        }
        elsif ( $special_mode && ( $key eq '__temp_dir__' || $key eq '__log_dir__' ) ) {
            next if $been_here;
            $been_here = 1;
            $to_print .= <<'EREH';
if($has_sqlite) {
    $config['log_dir'] = getenv('HOME') . '/logs/roundcube/';
    $config['temp_dir'] = getenv('HOME') . '/tmp';
}
else {
    $config['log_dir'] = '/var/cpanel/roundcube/log';
    $config['temp_dir'] = '/var/cpanel/roundcube/tmp';
}
EREH
        }
        else {
            # In order to be consistent, we match the quote marks and replace
            # with strings already quoted.
            $line =~ s/\'$key\'/$hr_TEMPVARS->{$context}{$key}/g;
            $to_print .= $line;
        }
        print {$tout_fh} $to_print or $logger->warn("print() to “$dest” failed: $!");
    }

    if ($!) {
        $logger->warn("readline() from “$template” failed: $!");
    }

    close($tin_fh)                                 or $logger->warn("close($template) failed: $!");
    Cpanel::SafeFile::safeclose( $tout_fh, $lock ) or warn "safeclose($dest) failed: $!";

    # 644 if sqlite or mysql_plus_sqlite; 640 on mysql context.
    my ( $chmod, @chown ) = ( 0644, qw{root root} );
    if ( $context eq 'mysql' && !$special_mode ) {
        $chmod = 0640;
        @chown = ( 'cpanelroundcube', 'cpanelroundcube' );
    }

    chmod $chmod, $dest or $logger->warn("chmod($chmod $dest) failed: $!");
    Cpanel::SafetyBits::Chown::safe_chown( @chown, $dest ) or do {
        $logger->warn("chown(@chown $dest) failed: $!");
    };
    return;
}

## SOMEDAY: is there a better place for this? Cpanel.pm?
sub restart_cpsrvd {

    $logger->info("Restarting cpsrvd");

    require Cpanel::Signal;
    Cpanel::Signal::send_hup_cpsrvd();
    return;
}

## Called by scripts/convert_roundcube_mysql2sqlite
sub archive_and_drop_mysql_roundcube {
    my ($llogger) = @_;
    my $valid_archive = 0;

    local $logger = $llogger if $llogger;

    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Connect');
    my $mysql_dbh = Cpanel::MysqlUtils::Connect::get_dbi_handle();

    $valid_archive = archive_mysql_roundcube($mysql_dbh);

    prune_roundcube_archives( $ROUNDCUBE_DATA_DIR, 'roundcube.backup.sql.\d+', 'latest' );

    $mysql_dbh->do('DROP DATABASE IF EXISTS roundcube');

    return $valid_archive;
}

sub prune_mysql_roundcube_archives {
    prune_roundcube_archives( $ROUNDCUBE_DATA_DIR, 'roundcube.backup.sql.\d+', 'latest' );
}

sub archive_mysql_roundcube {
    my ( $dbh, $llogger ) = @_;

    local $logger = $llogger if $llogger;

    my $date = time();

    $logger->info("Archiving current Roundcube data to $ROUNDCUBE_DATA_DIR/roundcube.backup.sql.$date");

    ## case 44793: taking out '--no-create-info'; ensures the cp_schema_version table is recreated
    ## if present; since I am thinking about schema and application version disparity so much,
    ## I can not think of a mysqldump without create table statements to be a true backup.
    my $backup_file = "$ROUNDCUBE_DATA_DIR/roundcube.backup.sql.$date";

    #
    #Ensure that the backup is never world-readable by chmod()ing it
    #before mysqldump populates it.
    #

    open my $wfh, '>', $backup_file or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $backup_file, mode => '>', error => $! ] );

    chmod 0600, $wfh or die Cpanel::Exception::create( 'IO::ChmodError', [ path => $backup_file, permissions => 0600, error => $! ] );

    my @mysqldump_args = (
        '--no-create-db',
        '--skip-comments',
        '--complete-insert',
        '--ignore-table=roundcube.cache',
        '--ignore-table=roundcube.session',
        '--ignore-table=roundcube.messages',
        '--databases' => 'roundcube',
    );

    my $dump_out = $dbh->exec_with_credentials_no_db(
        program => Cpanel::DbUtils::find_mysqldump(),
        args    => \@mysqldump_args,
        stdout  => $wfh,
    );

    close $wfh or die Cpanel::Exception::create( 'IO::FileCloseError', [ path => $backup_file, error => $! ] );

    if ( $dump_out->CHILD_ERROR() ) {
        $logger->warn( "Failed to backup existing Roundcube DB: " . ${ $dump_out->stderr_r() } );
        unlink $backup_file or warn "unlink($backup_file) failed: $!";

        return 0;
    }

    $logger->info("Roundcube DB successfully archived");

    my $link_path = "$ROUNDCUBE_DATA_DIR/latest";
    if ( -l $link_path ) {
        unlink $link_path or do {
            die Cpanel::Exception->new( 'The system failed to unlink “[_1]” because of an error: [_2]', [ $link_path, $! ] );
        };
    }

    my $symlink_dest = $backup_file;
    $symlink_dest =~ s{.*/}{};    #Make the symlink relative to the same directory.

    symlink( $symlink_dest, $link_path ) or do {
        die Cpanel::Exception->new( 'The system failed to create a symbolic link “[_1]” to “[_2]” because of an error: [_3]', [ $link_path, $backup_file, $! ] );
    };

    return 1;
}

#The return indicates whether a custom installer ran.
sub process_custom_roundcube_install_file {

    if ( -e "$ROUNDCUBE_DATA_DIR/install" ) {

        # Since we now install via RPM, we'll just spit out a note and
        # do nothing.
        print <<"EOF";

NOTE:  cPanel manages the Roundcube system via RPM.  Your custom
install script in the $ROUNDCUBE_DATA_DIR/install file will no longer
operate.  See https://go.cpanel.net/patchroundcube for further
details.

EOF
    }

    return;
}

sub restore_latest_mysql_archive {
    my ($dbh) = @_;

    my $archive_path = Cpanel::Email::RoundCube::latest_archive_path();

    open my $rfh, '<', $archive_path or do {
        die Cpanel::Exception->new( 'The system failed to open the file “[_1]” for reading because of an error: [_2]', [$archive_path] );
    };

    my $run = $dbh->exec_with_credentials_no_db(
        program => Cpanel::DbUtils::find_mysql(),
        args    => [ '-f', '--database=roundcube' ],
        stdin   => $rfh,
    );

    if ( $run->CHILD_ERROR() ) {
        warn ${ $run->stderr_r() };
    }

    return $run->CHILD_ERROR();
}

sub latest_archive_path {
    return "$ROUNDCUBE_DATA_DIR/latest";
}

sub archive_sqlite_roundcube {
    my ($dbinfo) = @_;

    my $success = 1;
    my $date    = time();

    my $db_fullpath      = sprintf( '%s/%s', $dbinfo->{base_dir}, $dbinfo->{db_fname} );
    my $archive_fullpath = "$db_fullpath.$date";

    $logger->info("Archiving current Roundcube data to $archive_fullpath");

    my $rv = Cpanel::FileUtils::Copy::safecopy( $db_fullpath, $archive_fullpath );
    if ($rv) {
        $logger->info("Roundcube DB successfully archived");

        ## note: a missing .latest symlink should not be fatal
        my $latest = "$db_fullpath.latest";
        unlink($latest);

        # Use a relative symlink to prevent breakage after domain rename
        Cpanel::Path::relativesymlink( $archive_fullpath, $latest );
        system( 'ls', '-l', $archive_fullpath );
    }
    else {
        $logger->warn("Failed to backup Roundcube DB $db_fullpath.");
        $success = 0;
        unlink($archive_fullpath);
    }
    return $success;
}

sub prune_roundcube_archives {
    my ( $dir, $backup_regex, $latest_fname ) = @_;

    ## SOMEDAY: consider also a time-based clause; if the customer runs the update
    ##   script several times in succession due to a problem, we are likely overwriting
    ##   very valuable backups

    $logger->info("Cleaning old Roundcube data archives");

    local $@;

    # Keep 5 copies of roundcube dump
    my $backups_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes($dir) };
    warn $@ if !$backups_ar;

    my $_quoted = qr($backup_regex);
    my @backups = sort grep( /^$_quoted/, @$backups_ar );

    while ( scalar @backups > $MAX_ARCHIVES_TO_RETAIN ) {
        my $unlinkMe = shift(@backups);
        $logger->info("Removing old backup: $unlinkMe");
        unlink("$dir/$unlinkMe");
    }

    if ( @backups && !-e "$dir/$latest_fname" ) {

        # Use a relative symlink to prevent broken SQLite archive symlink after domain rename
        Cpanel::Path::relativesymlink( $backups[-1], "$dir/$latest_fname" );
    }

    return;
}

my @old_patches = qw{
  0001-cPanel-defaults.patch
  0003-provide-support-url.patch
  0004-Fix-possible-HTTP-DoS-on-error-in-keep-alive-request.patch
  0004-Fix-focus-issue-in-IE-when-selecting-message-row.patch
  0004-User-can-select-a-different-skin-when-its-choice-is-.patch
  0005-check-if-skin-directory-exist.patch
  0006-User-can-select-a-different-skin-when-its-choice-is-.patch
};

# Case 117993, deal with partially installed Roundcube on install
sub check_if_config_has_been_chowned {
    my $path = "$ROUNDCUBE_DEST_DIR/roundcube/config/config.inc.php";

    if ( !-e $path ) { return 0; }    # does not exists, could not have been chowned

    my $rc_uid = ( getpwnam 'cpanelroundcube' )[2];

    if ( $rc_uid != ( stat($path) )[4] ) {
        return 0;
    }

    return 1;
}

# Case 117993, deal with partially installed Roundcube on install
sub perform_chown_fix {
    my $path = "$ROUNDCUBE_DEST_DIR/roundcube/config/config.inc.php";

    if ( !-e $path ) { return 0; }    # does not exists cannot chown it

    my $rc_uid = ( getpwnam 'cpanelroundcube' )[2];
    my $rc_gid = ( getgrnam 'cpanelroundcube' )[2];

    chown $rc_uid, $rc_gid, $path or do {
        die Cpanel::Exception->create_raw("chown($path) failed: $!");
    };

    return 1;
}

#NOTE: What actually *cares* whether this file exists?
sub lock_roundcube_for_update {
    $logger->info("Roundcube will be locked out during this process.");
    return Cpanel::FileUtils::TouchFile::touchfile("$ROUNDCUBE_DATA_DIR/updating");
}

sub unlock_roundcube_after_update {
    if ( -e "$ROUNDCUBE_DATA_DIR/updating" ) {
        unlink "$ROUNDCUBE_DATA_DIR/updating" or do {
            $logger->warn("Roundcube failed to unlink $ROUNDCUBE_DATA_DIR/updating ($!).  Roundcube will be disabled until this is resolved.");
        };
    }

    return 1;
}

## eliminate code dupe in convert rcube and update rcube sqlite script
sub collect_domains {
    my ($user) = @_;

    return () unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    my @DOMAINS    = ( $cpuser_ref->{'DOMAIN'} );
    if ( ref $cpuser_ref->{'DOMAINS'} eq 'ARRAY' ) {
        push @DOMAINS, @{ $cpuser_ref->{'DOMAINS'} };
    }

    ## Filter out all ^www. and domain values of 'asterix'. The '?:' is not needed.
    ## case 22546
    my @acceptable_domains = grep( !/(?:^www\.|\*)/i, @DOMAINS );
    return @acceptable_domains;
}

sub _roundcubepass_file {
    '/var/cpanel/roundcubepass';
}

sub get_roundcube_password {
    my $roundcubepass;
    my $file = _roundcubepass_file();

    die "No Roundcube password file!" if !length $file;

    if ( -s $file ) {
        $roundcubepass = Cpanel::LoadFile::loadfile($file) or do {
            warn "Failed to read $file: $!";
        };

        # strip spaces and newline as they are not in generated by getranddata
        $roundcubepass =~ s/^\s+//m;
        $roundcubepass =~ s/\s+$//m;
    }

    if ( !$roundcubepass ) {
        $roundcubepass = Cpanel::Rand::Get::getranddata(16);
        my $lock = Cpanel::SafeFile::safesysopen( my $tout_fh, $file, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT )), 0600 ) or warn "sysopen($file) failed: $!";
        print {$tout_fh} $roundcubepass                or warn "print to “$file” failed: $!";
        Cpanel::SafeFile::safeclose( $tout_fh, $lock ) or warn "safeclose($file) failed: $!";
    }

    return $roundcubepass;
}

sub handle_mysql_roundcube_grants {
    my ( $dbname, $dbh ) = @_;

    my $host_ar = $dbh->selectall_arrayref( 'SELECT SUBSTRING_INDEX(CURRENT_USER(), ?, -1)', undef, '@' );
    if ( !$host_ar ) {
        die "Failed to identify logged-in MySQL host: " . $dbh->errstr();
    }

    my $grantHost = $host_ar->[0][0];

    my $roundcubepass = get_roundcube_password();

    my $grant = Cpanel::MysqlUtils::Grants->new();
    $grant->db_privs('ALL');
    $grant->db_name($dbname);
    $grant->quoted_db_obj('*');
    $grant->db_user('roundcube');
    $grant->db_host($grantHost);

    my $grant_str = $grant->to_string();

    local $@;
    my $ok = eval {
        my $rc_user_exists = $dbh->selectall_arrayref( 'SELECT User from mysql.user where User=?', undef, 'roundcube' );
        my $user_exists    = ( ref $rc_user_exists eq 'ARRAY' && scalar(@$rc_user_exists) );
        my %args           = (
            name   => Cpanel::MysqlUtils::Quote::quote('roundcube') . "@" . Cpanel::MysqlUtils::Quote::quote($grantHost),
            pass   => Cpanel::MysqlUtils::Quote::quote($roundcubepass),
            exists => $user_exists,
            hashed => 0,
            plugin => 'mysql_native_password',
        );

        my $db               = Cpanel::Database->new();
        my $set_password_sql = $db->get_set_password_sql(%args);

        $dbh->do($set_password_sql);
        $dbh->do($grant_str);
        $dbh->do('FLUSH PRIVILEGES');
    };

    if ( !$ok ) {
        Cpanel::Logger->new()->warn( $dbh->errstr() );
        return ( 0, $dbh->errstr() );
    }

    return 1;
}

1;
