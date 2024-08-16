#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/notify_call.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::notify_call;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

# Override to add process_ssl_pending_queue as it does this as user
use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
    '/usr/local/cpanel/bin/process_ssl_pending_queue',
);

sub _actions {
    return (
        'SEND_WARNING',
        'SEND_ERROR',
        'NOTIFY_CPUWATCH',
        'NOTIFY_LOGRUNNER',
        'NOTIFY_SSL_QUEUE_INSTALL',
        'NOTIFY_SSL_QUEUE_CERT_ACTION_NEEDED',
        'NOTIFY_NEW_USER',
        'NOTIFY_TEAM_USER_RESET_REQUEST',
    );
}

sub _demo_actions {
    return _action();
}

sub SEND_WARNING {
    my ( $self, $application, $message ) = @_;
    return $self->_do_generic( 'warn', $application, $message );
}

sub SEND_ERROR {
    my ( $self, $application, $message ) = @_;
    return $self->_do_generic( 'error', $application, $message );
}

sub _do_generic {
    my ( $self, $level, $application, $message ) = @_;

    die "Invalid application: “$application”!" if $application =~ tr<:><>;

    _do_notify(
        class            => "Application::$application",
        application      => "Application::$application",
        constructor_args => [
            notification_targets_user_account => 1,
            level                             => $level,
            message                           => $message,
            username                          => scalar $self->get_caller_username(),
        ],
    );

    return;
}

sub NOTIFY_SSL_QUEUE_CERT_ACTION_NEEDED {
    my ( $self, %opts ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'csr' ] ) if !$opts{csr};

    _do_notify(
        class            => 'Market::SSLCertActionNeeded',
        application      => 'Market::SSLCertActionNeeded',    #or should it be “Market”?
        constructor_args => [
            notification_targets_user_account => 1,
            username                          => scalar $self->get_caller_username(),
            %opts{
                qw(
                  vhost_name
                  product_id
                  order_id
                  order_item_id
                  provider
                  csr
                  action_urls
                )
            },
        ],
    );

    return;
}

sub NOTIFY_SSL_QUEUE_INSTALL {
    my ( $self, %opts ) = @_;

    _do_notify(
        class            => 'Market::SSLWebInstall',
        application      => 'Market::SSLWebInstall',    #or should it be “Market”?
        constructor_args => [
            notification_targets_user_account => 1,
            username                          => scalar $self->get_caller_username(),
            (
                map { $_ => $opts{$_} }
                  qw(
                  certificate_pem
                  vhost_name
                  product_id
                  order_id
                  order_item_id
                  provider
                  )
            ),
        ],
    );

    return;
}

sub NOTIFY_CPUWATCH {
    my ( $self, $pid ) = @_;

    _do_notify(
        'class'            => 'OverLoad::CpuWatch',
        'application'      => 'OverLoad::CpuWatch',
        'constructor_args' => [
            user   => $self->get_caller_username(),
            origin => 'cpuwatch',
            %{ $self->_get_pidinfo_if_valid_pid($pid) },
        ]
    );

    return 1;
}

sub NOTIFY_LOGRUNNER {
    my ( $self, $pid ) = @_;

    _do_notify(
        'class'            => 'OverLoad::LogRunner',
        'application'      => 'OverLoad::LogRunner',
        'constructor_args' => [
            user   => $self->get_caller_username(),
            origin => 'logrunner',
            %{ $self->_get_pidinfo_if_valid_pid($pid) },
        ]
    );

    return 1;
}

sub NOTIFY_NEW_USER {
    my ( $self, %opts ) = @_;

    _do_notify(
        class            => 'ChangePassword::NewUser',
        application      => 'ChangePassword::NewUser',
        constructor_args => [
            notification_targets_user_account => 1,
            username                          => scalar $self->get_caller_username(),
            use_alternate_email               => 1,
            (
                map { $_ => $opts{$_} }
                  qw(
                  to
                  user
                  user_domain
                  origin
                  source_ip_address
                  subaccount
                  cookie
                  team_account
                  )
            ),
        ],
    );

    return;
}

sub NOTIFY_TEAM_USER_RESET_REQUEST {
    my ( $self, %opts ) = @_;

    _do_notify(
        class            => 'ChangePassword::TeamUserResetRequest',
        application      => 'ChangePassword::TeamUserResetRequest',
        constructor_args => [
            notification_targets_user_account => 1,
            username                          => $self->get_caller_username(),
            use_alternate_email               => 1,
            (
                map { $_ => $opts{$_} }
                  qw(
                  to
                  user
                  user_domain
                  origin
                  source_ip_address
                  subaccount
                  cookie
                  team_account
                  )
            ),
        ],
    );

    return;
}

sub _do_notify {
    my (%notify_args) = @_;

    # CPANEL-36225: 'skip_send' belongs inside of 'constructor_args', not the main parameter list.
    my %constructor_args = @{ $notify_args{'constructor_args'} };
    $constructor_args{'skip_send'}   = 1;
    $notify_args{'constructor_args'} = [%constructor_args];

    require Cpanel::Notify;
    my $obj = Cpanel::Notify::notification_class(%notify_args);
    return $obj->send();
}

my $_MAX_PID;

sub _get_pidinfo_if_valid_pid {
    my ( $self, $pid ) = @_;

    require Cpanel::LoadFile;
    $_MAX_PID //= Cpanel::LoadFile::load('/proc/sys/kernel/pid_max');
    if ( !$pid ) {
        die Cpanel::Exception->create( "Give a valid process ID.", [$pid] );
    }
    elsif ( $pid !~ m{^[0-9]+} or $pid > $_MAX_PID ) {
        die Cpanel::Exception->create( "“[_1]” is not a valid process ID.", [$pid] );
    }

    require Cpanel::PsParser;
    my $pid_info = Cpanel::PsParser::get_pid_info($pid);
    if ( !$pid_info ) {

        # If the pid dies between trigger the notification and now there is
        # no point in sending the notification.
        die Cpanel::Exception->create( "The system does not have a process with ID “[_1]”. It is possible that a process was running but has since ended.", [$pid] );
    }

    return $pid_info;
}

1;
