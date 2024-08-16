package Cpanel::TailWatch::MailHealth;

# cpanel - Cpanel/TailWatch/MailHealth.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::TailWatch::Base';

use Cpanel::TailWatch ();
use Cpanel::OS        ();

our $VERSION = 1.0;
my $daysec                 = 86400;
my $MAILBOX_STATUS_TIMEOUT = 300;                            # 5 minutes
my $LOCKFILE               = '/var/cpanel/mailhealth.pid';

sub internal_name { return 'mailhealth'; }

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'internal_store' => {} }, $my_ns;

    my $maillog = Cpanel::OS::maillog_path();
    $maillog = $maillog . '.0' if !-f $maillog;
    $maillog = '/var/log/mail' if !-f $maillog;

    $tailwatch_obj->register_module( $self, __PACKAGE__, Cpanel::TailWatch::BACK30LINES(), [$maillog] );

    $self->{'process_line_regex'}->{$maillog} = qr/dovecot.*\(Out of memory/;

    return $self;
}

sub process_line {
    my ( $self, $line, $tailwatch_obj ) = @_;

    return if !$line;

    my ( $srvlog, $data ) = split( /\: /, $line, 2 );
    return if ( !$srvlog || !$data || $srvlog !~ m{dovecot$} );

    # Apr 23 09:40:25 mx1.cpanel.net dovecot: imap(scott@cpanel.net): Fatal: master: service(imap): child 25254 returned error 83 (Out of memory (service imap { vsz_limit=512 MB }, you may need to increase it) - set CORE_OUTOFMEM=1 environment to get core dump)
    my ( $service, $user, $vsz_limit ) = $data =~ m{^(imap|lmtp|pop3)\(([^\)]+)\).*vsz_limit=([0-9]+)};

    return if !$service;

    my $account = _get_account($user);
    return if !$account;

    require Cpanel::ForkAsync;
    Cpanel::ForkAsync::do_in_child(
        sub {
            return _send_oom_notification(
                $tailwatch_obj,
                'service'              => $service,
                'account'              => $account,
                'current_memory_limit' => $vsz_limit,
            );
        }
    );

    return 1;
}

sub _get_account {
    my ($full_email) = @_;
    return if !$full_email;

    my ( $email, $domain ) = split( /\@/, $full_email );

    my $hostname;
    if ($domain) {
        require Cpanel::Sys::Hostname;
        $hostname = Cpanel::Sys::Hostname::gethostname();
        return if !$hostname;
    }

    # if the email is $cPanel_username@$hostname, then it is the default account
    # and we only want to return the cPanel username
    # else, we want to return the full email address
    if ( defined $domain && $domain eq $hostname ) {

        require Cpanel::AcctUtils::Account;
        return $email if Cpanel::AcctUtils::Account::accountexists($email);
    }

    return $full_email;
}

sub _send_oom_notification {
    my ( $tailwatch_obj, %opts ) = @_;

    # Prevent a storm of doveadm processes and a storm of OOM notifications by only allowing one process at a time to run this section.
    require Cpanel::PIDFile;
    require Cpanel::Try;
    require Cpanel::Exception;

    Cpanel::Try::try(
        sub {
            Cpanel::PIDFile->do(
                $LOCKFILE,
                sub {
                    require Cpanel::Notify;

                    return if Cpanel::Notify::notify_blocked(
                        app      => 'MailServer::OOM',
                        status   => 'OOM_' . $opts{'account'},
                        interval => $daysec,
                    );

                    my $mailbox_status;
                    Cpanel::Try::try(    # would rather use Try::Tiny, but Cpanel::Try is already loaded...

                        sub {
                            require Cpanel::Dovecot::Utils;
                            $mailbox_status = Cpanel::Dovecot::Utils::get_mailbox_status( $opts{'account'}, $MAILBOX_STATUS_TIMEOUT );
                        },

                        '' => sub { $tailwatch_obj->warn( "Failed to fetch mailbox status of “$opts{'account'}”: " . Cpanel::Exception::get_string_no_id($@) ) if ref $tailwatch_obj },

                        # Set a default value if an exception happened:
                        sub { $mailbox_status ||= {} }

                    );                   # END inner Cpanel::Try::try()

                    Cpanel::Notify::notification_class(
                        interval         => $daysec,
                        status           => 'OOM_' . $opts{'account'},
                        class            => 'MailServer::OOM',
                        application      => 'MailServer::OOM',
                        constructor_args => [ %opts, 'mailbox_status' => $mailbox_status ],
                    );
                }
            );    # END Cpanel::PIDFile->do()
        },

        'Cpanel::Exception::CommandAlreadyRunning' => sub {
            my $pid = $@->get('pid');
            $tailwatch_obj->debug("Not processing OOM notification for “$opts{'account'}” because another line is being processed by PID $pid.") if ref $tailwatch_obj && $tailwatch_obj->{'debug'};
        },
        '' => sub { $tailwatch_obj->error( "Error while processing OOM notification for “$opts{'account'}”: " . Cpanel::Exception::get_string_no_id($@) ) if ref $tailwatch_obj }
    );    # END outer Cpanel::Try::try()

    return;
}

1;
