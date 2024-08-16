package Whostmgr::Transfers::Systems::Cron;

# cpanel - Whostmgr/Transfers/Systems/Cron.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Cron::Edit ();
use Cpanel::LoadFile   ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_prereq { return ['Shell']; }    # Must restore the shell first so we get the right shell for cron

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [asis,crontab] entries.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my $olduser = $self->olduser();    # case 113733: Used only to find the files

    my $newuser = $self->newuser();

    my $archive_crontab = "$extractdir/cron/$olduser";    # case 113733: Used only to find the files

    #Nothing to do if there's no crontab in the archive!
    return ( 1, "No crontab" ) if !-e $archive_crontab;

    $self->start_action('Restoring crontab');

    local $@;

    my $crontab_sr = Cpanel::LoadFile::loadfile_r($archive_crontab);

    return ( 0, $@ ) if !$crontab_sr;

    # Some transfer packages are very broken and contain this content.
    return ( 1, "No valid crontab" ) if $$crontab_sr =~ /^no crontab for \S+$/;

    my ( $ok, $err ) = Cpanel::Cron::Edit::save_user_cron( $newuser, $crontab_sr );

    if ( !$ok ) {
        $self->warn("ERROR: $err");
    }

    return ( $ok, $err );
}

*restricted_restore = \&unrestricted_restore;

1;
