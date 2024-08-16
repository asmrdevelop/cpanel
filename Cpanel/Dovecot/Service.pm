package Cpanel::Dovecot::Service;

# cpanel - Cpanel/Dovecot/Service.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Service - manage the state of dovecot's internal services

=head1 SYNOPSIS

  Cpanel::Dovecot::Service::set_dovecot_service_state( 'protocols' => { 'pop3' => 0, 'imap' => 0 } );

  Cpanel::Dovecot::Service::set_dovecot_service_state( 'protocols' => { 'pop3' => 1, 'imap' => 1 } );

  Cpanel::Dovecot::Service::set_dovecot_monitoring_state( 'protocols' => { 'pop3' => 0, 'imap' => 0 } );

  Cpanel::Dovecot::Service::set_dovecot_monitoring_state( 'protocols' => { 'pop3' => 1 } );


=head1 DESCRIPTION

This module allows enabling/disabling imap and pop3 in the dovecot
configuration.  It may handle additional dovecot services in the future

=cut

use strict;

use Try::Tiny;

use Cpanel::CachedDataStore   ();
use Cpanel::Debug             ();
use Cpanel::SafeRun::Object   ();
use Cpanel::AdvConfig::Setup  ();
use Cpanel::Chkservd::Manage  ();
use Cpanel::Services::Enabled ();

our $SCRIPT_TO_REBUILD_DOVECOTCONF    = '/usr/local/cpanel/scripts/builddovecotconf';
our $DOVECOT_ADVCONFIG_DATASTORE_FILE = '/var/cpanel/conf/dovecot/main';

my %ALLOWED_PROTOCOLS = ( 'pop3' => 1, 'imap' => 1 );

=head1 METHODS

=head2 set_dovecot_service_state

Enable or disable services inside of dovecot

=head3 Arguments

A hash with the following keys:

protocols      - The protocols to enable/disable.  A hashref with the following keys:

  imap - boolean (0/1)
  pop3 - boolean (0/1)

=head3 Return Value

  0 - The dovecot configuration was not modified (it was already in the desired state)
  1 - The dovecot configuration was modified

=cut

sub set_dovecot_service_state {
    my (%opts) = @_;
    my $protocols_ref = _get_protocols_from_opts(%opts);

    Cpanel::AdvConfig::Setup::ensure_conf_dir_exists('dovecot');

    # TODO: use Cpanel::Transaction here in the future
    # we can't do this now since we don't have a module that
    # acts like Cpanel::CachedDataStore and does the YAML and JSON cache
    my $dovecot_conf_obj = Cpanel::CachedDataStore::loaddatastore( $DOVECOT_ADVCONFIG_DATASTORE_FILE, 1 );    # lock and load
    if ( 'HASH' ne ref $dovecot_conf_obj->{'data'} ) {
        $dovecot_conf_obj->{'data'} = {};
    }
    my @services;
    push @services, 'imap' if $protocols_ref->{'imap'};
    push @services, 'pop3' if $protocols_ref->{'pop3'};
    push @services, 'none' if !@services;
    my $config_line = join( ' ', @services );

    if ( !length $dovecot_conf_obj->{'data'}{'protocols'} || $dovecot_conf_obj->{'data'}{'protocols'} ne $config_line ) {
        $dovecot_conf_obj->{'data'}{'protocols'} = $config_line;
        $dovecot_conf_obj->save();

        try {
            Cpanel::SafeRun::Object->new_or_die( 'program' => $SCRIPT_TO_REBUILD_DOVECOTCONF );
        }
        catch {
            Cpanel::Debug::log_warn("“$SCRIPT_TO_REBUILD_DOVECOTCONF” failed: $_");
        };
        return 1;
    }
    $dovecot_conf_obj->abort();
    return 0;
}

=head1 METHODS

=head2 set_dovecot_monitoring_state

Enable or disable monitoring of services inside of dovecot

=head3 Arguments

A hash with the following keys:

protocols      - The protocols to enable/disable.  A hashref with the following keys:

  imap - boolean (0/1)
  pop3 - boolean (0/1)

=head3 Return Value

  0 - The chkservd configuration was not modified (it was already in the desired state)
  1 - The chkservd configuration was modified

=cut

sub set_dovecot_monitoring_state {
    my (%opts) = @_;
    my $protocols_ref = _get_protocols_from_opts(%opts);

    my %monitored_services = Cpanel::Chkservd::Manage::getmonitored();
    my $modified           = 0;

    if ( exists $protocols_ref->{'imap'} ) {
        if ( $protocols_ref->{'imap'} && Cpanel::Services::Enabled::is_enabled('imap') ) {
            if ( !$monitored_services{'imap'} ) {
                Cpanel::Chkservd::Manage::enable('imap');
                $modified = 1;
            }
        }
        else {
            if ( $monitored_services{'imap'} ) {
                Cpanel::Chkservd::Manage::disable('imap');
                $modified = 1;
            }
        }
    }

    if ( exists $protocols_ref->{'pop3'} ) {
        if ( $protocols_ref->{'pop3'} && Cpanel::Services::Enabled::is_enabled('pop') ) {
            if ( !$monitored_services{'pop'} ) {
                Cpanel::Chkservd::Manage::enable('pop');
                $modified = 1;
            }
        }
        else {
            if ( $monitored_services{'pop'} ) {
                Cpanel::Chkservd::Manage::disable('pop');
                $modified = 1;
            }
        }
    }

    return $modified;
}

sub _get_protocols_from_opts {
    my (%opts) = @_;
    if ( !$opts{'protocols'} ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'protocols' ] );
    }

    my %protocols = %{ $opts{'protocols'} };

    foreach my $protocol ( sort keys %protocols ) {
        if ( !$ALLOWED_PROTOCOLS{$protocol} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must only include the following: [join,~, ,_2]", [ 'protocols', [ sort keys %ALLOWED_PROTOCOLS ] ] );
        }
    }

    return \%protocols;
}

1;
