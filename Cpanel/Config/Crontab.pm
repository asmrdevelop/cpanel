package Cpanel::Config::Crontab;

# cpanel - Cpanel/Config/Crontab.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::Crontab

=head1 SYNOPSIS

    Cpanel::Config::Crontab::sync_root_crontab();

=head1 DESCRIPTION

A one-stop-shop for keeping root’s crontab in sync with the system
configuration.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::Sources ();
use Cpanel::Update::Crontab ();
use Cpanel::Cron::Utils     ();
use Cpanel::Server::Type    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $updated_yn = sync_root_crontab()

Examines the system configuration state and, if needed, updates root’s
crontab accordingly. Returns 1 if the configuration was altered and 0
if not. Throws an appropriate exception on failure.

=cut

sub sync_root_crontab {
    my $old = _fetch_root_crontab('root');

    my %CPSRC           = _loadcpsources();
    my $httpupdate_host = $CPSRC{'HTTPUPDATE'} // 'httpupdate.cpanel.net';

    my @crontab_lines = split m<\n>, $old;

    my $cron_updates = _get_cron_updates(
        \@crontab_lines,
        $httpupdate_host,
        Cpanel::Server::Type::is_dnsonly(),
    );

    if ( defined $cron_updates ) {

        # Extra empty-string gives a trailing newline.
        my $crontab_txt = join( "\n", @$cron_updates, q<> );

        _save_root_crontab($crontab_txt);

        return 1;
    }

    return 0;
}

#----------------------------------------------------------------------
# These are mocked in tests.

*_loadcpsources     = \*Cpanel::Config::Sources::loadcpsources;
*_get_cron_updates  = \*Cpanel::Update::Crontab::_get_cron_updates;
*_save_root_crontab = \*Cpanel::Cron::Utils::save_root_crontab;

sub _fetch_root_crontab {
    return Cpanel::Cron::Utils::fetch_user_crontab('root');
}

1;
