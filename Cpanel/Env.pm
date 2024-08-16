package Cpanel::Env;

# cpanel - Cpanel/Env.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.7';

#We have code inside and outside this module that expects to receive a
#space-delimited list; however, that’s quirky to maintain. So we write out
#the list line-by-line then put it together at compile time.
my $SAFE_ENV_VARS;

BEGIN {
    $SAFE_ENV_VARS = q<
        ALLUSERSPROFILE
        APPDATA
        BUNDLE_PATH
        CLIENTNAME
        COMMONPROGRAMFILES
        COMPUTERNAME
        COMSPEC
        CPANEL_BASE_INSTALL
        CPANEL_IS_CRON
        CPBACKUP
        DEBIAN_FRONTEND
        DEBIAN_PRIORITY
        DOCUMENT_ROOT
        FORCEDCPUPDATE
        FP_NO_HOST_CHECK
        HOMEDRIVE
        HOMEPATH
        LANG
        LANGUAGE
        LC_ALL
        LC_MESSAGES
        LC_CTYPE
        LOGONSERVER
        NEWWHMUPDATE
        NOTIFY_SOCKET
        NUMBER_OF_PROCESSORS
        OPENSSL_NO_DEFAULT_ZLIB
        OS
        PATH
        PATHEXT
        PROCESSOR_ARCHITECTURE
        PROCESSOR_IDENTIFIER
        PROCESSOR_LEVEL
        PROCESSOR_REVISION
        PROGRAMFILES
        PROMPT
        PYTHONIOENCODING
        SERVER_SOFTWARE
        SESSIONNAME
        SKIP_DEFERRAL_CHECK
        SSH_CLIENT
        SYSTEMDRIVE
        SYSTEMROOT
        TEMP
        TERM
        TMP
        UPDATENOW_NO_RETRY
        UPDATENOW_PRESERVE_FAILED_FILES
        USERDOMAIN
        USERNAME
        USERPROFILE
        WINDIR
    >;

    $SAFE_ENV_VARS =~ tr<\n >< >s;
    $SAFE_ENV_VARS =~ s<\A\s+><>;
}

# CPANEL_IS_CRON - Denotes that one of the parent procs is upcp
# FORCEDCPUPDATE - Denotes that upcp is running under --force
# CPANEL_BASE_INSTALL - Used to indicate new install process

# cleanenv
#
#Args are:
#   keep (array ref) - list of %ENV entries to keep (in addition to "safe" ones)
#   delete (array ref) - list of %ENV entries to delete, no matter what
#   http_purge (boolean) - remove SERVER_SOFTWARE and DOCUMENT ROOT entries
#
#Note that this function does NOT have the quirk that 'keep'/'delete' persists
#from one invocation to the next that existed in the legacy version.

{
    no warnings 'once';
    *cleanenv = *clean_env;
}

sub clean_env {
    my %OPTS = @_;

    my %SAFE_ENV_VARS = map { $_ => undef } split( m{ }, $SAFE_ENV_VARS );

    if ( defined $OPTS{'keep'} && ref $OPTS{'keep'} eq 'ARRAY' ) {
        @SAFE_ENV_VARS{ @{ $OPTS{'keep'} } } = undef;
    }

    if ( defined $OPTS{'delete'} && ref $OPTS{'delete'} eq 'ARRAY' ) {
        delete @SAFE_ENV_VARS{ @{ $OPTS{'delete'} } };
    }

    delete @ENV{ grep { !exists $SAFE_ENV_VARS{$_} } keys %ENV };
    if ( $OPTS{'http_purge'} ) {
        delete @ENV{ 'SERVER_SOFTWARE', 'DOCUMENT_ROOT' };
    }

    return;
}

sub get_safe_env_vars {
    return $SAFE_ENV_VARS;
}

sub get_safe_path {
    return '/usr/local/jdk/bin:/usr/kerberos/sbin:/usr/kerberos/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/X11R6/bin:/usr/local/bin:/usr/X11R6/bin:/root/bin:/opt/bin';
}

sub set_safe_path {
    return ( $ENV{'PATH'} = get_safe_path() );
}

1;
