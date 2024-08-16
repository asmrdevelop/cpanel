package Cpanel::Update::Blocker::CpanelConfig;

# cpanel - Cpanel/Update/Blocker/CpanelConfig.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Update::Logger      ();
use Cpanel::Config::CpConfGuard ();

sub new {
    my ( $class, $args ) = @_;

    my $self = $class->init($args);
    return bless $self, $class;
}

sub init {
    my ( $class, $args ) = @_;

    my $logger = $args->{'logger'} || Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'debug' } );

    return {
        'invalid' => 0,
        'logger'  => $logger,
        'guard'   => Cpanel::Config::CpConfGuard->new(),
    };
}

sub cpconfig {
    my $self = shift;
    return $self->{'guard'}->{'data'};
}

sub is_local_nameserver_type_valid {
    my $self            = shift;
    my $nameserver_type = $self->cpconfig()->{'local_nameserver_type'} || '';

    # No custom nameserver_type provided during install. That's ok.
    return 1 if ( $nameserver_type eq '' && $ENV{'CPANEL_BASE_INSTALL'} );

    return 1 if !$nameserver_type;
    return 1 if ( $nameserver_type =~ /^(?:powerdns|bind|disabled)$/ );

    $self->{'invalid'}++;
    return 0;
}

sub is_mailserver_valid {
    my $self       = shift;
    my $mailserver = $self->cpconfig()->{'mailserver'} || '';

    # No custom mailserver provided during install. That's ok.
    return 1 if ( $mailserver eq '' && $ENV{'CPANEL_BASE_INSTALL'} );

    return 1 if ( $mailserver =~ /^(?:dovecot|disabled)$/ );

    $self->{'invalid'}++;
    return 0;
}

sub is_ftpserver_valid {
    my $self      = shift;
    my $ftpserver = $self->cpconfig()->{'ftpserver'} || '';

    # No custom ftpserver provided during install. That's ok.
    return 1 if ( $ftpserver eq '' && $ENV{'CPANEL_BASE_INSTALL'} );

    return 1 if ( $ftpserver =~ /^(?:pure-ftpd|proftpd|disabled)$/ );

    $self->{'invalid'}++;
    return 0;
}

sub cleanse_cpanel_config_entries {
    my $self = shift;
    my $conf = $self->cpconfig();

    my $needs_save;

    for my $key (qw/ftpserver local_nameserver_type mailserver mysql-version/) {
        my $value = $conf->{$key} || '';

        # Can't do these on one line or it'll short.
        my $changed = $value =~ s/^\s+//;
        $changed += $value =~ s/\s+$//;
        next unless $changed;

        $self->{'logger'}->warning("Correcting white space found in cpanel.config setting: $key");
        $needs_save++;
        $conf->{$key} = $value;
    }
    if ( not $needs_save ) {
        $self->{'guard'}->release_lock();    # save() releases the lock automatically (cause keep_lock isn't in effect),
                                             # so we need to release the lock manually in scenarios where we dont 'cleanse'
        return;
    }

    $self->{'logger'}->warning("Saving cpanel.config with removed white space");
    $self->{'guard'}->save();

    return 1;
}

sub is_legacy_cpconfig_invalid {
    my $self = shift;

    return $self->{'invalid'};
}

1;
