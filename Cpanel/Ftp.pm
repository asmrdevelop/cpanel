package Cpanel::Ftp;

# cpanel - Cpanel/Ftp.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::Locale                             ();
use Cpanel::Logger                             ();

require Exporter;

use Cpanel::API      ();
use Cpanel::API::Ftp ();

*import = \&Exporter::import;

*_fullftplist        = \&Cpanel::API::Ftp::_fullftplist;
*listftp             = \&Cpanel::API::Ftp::_listftp;
*_getreldir_from_dir = \&Cpanel::API::Ftp::_getreldir_from_dir;
*countftp            = \&Cpanel::API::Ftp::_countftp;

our @EXPORT = qw(
  ftpservername
  hasftp
  addftp
  delftp
  get_anonftp
  set_anonftp
  get_anonftpin
  set_anonftpin
  get_welcomemsg
  set_welcomemsg
  listftp
  countftp
  kill_ftp_session
  ftp_sessions
  passwdftp
  getftpquota
  ftpquota
  ftpquotalist
);

our $VERSION = '1.5';

my $FTP_hasftp;
my $logger = Cpanel::Logger->new();

##############################

## DEPRECATED!
sub api2_listftp {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "list_ftp", \%CFG );
    return @{ $result->data() || [] };
}

## DEPRECATED!
sub api2_listftpwithdisk {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "list_ftp_with_disk", \%CFG );
    return @{ $result->data() || [] };
}

## DEPRECATED!
sub api2_addftp {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "add_ftp", \%OPTS );

    my $reason = '';
    if ( $result->status() ) {
        $reason = 'OK';
    }

    return { 'result' => $result->status(), 'reason' => $reason };
}

## DEPRECATED!
sub addftp {
    my ( $user, $pass, $homedir, $quota, $disallowdot ) = @_;
    my %args   = ( user => $user, pass => $pass, homedir => $homedir, quota => $quota, disallow => $disallowdot );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "add_ftp", \%args );
    return $result->status();
}

## DEPRECATED!
sub api2_delftp {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "delete_ftp", \%OPTS );
    if ( $result->status() ) {
        return { 'result' => 1, 'reason' => 'OK' };
    }
    else {
        return { 'result' => 0, 'reason' => $result->errors_as_string() };
    }
}

## DEPRECATED!
sub delftp {
    my ( $user, $destroy ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "delete_ftp", { user => $user, destroy => $destroy } );
    unless ( $result->status() ) {
        return wantarray ? ( 0, $result->errors_as_string() ) : 0;
    }
    return 1;
}

## DEPRECATED!
sub api2_passwd {
    my %OPTS   = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "passwd", \%OPTS );
    if ( $result->status() ) {
        return { 'result' => 1, 'reason' => 'OK' };
    }
    else {
        return { 'result' => 0, 'reason' => $result->errors_as_string() };
    }
}

## DEPRECATED!
sub passwdftp {
    my ( $user, $pass ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "passwd", { user => $user, pass => $pass } );
    unless ( $result->status() ) {
        return wantarray ? ( 0, $result->errors_as_string() ) : 0;
    }
    return 1;
}

##############################

## DEPRECATED!
sub getftpquota {
    my ($acct) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "get_quota", { account => $acct } );
    unless ( $result->status() ) {
        return (0);
    }
    return $result->data();
}

## DEPRECATED!
sub api2_setquota {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "set_quota", \%CFG );
    if ( $result->status() ) {
        return { 'result' => 1, 'reason' => 'OK' };
    }
    else {
        return { 'result' => 0, 'reason' => $result->errors_as_string() };
    }
}

## DEPRECATED!
sub ftpquota {
    my ( $user, $quota, $kill ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "set_quota", { user => $user, quota => $quota, kill => $kill } );
    unless ( $result->status() ) {
        return wantarray ? ( 0, $result->errors_as_string() ) : 0;
    }
    return 1;
}

## DEPRECATED!
sub api2_listftpsessions {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "list_sessions", { 'api.quiet' => 1 } );
    return @{ $result->data() || [] };
}

