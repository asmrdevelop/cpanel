package Whostmgr::Config::Restore::System::GreyList;

# cpanel - Whostmgr/Config/Restore/System/GreyList.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::System::GreyList

=head1 DESCRIPTION

This module implements GreyList configuration restoration
for the transfer system.

This module subclasses L<Whostmgr::Config::Restore::Base>.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Restore::Base::JSON );

use Cpanel::CommandQueue                          ();
use Cpanel::GreyList::CommonMailProviders::Config ();
use Cpanel::GreyList::Config                      ();
use Cpanel::GreyList::Handler                     ();

use Whostmgr::API::1::Utils::Execute ();

#----------------------------------------------------------------------

sub _restore_from_structure ( $self, $conf ) {

    my $common_mail_to_restore = $conf->{'common_mail_providers'};
    my $common_mail_status_quo = Cpanel::GreyList::CommonMailProviders::Config::load();

    my $queue = Cpanel::CommandQueue->new();

    my @subs_to_restore_common = _create_subs_to_set_up_common_mail( $conf->{'common_mail_providers'} );

    my @subs_to_roll_back = _create_subs_to_set_up_common_mail($common_mail_status_quo);

    $queue->add(
        $subs_to_restore_common[0],
        $subs_to_roll_back[0],
        'common mail providers auto-update configuration',
    );

    $queue->add(
        $subs_to_restore_common[1],
        $subs_to_roll_back[1],
        'trusted common mail providers',
    );

    $queue->add(
        $subs_to_restore_common[2],
        $subs_to_roll_back[2],
        'untrusted common mail providers',
    );

    my $old_trusted_hosts = Cpanel::GreyList::Handler->new()->read_trusted_hosts( undef, 1 );

    _enqueue_trusted_hosts_update(
        $queue,
        $conf->{'trusted_hosts'},
        $old_trusted_hosts,
    );

    my $old_config = Cpanel::GreyList::Config::loadconfig();

    # NB: The tests assume that this is the last step in restoration.
    $queue->add(
        sub {
            _restore_general_config( $conf->{'general'} );
        },
        sub {
            _restore_general_config($old_config);
        },
        'general GreyList configuration',
    );

    $queue->run();

    return;
}

sub _enqueue_trusted_hosts_update ( $queue, $new_trusted, $old_trusted ) {

    # The API doesn’t allow a bulk export/import, so we do it piecemeal.

    for my $old_hr (@$old_trusted) {
        my $ip = $old_hr->{'host_ip'};

        $queue->add(
            sub {
                _execute_or_die( 'delete_cpgreylist_trusted_host', { ip => $ip } );
            },
            sub {
                _execute_or_die( 'create_cpgreylist_trusted_host', { ip => $ip, comment => $old_hr->{'comment'} } );
            },
            "Restore $ip as trusted",
        );
    }

    for my $new_hr (@$new_trusted) {
        my $ip = $new_hr->{'host_ip'};

        # The backend logic behind this API call apparently doesn’t like
        # Unicode characters.
        utf8::encode( $new_hr->{'comment'} ) if utf8::is_utf8( $new_hr->{'comment'} );

        $queue->add(
            sub {
                _execute_or_die( 'create_cpgreylist_trusted_host', { ip => $ip, comment => $new_hr->{'comment'} } );
            },
            sub {
                _execute_or_die( 'delete_cpgreylist_trusted_host', { ip => $ip } );
            },
            "Delete $ip as trusted",
        );
    }

    return;
}

# This expects the same structure that
# Cpanel::GreyList::CommonMailProviders::Config::load() returns.
sub _create_subs_to_set_up_common_mail ($providers_hr) {

    my $individuals_hr = $providers_hr->{'provider_properties'};

    my %providers_config1 = (
        %{$providers_hr}{'autotrust_new_common_mail_providers'},
        map { $_ => $individuals_hr->{$_}{'autoupdate'} } keys %$individuals_hr,
    );

    my $config_sub = sub {
        _execute_or_die(
            'cpgreylist_save_common_mail_providers_config',
            \%providers_config1,
        );
    };

    my ( @trusted, @untrusted );
    for my $name ( sort keys %$individuals_hr ) {
        if ( $individuals_hr->{$name}{'is_trusted'} ) {
            push @trusted, $name;
        }
        else {
            push @untrusted, $name;
        }
    }

    my $trust_sub = sub {
        if (@trusted) {
            _execute_or_die(
                'cpgreylist_trust_entries_for_common_mail_provider',
                { provider => \@trusted },
            );
        }
    };

    my $untrust_sub = sub {
        if (@untrusted) {
            _execute_or_die(
                'cpgreylist_untrust_entries_for_common_mail_provider',
                { provider => \@untrusted },
            );
        }
    };

    return ( $config_sub, $trust_sub, $untrust_sub );
}

sub _restore_general_config ($config) {

    _execute_or_die( 'save_cpgreylist_config', $config );

    return;
}

sub _execute_or_die ( $fn, $args_hr ) {

    return Whostmgr::API::1::Utils::Execute::execute_or_die(
        'cPGreyList', $fn,
        $args_hr,
    );
}

1;
