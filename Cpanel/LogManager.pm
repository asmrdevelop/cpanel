package Cpanel::LogManager;

# cpanel - Cpanel/LogManager.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache            ();
use Cpanel                     ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Config::User::Logs ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::Encoder::URI       ();
use Cpanel::FileUtils::Write   ();
use Cpanel::Locale             ();
use Cpanel::Exception          ();

our $VERSION = '1.2';

=head1 MODULE

C<Cpanel::LogManager>

=head1 DESCRIPTION

C<Cpanel::LogManager> provides helper methods used to control how log archives
are created and manages. It also includes a method to retrieve the list of
available log archives.

=head1 FUNCTIONS

=cut

sub LogManager_init { }

sub LogManager_showsettings {
    my $locale = Cpanel::Locale->get_handle();

    my ( $archivelogs, $remoldarchivedlogs ) = Cpanel::Config::User::Logs::load_users_log_config( [ Cpanel::PwCache::getpwnam($Cpanel::user) ] );
    my %CPCONF     = Cpanel::Config::LoadCpConf::loadcpconf();
    my $checked    = '';
    my $remchecked = '';
    if ( $archivelogs eq "1" ) {
        $checked = 'checked';
    }
    if ( $remoldarchivedlogs eq "1" ) {
        $remchecked = 'checked';
    }

    if ( $CPCONF{'dumplogs'} eq "1" ) {
        my $hours = $CPCONF{'cycle_hours'};
        print "<input value=1 type=checkbox name=archivelogs $checked> " . $locale->maketext( 'Archive log files to your home directory after the system processes statistics. The system currently processes logs every [quant,_1,hour,hours].', $hours ) . "<br />\n";
    }
    else {
        print "<input value=1 type=checkbox name=archivelogs $checked> " . $locale->maketext('Archive logs in your home directory at the end of each month.') . " <br />\n";
    }

    print "<input value=1 type=checkbox name=remoldarchivedlogs $remchecked> " . $locale->maketext('Remove the previous month’s archived logs from your home directory at the end of each month.') . " <br />\n";

    return (1);
}

sub LogManager_savesettings {
    my ( $archive, $remarchive ) = @_;

    my $conf = '';
    if ($archive)    { $conf .= "archive-logs=1\n"; }
    if ($remarchive) { $conf .= "remove-old-archived-logs=1\n"; }

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$Cpanel::homedir/.cpanel-logs", $conf, 0600 ) ) {
        $Cpanel::CPERROR{$Cpanel::context} = "Failed to write: $Cpanel::homedir/.cpanel-logs :$!";
    }

    return 1;
}

sub LogManager_listdownloads {
    my $locale = Cpanel::Locale->get_handle();

    my @LOGDIR;
    if ( opendir( my $dir, "$Cpanel::homedir/logs" ) ) {
        @LOGDIR = readdir($dir);
        closedir($dir);
    }
    elsif ( -e "$Cpanel::homedir/logs" ) {

        # failure to open is only an error if the directory exists.
        print "<p>Cannot open $Cpanel::homedir/logs: $!</p>\n";
        return;
    }

    my ($logcount) = 0;
    foreach my $logfile (@LOGDIR) {
        next if ( $logfile =~ /^\./ );
        $logcount++;
        my $file     = Cpanel::Encoder::Tiny::safe_html_encode_str($logfile);
        my $uri_file = Cpanel::Encoder::URI::uri_encode_str($logfile);
        print "<a href=\"$ENV{'cp_security_token'}/getlogarchive/${uri_file}\">${file}</a><br>\n";
    }
    if ( $logcount == 0 ) {
        print $locale->maketext('There are currently no archived log files.') . "\n";
    }
    return;
}

=head2 list_settings()

Gets the log archive settings.

=head3 RETURNS

Hashref with the following properties:

=over

=item archive_logs - Boolean

If 1, the system will archives log files to your home directory after
the system processes statistics. If 0, the system does not archive logs.

=item prune_archive - Boolean

If 1, the system will remove the previous months archived logs from
your home directory at the end of each month. If 0, the system does
not remove archived logs.

=back

=head3 THROWS

=over

=item When the configuration exists, but the system fails to load the log configuration.

=item When the configuration exists, but Cpanel::Config::LoadConfig::loadConfig prints errors to STDERR.

=back

=cut

