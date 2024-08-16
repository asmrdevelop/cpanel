package Whostmgr::Transfers::Systems::Password;

# cpanel - Whostmgr/Transfers/Systems/Password.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Try::Tiny;

use Cpanel::Exception    ();
use Cpanel::LoadFile     ();
use Cpanel::Locale       ();
use Cpanel::Auth::Shadow ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the encrypted system password.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $archive_shadow_file = "$extractdir/shadow";

    return 1 if !-s $archive_shadow_file;

    my $shadow;
    my $err;
    try {
        $shadow = Cpanel::LoadFile::load($archive_shadow_file);
    }
    catch {
        $err = Cpanel::Exception::get_string($_);
    };

    return ( 0, $err ) if !$shadow;

    chomp($shadow);

    ## Case 21406: FreeBSD prefixes '*LOCKED*' to suspended accounts, while Linux prefixes '!!'.
    ##   Ensures each side handles the other during the "transfer then unsuspend" process.
    #NOTE: We no longer support FreeBSD, but hey.
    $shadow =~ s/^\*LOCKED\*//;
    $shadow =~ s/^!!//;

    $self->start_action( $self->_locale()->maketext('Restoring password …') );

    my ( $status, $statusmsg ) = Cpanel::Auth::Shadow::update_shadow( $newuser, $shadow );

    $self->out($statusmsg);

    if ( !$status ) {
        return ( $status, $statusmsg );
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
