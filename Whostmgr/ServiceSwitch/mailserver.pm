package Whostmgr::ServiceSwitch::mailserver;

# cpanel - Whostmgr/ServiceSwitch/mailserver.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Config::LoadCpConf ();
use Cpanel::Encoder::Tiny      ();
use Cpanel::SafeRun::Dynamic   ();
use Whostmgr::CheckRun         ();
use Whostmgr::HTMLInterface    ();
use Cpanel::Services::Enabled  ();

sub switch {
    my %OPTS = @_;

    my $is_running = Whostmgr::CheckRun::check( 'Mailserver conversion', '/var/cpanel/logs/setupmailserver', '/var/run/setupmailserver.pid' );
    if ($is_running) { return; }

    my $mailserver = $OPTS{'mailserver'};
    my @cmd        = ( '/usr/local/cpanel/scripts/setupmailserver', '--html' );

    my $security_token = $ENV{'cp_security_token'} || '';

    my %CPCONF             = Cpanel::Config::LoadCpConf::loadcpconf();
    my $current_mailserver = $CPCONF{'mailserver'};
    $current_mailserver = 'disabled' if Cpanel::Services::Enabled::is_enabled('mail') == 0;

    if ( $current_mailserver eq $mailserver ) {
        print "Already configured for $mailserver...skipping.\n";
        return 1;
    }

    if ( $mailserver ne 'dovecot' && $mailserver ne 'disabled' ) {
        print "Invalid mailserver type specified.\n";
        return;
    }

    if ( $mailserver eq 'disabled' ) {
        Whostmgr::HTMLInterface::simpleheading("Shutting down mailserver");
    }
    else {
        my $displayname = 'Dovecot';
        Whostmgr::HTMLInterface::simpleheading("Configuring $displayname mailserver");
        print "Installing and configuring $displayname...<br /><br />\n";
    }

    print "<pre>\n";

    my $old_umask = umask(0077);    # Case 92381: Logs should not be world-readable.
    open( my $smslog_fh, '>', '/var/cpanel/logs/setupmailserver' );

    if ($smslog_fh) {
        print "Conversion process will be logged to /var/cpanel/logs/setupmailserver.<br />\n";
    }

    umask($old_umask);

    Cpanel::SafeRun::Dynamic::livesaferun(
        'prog'      => [ @cmd, $mailserver ],
        'formatter' => sub {
            my $line = shift;
            if ($smslog_fh) {
                print $smslog_fh $line;
            }
            return Cpanel::Encoder::Tiny::safe_html_encode_str($line);
        },
    );

    if ($smslog_fh) {
        close($smslog_fh);
    }

    print "</pre><br>\n";

    if ( $mailserver ne 'disabled' ) {
        print "<span class=\"b2\">You should now check and adjust the mailserver settings<br>\n";
        print "by visiting the <a href=\"${security_token}/scripts2/mailserversetup\">Mailserver Configuration</a> interface.</span>\n";
    }

    return 1;
}

1;