sub list_settings {

    require Cpanel::Config::LoadConfig;
    require Capture::Tiny;
    require Cpanel::PwCache;

    my $cpconf;
    my $homedir     = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
    my $conf_path   = "${homedir}/.cpanel-logs";
    my $conf_exists = -e $conf_path;

    # much deeper code always seem to dump to STDERR no matter what
    my ( $stdout, $stderr, $config ) = Capture::Tiny::capture(
        sub {
            Cpanel::Config::LoadConfig::loadConfig($conf_path);
        }
    );

    die Cpanel::Exception::create(
        "IO::ReadError",
        "The system was unable to load the log configuration."
    ) if $stderr && $conf_exists;

    if ($conf_exists) {

        require Cpanel::Validate::Boolean;

        if ( !exists( $config->{'archive-logs'} ) ) {
            $config->{'archive-logs'} = 0;
        }
        elsif ( !Cpanel::Validate::Boolean::is_valid( $config->{'archive-logs'} ) ) {
            $cpconf = Cpanel::Config::LoadCpConf::loadcpconf() if !$cpconf;
            $config->{'archive-logs'} = $cpconf->{'default_archive-logs'};
        }

        if ( !exists( $config->{'remove-old-archived-logs'} ) ) {
            $config->{'remove-old-archived-logs'} = 0;
        }
        elsif ( !Cpanel::Validate::Boolean::is_valid( $config->{'remove-old-archived-logs'} ) ) {
            $cpconf = Cpanel::Config::LoadCpConf::loadcpconf() if !$cpconf;
            $config->{'remove-old-archived-logs'} = $cpconf->{'default_remove-old-archived-logs'};
        }

    }
    else {
        $cpconf                               = Cpanel::Config::LoadCpConf::loadcpconf();
        $config->{'archive-logs'}             = $cpconf->{'default_archive-logs'};
        $config->{'remove-old-archived-logs'} = $cpconf->{'default_remove-old-archived-logs'};
    }

    return {
        'archive_logs'  => $config->{'archive-logs'},
        'prune_archive' => $config->{'remove-old-archived-logs'}
    };
}

=head2 list_logs()

=head3 RETURNS

Array of log files located in /home/{user}/logs.

=head3 THROWS

=over

=item When the logs folder does not exist.

=back

=cut

sub list_logs {

    require Cpanel::PwCache;

    my $homedir = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
    my $path    = "${homedir}/logs";
    return [] if !-d $path;

    require Cpanel::Autodie;

    my @archives;
    Cpanel::Autodie::opendir( my $dir_fh, $path );
    while ( my $file = readdir($dir_fh) ) {
        my $full_path = "$path/$file";
        next if !-f $full_path;            # skip anything but files.
        next if $file !~ m<\A.+\.gz\z>;    # skip anything that does not have the .gz extension.

        my $mtime = ( stat(_) )[9] || 0;
        push @archives, {
            file  => $file,
            path  => $full_path,
            mtime => $mtime,
        };
    }
    Cpanel::Autodie::closedir($dir_fh);

    return \@archives;
}

=head2 save_settings(ARCHIVE_LOG, PRUNE_LOG)

Saves the log archive settings.

=head3 ARGUMENTS

=over

=item ARCHIVE_LOG - Boolean

When 1, archives the logs. When 0 does not archive the logs.

=item PRUNE_LOG - Boolean

When 1, removes old log archives at the end of the month. When 0 does not remove old log archives.

=back

=head3 RETURNS

1 when successful.

=head3 THROWS

=over

=item When creating the /home/{user}/.cpanel-logs configuration file fails.

=item When writing to the /home/{user}/.cpanel-logs configuration file fails.

=back

=cut

sub save_settings {

    my ( $archive_logs, $prune_archive ) = @_;

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die( $archive_logs,  'archive_logs' )  if defined($archive_logs);
    Cpanel::Validate::Boolean::validate_or_die( $prune_archive, 'prune_archive' ) if defined($prune_archive);

    if ( !defined($archive_logs) || !defined($prune_archive) ) {
        my $settings = list_settings();
        $archive_logs  //= $settings->{'archive_logs'};
        $prune_archive //= $settings->{'prune_archive'};
    }

    my $conf = '';
    if ( $archive_logs == 1 ) {
        $conf .= "archive-logs=1\n";
    }

    if ( defined $prune_archive && $prune_archive == 1 ) {
        $conf .= "remove-old-archived-logs=1\n";
    }

    eval {
        Cpanel::FileUtils::Write::overwrite(
            "$Cpanel::homedir/.cpanel-logs",
            $conf,
            0600
        );
    };
    if ( my $err = $@ ) {
        die Cpanel::Exception->create_raw( $err->to_string_no_id() ) if $err->isa('Cpanel::Exception');
        die Cpanel::Exception->create_raw($err);
    }

    return 1;

}

1;
