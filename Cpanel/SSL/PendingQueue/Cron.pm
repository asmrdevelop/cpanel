package Cpanel::SSL::PendingQueue::Cron;

# cpanel - Cpanel/SSL/PendingQueue/Cron.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Cron::Utils ();
use Cpanel::Math        ();

# our for tests
our $POLLING_BIN = '/usr/local/cpanel/bin/process_ssl_pending_queue';
my $POLLING_INTERVAL = 5;

sub _get_crontab_obj {
    my ($username) = @_;

    my $crontab = Cpanel::Cron::Utils::fetch_user_crontab($username);

    require Config::Crontab;
    return Config::Crontab::Block->new(
        -data => $crontab,
    );
}

sub _save_crontab_obj {
    my ( $username, $crontab_obj ) = @_;

    my $cron_entry = $crontab_obj->dump();
    Cpanel::Cron::Utils::save_user_crontab( $username, $cron_entry );

    return;
}

# Input: Username to add or remove cron entry for
# Return: 1 if the cron entry was added, 0 if it was not needed. The function will die if it encounters an error
sub add_polling_cron_entry_for_user_if_needed {
    my ($username) = @_;

    my $crontab_obj = _get_crontab_obj($username);

    my ($polling_bin_entry) = $crontab_obj->select(
        -type       => 'event',
        -command_re => qr/\Q$POLLING_BIN\E/,
    );

    if ( !$polling_bin_entry ) {
        my @minutes = Cpanel::Math::divide_with_random_translation( 60, $POLLING_INTERVAL );
        $crontab_obj->last(
            Config::Crontab::Event->new(
                -minute  => join( ',', @minutes ),
                -command => $POLLING_BIN,
            ),
        );

        _save_crontab_obj( $username, $crontab_obj );

        return 1;
    }

    return 0;
}

# Input: Username to add or remove cron entry for
# Return: 1 if the cron entry was removed, 0 if it wasn't there. The function will die if it encounters an error
sub remove_polling_cron_entry_for_user_if_exists {
    my ($username) = @_;

    my $crontab_obj = _get_crontab_obj($username);

    my ($polling_bin_entry) = $crontab_obj->select(
        -type       => 'event',
        -command_re => qr/\Q$POLLING_BIN\E/,
    );

    if ($polling_bin_entry) {
        $crontab_obj->remove($polling_bin_entry);
        _save_crontab_obj( $username, $crontab_obj );

        return 1;
    }

    return 0;
}

1;
