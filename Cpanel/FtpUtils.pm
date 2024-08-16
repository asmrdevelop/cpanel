package Cpanel::FtpUtils;

# cpanel - Cpanel/FtpUtils.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile                           ();
use Cpanel::Debug                              ();
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::FtpUtils::Server                   ();
use Cpanel::Config::LoadCpUserFile             ();
use Cpanel::ConfigFiles                        ();

our $VERSION = '1.3';

*using_pureftpd   = *Cpanel::FtpUtils::Server::using_pureftpd;
*find_proftpconf  = *Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file;
*find_proftpdconf = *Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file;
*listftp          = *_listftp;

sub _listftp {
    my $user = shift || $Cpanel::user;

    my $users_domain_regex;
    if ($Cpanel::user) {
        $users_domain_regex = join '|', map { "\Q$_\E" } @Cpanel::DOMAINS;
    }
    else {
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        $users_domain_regex = join '|', map { "\Q$_\E" } ( $cpuser_ref->{'DOMAIN'}, $cpuser_ref->{'DOMAINS'} ? @{ $cpuser_ref->{'DOMAINS'} } : () );
    }
    $users_domain_regex = qr/\@($users_domain_regex)$/;

    my $ftp_user_pw_file = "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$user";

    my @LST;
    if ( !-r $ftp_user_pw_file ) {
        print "Fatal: $ftp_user_pw_file is missing or unreadable: Operation Aborted\n";
        return @LST;
    }

    my $plock = Cpanel::SafeFile::safeopen( \*PROFTPD, "<", $ftp_user_pw_file ) || return @LST;
    if ( !$plock ) {
        Cpanel::Debug::log_warn("Could not read from $ftp_user_pw_file");
        return;
    }
    while (<PROFTPD>) {
        my ( $ftpuser, $homedir ) = ( split( /:/, $_, 7 ) )[ 0, 5 ];
        next if ( $ftpuser eq '' || $ftpuser eq 'anonymous' );
        if ( $ftpuser eq $user . '_logs' ) {
            push( @LST, { 'user' => $ftpuser, 'homedir' => $homedir, 'type' => 'logaccess' } );
        }
        elsif ( $ftpuser ne $user ) {
            if ( $ftpuser !~ /^(ftp|anonymous)$/ ) {

                # Accounts at the main domain may be represented either with or without the domain.
                # Normalize the response so the caller doesn't have to be aware of this.
                $ftpuser .= '@' . _maindomain($user) if $ftpuser !~ tr/@//;

                # PIG-1785: Do not return FTP accounts that are setup for domains that the user
                # does not own (addon domains that were removed, etc).
                next if $ftpuser !~ $users_domain_regex;

                push( @LST, { 'user' => $ftpuser, 'homedir' => $homedir, 'type' => 'sub' } );
            }
            else {
                if ( -e '/var/cpanel/noanonftp' ) { next(); }

                push( @LST, { 'user' => 'ftp',       'homedir' => $homedir, 'type' => 'anonymous' } );
                push( @LST, { 'user' => 'anonymous', 'homedir' => $homedir, 'type' => 'anonymous' } );
            }
        }
        else {
            push( @LST, { 'user' => $ftpuser, 'homedir' => $homedir, 'type' => 'main' } );
        }
    }
    Cpanel::SafeFile::safeclose( \*PROFTPD, $plock );
    return @LST;
}

sub _maindomain {
    my ($cpanel_user) = @_;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($cpanel_user);
    return $cpuser_ref->{DOMAIN};    # 'DNS' from cpanel.config
}

1;