## DEPRECATED!
sub ftp_sessions {
    ## no args
    ## note: returns a ArrayOfHash; massaged into a hash below
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "list_sessions" );
    unless ( $result->status() ) {
        return ();
    }
    my $data = $result->data() || [];
    my %rv   = map { $_->{pid} => $_ } @$data;
    return %rv;
}

## DEPRECATED!
sub kill_ftp_session {
    my ($login) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "kill_session", { login => $login } );
    return;
}

## DEPRECATED!
sub ftpservername {
    ## no args
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "server_name" );
    return $result->data();
}

##################################################
## ANONYMOUS FTP

## DEPRECATED!
sub get_anonftp {
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "allows_anonymous_ftp" );
    unless ( $result->status() ) {
        return '';
    }
    return 'checked="checked"';
}

## DEPRECATED!
sub get_anonftpin {
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "allows_anonymous_ftp_incoming" );
    unless ( $result->status() ) {
        return '';
    }
    return 'checked="checked"';
}

## DEPRECATED!
sub set_anonftp {
    my ($set) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "set_anonymous_ftp", { set => $set } );
    return;
}

## DEPRECATED!
sub set_anonftpin {
    my ($set) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "set_anonymous_ftp_incoming", { set => $set } );
    return;
}

## DEPRECATED
sub get_welcomemsg {
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "get_welcome_message" );
    if ( $result->status() ) {
        return $result->data();
    }
    return '';
}

## DEPRECATED
sub set_welcomemsg {
    my ($message) = @_;
    my $result = Cpanel::API::wrap_deprecated( "Ftp", "set_welcome_message", { message => $message } );
    return $result->status();
}

##############################
## UTILITY FUNCTIONS

sub hasftp {
    if ( defined $FTP_hasftp ) { return $FTP_hasftp; }
    $FTP_hasftp = 0;
    my $ftpconf = Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file();
    if ( -e $ftpconf ) {
        if ( open my $ftpconf_fh, '<', $ftpconf ) {
            while ( my $line = readline $ftpconf_fh ) {
                if ( $line =~ m/^\s*ServerName\s+(?:ftp\.)?\Q$Cpanel::CPDATA{'DNS'}\E/i ) {
                    $FTP_hasftp = 1;
                    last;
                }
            }
            close $ftpconf_fh;
        }
    }
    return $FTP_hasftp;
}

sub _ftp_log_link {
    my ( $user, $login, $ftphost, $path ) = @_;

    return 0 unless -e apache_paths_facade->dir_domlogs() . "/$user/$path" && -s _;

    print "<a href=\"ftp://$login\@$ftphost/$path\">ftp://$ftphost/$path</a><br />\n";
    return 1;
}

sub ftplist {
    goto &Cpanel::API::Ftp::_listftp;
}

##################################################

my $ftpaccts_feature = {
    needs_role    => 'FTP',
    needs_feature => "ftpaccts",
};

our %API = (
    'addftp'  => $ftpaccts_feature,    # Wrapped Cpanel::API::Ftp::add_ftp
    'delftp'  => $ftpaccts_feature,    # Wrapped Cpanel::API::Ftp::delete_ftp
    'listftp' => {                     # Wrapped Cpanel::API::Ftp::list_ftp
        'func'            => 'api2_listftp',
        'engine'          => 'arraysplit',
        'engineopts'      => ':',
        'datapoints'      => [ 'login', 'homedir' ],
        'csssafe'         => 1,
        'datapointregexs' => [],
        allow_demo        => 1,
        needs_role        => 'FTP',
    },
    'listftpsessions' => { needs_feature => "ftpsetup", allow_demo => 1 },    # Wrapped Cpanel::API::Ftp::list_sessions
    'listftpwithdisk' => {                                                    # Wrapped Cpanel::API::Ftp::list_ftp_with_disk
        'csssafe'  => 1,
        allow_demo => 1,
        needs_role => 'FTP',
    },
    'passwd'   => $ftpaccts_feature,                                          # Wrapped Cpanel::API::Ftp::passwd
    'setquota' => { allow_demo => 1 },                                        # Wrapped Cpanel::API::Ftp::set_quota
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
