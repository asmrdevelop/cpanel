package Whostmgr::Config::Restore::System::Hulk;

# cpanel - Whostmgr/Config/Restore/System/Hulk.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::System::Hulk

=head1 DESCRIPTION

This module implements Hulk configuration restoration
for the transfer system.

This module subclasses L<Whostmgr::Config::Restore::Base>.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Restore::Base::JSON );

use Cpanel::CommandQueue       ();
use Cpanel::Config::Hulk::Load ();

use Whostmgr::API::1::Utils::Execute ();

sub _restore_from_structure ( $self, $conf ) {

    my $queue = Cpanel::CommandQueue->new();

    foreach my $subs_ar ( _create_subs_to_set_up_white_and_black_lists($conf) ) {
        $queue->add(@$subs_ar);
    }

    my $old_config = Cpanel::Config::Hulk::Load::loadcphulkconf();

    $queue->add(
        sub {
            _restore_config( $conf->{general} );
        },
        sub {
            # This is currently a no-op as currently there are no operations
            # after the config restoration that might potentially trigger this
            # handler. It is here in case additional operations are added later.
            _restore_config($old_config);
        },
        "Restore original cPHulk config",
    );

    $queue->run();

    return;
}

sub _create_subs_to_set_up_white_and_black_lists ($conf) {

    my @subs;

    for my $list_name (qw(black white)) {

        next if !scalar keys %{ $conf->{$list_name} };

        for my $ip ( keys %{ $conf->{$list_name} } ) {
            push @subs, [
                sub {
                    Whostmgr::API::1::Utils::Execute::execute_or_die(
                        'cPHulk', 'create_cphulk_record',
                        {
                            list_name          => $list_name,
                            ip                 => $ip,
                            comment            => $conf->{$list_name}{$ip},
                            skip_enabled_check => 1,
                        }
                    );
                },
                sub {
                    Whostmgr::API::1::Utils::Execute::execute_or_die(
                        'cPHulk', 'delete_cphulk_record',
                        {
                            list_name          => $list_name,
                            ip                 => $ip,
                            skip_enabled_check => 1,
                        }
                    );
                },
                "Remove cPHulk record for “$ip”",
            ];
        }

    }

    return @subs;
}

sub _restore_config ($config) {

    $config->{skip_enabled_check} = 1;
    Whostmgr::API::1::Utils::Execute::execute_or_die( 'cPHulk', 'save_cphulk_config', $config );

    return;
}

1;
