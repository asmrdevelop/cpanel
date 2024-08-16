package Cpanel::SSL::Setup;

# cpanel - Cpanel/SSL/Setup.pm                       Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::ServerTasks                  ();
use Cpanel::Features::Check              ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();

use List::Util ();

use constant DNS_RELOAD_SETTLE_TIME  => 20;                            # From live testing
use constant SUBDOMAIN_SETTLE_TIME   => DNS_RELOAD_SETTLE_TIME + 10;
use constant NEW_ACCOUNT_SETTLE_TIME => DNS_RELOAD_SETTLE_TIME + 15;

our $INSTALL_BEST_AVAILABLE_QUEUE_TIME = 5;
our $AUTOSSL_DNS_PRE_SETUP_QUEUE_TIME  = 200;                          # For users who create the domain before setting up the account
our $AUTOSSL_DNS_POST_SETUP_QUEUE_TIME = 7200;                         # For users who create the domain after setting up the account
our $DISABLED                          = 0;                            # for transfer restores to be able to set

=encoding utf-8

=head1 NAME

Cpanel::SSL::Setup - Setup SSL and trigger AutoSSL for a new domain

=head1 SYNOPSIS

    use Cpanel::SSL::Setup;

    Cpanel::SSL::Setup::setup_new_domain('user' => $user, 'domain' => $domain);

    my $tasks_ar = Cpanel::SSL::Setup::setup_new_domain_tasks('user' => $user, 'domain' => $domain);
    if ( $tasks_ar && @$tasks_ar ) {
        Cpanel::ServerTasks::schedule_tasks( ['SSLTasks'], $tasks_ar );
    }

=head2 setup_new_domain('user' => $user, 'domain' => $domain)

Install the best available certificate for the domain, and trigger
an AutoSSL run for the user if enabled.

=cut

sub setup_new_domain {
    my $tasks_ar = setup_new_domain_tasks(@_);
    if ( $tasks_ar && @$tasks_ar ) {
        Cpanel::ServerTasks::schedule_tasks( ['SSLTasks'], $tasks_ar );
    }
    return;
}

=head2 setup_new_domain('user' => $user, 'domain' => $domain)

Returns an arrayref of tasks that will install the best available certificate for the domain, and trigger
an AutoSSL run for the user if enabled.  These tasks are expected to be passed to
Cpanel::ServerTasks::schedule_tasks

=cut

sub setup_new_domain_tasks {
    my (%OPTS) = @_;

    # The DISABLED flag is for the transfer system to disable ssl setup
    # when restoring domains in order to avoid a race condition where
    # the ssl certificates and keys have not yet been restored and
    # we install the ones from the user's ssl storage instead of
    # the ones that were originally installed and backed up in the
    # cpmove archive.
    return if $DISABLED;

    my ( $user, $domain ) = @OPTS{ 'user', 'domain' };
    foreach my $required (qw(user domain)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    my @tasks = ( [ "install_best_available_certificate_for_domain $domain", { 'delay_seconds' => $INSTALL_BEST_AVAILABLE_QUEUE_TIME } ] );
    my @autossl_tasks;
    if ( Cpanel::Features::Check::check_feature_for_user( $user, 'autossl' ) ) {
        @autossl_tasks = $OPTS{'subdomain'} ? _autossl_sub_domain_tasks($user) : _autossl_new_domain_tasks($user);
    }
    return [ @tasks, @autossl_tasks ];
}

sub schedule_autossl_run_if_feature {
    my (%OPTS) = @_;
    my ($user) = $OPTS{'user'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] ) if !length $user;

    if ( Cpanel::Features::Check::check_feature_for_user( $user, 'autossl' ) ) {
        if ( my @tasks = _autossl_new_domain_tasks($user) ) {
            Cpanel::ServerTasks::schedule_tasks( ['SSLTasks'], \@tasks );
            return 1;
        }
    }
    return 0;
}

sub _autossl_new_domain_tasks {
    my ($user) = @_;

    # Multiple tasks that are scheduled are automaticlly collasped into
    # a single task when using schedule_task.  This ensures we never run
    # autossl_check more then one time in $AUTOSSL_DNS_POST_SETUP_QUEUE_TIME seconds.
    return (
        [ "autossl_check $user",   { 'delay_seconds' => _get_time_for_http_and_dns_to_become_active() + NEW_ACCOUNT_SETTLE_TIME } ],
        [ "autossl_recheck $user", { 'delay_seconds' => $AUTOSSL_DNS_POST_SETUP_QUEUE_TIME } ]
    );
}

sub _autossl_sub_domain_tasks {
    my ($user) = @_;

    # For a subdomain we expect we already have dns so we want to run right away
    return (
        [ "autossl_check $user",   { 'delay_seconds' => _get_time_for_http_and_dns_to_become_active() + SUBDOMAIN_SETTLE_TIME } ],
        [ "autossl_recheck $user", { 'delay_seconds' => $AUTOSSL_DNS_POST_SETUP_QUEUE_TIME } ]
    );
}

# For subdomains we create in the system -- time it takes to setup dns + webroot
sub _get_time_for_http_and_dns_to_become_active {
    my $cpconf_ref         = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $longest_defer_time = List::Util::max(
        Cpanel::HttpUtils::ApRestart::BgSafe::get_time_between_ap_restarts(),
        $cpconf_ref->{httpd_deferred_restart_time},
        $cpconf_ref->{bind_deferred_restart_time}
    );
    return ( $longest_defer_time * 2 );

}

1;
