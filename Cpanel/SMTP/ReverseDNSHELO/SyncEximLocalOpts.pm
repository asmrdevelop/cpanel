package Cpanel::SMTP::ReverseDNSHELO::SyncEximLocalOpts;

# cpanel - Cpanel/SMTP/ReverseDNSHELO/SyncEximLocalOpts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SMTP::ReverseDNSHELO::SyncEximLocalOpts

=head1 DESCRIPTION

This module syncs existence of
L<Cpanel::SMTP::ReverseDNSHELO>’s flag with F</etc/exim.conf.localopts>.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync()

Sync the value of L<Cpanel::SMTP::ReverseDNSHELO> into the
F</etc/exim.conf.localopts> key C<use_rdns_for_helo>.

We have this module because L<Whostmgr::TweakSettings::Configure::Mail>
does not implement save.

=cut

sub sync {
    require Whostmgr::TweakSettings::Configure::Mail;
    my $mail         = Whostmgr::TweakSettings::Configure::Mail->new();
    my $current_conf = $mail->get_conf();

    require Cpanel::SMTP::ReverseDNSHELO;
    my $authoritative_value = Cpanel::SMTP::ReverseDNSHELO->is_on() ? 1 : 0;

    my $conf_key = 'use_rdns_for_helo';

    if ( !length $current_conf->{$conf_key} || $current_conf->{$conf_key} ne $authoritative_value ) {
        require Cpanel::Transaction::File::LoadConfig;
        my $transaction = Cpanel::Transaction::File::LoadConfig->new( Whostmgr::TweakSettings::Configure::Mail::get_exim_localopts_loadconfig_args() );

        my $value = $transaction->get_entry($conf_key);

        # We recheck the value in case some other process altered
        # Whostmgr::TweakSettings::Configure::Mail’s datastore between a) when
        # we read it above and b) when we acquired the lock.
        if ( !length $value || $value ne $authoritative_value ) {
            $transaction->set_entry( $conf_key, $authoritative_value );
            $transaction->save_or_die();
        }

        $transaction->close_or_die();
    }
    return;
}

1;
