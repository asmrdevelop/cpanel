package Whostmgr::Transfers::Systems::DigestShadow;

# cpanel - Whostmgr/Transfers/Systems/DigestShadow.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Auth::Digest::DB::Manage ();
use Cpanel::LoadFile                 ();
use Cpanel::Locale                   ();

our $MAX_DIGESTSHADOW_SECRET_LENGTH = 128;

use parent qw(
  Whostmgr::Transfers::Systems
);

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores password data for digest authentication.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->extractdir();

    my $newuser = $self->newuser();

    my $digestshadow_file = "$extractdir/digestshadow";

    return 1 if !-s $digestshadow_file;

    local $!;
    my $digestshadow = Cpanel::LoadFile::loadfile("$extractdir/digestshadow");
    if ($!) {

        #TODO: error handling
    }

    chomp($digestshadow);

    my ( $status, $cpuser_data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();

    if ( $cpuser_data->{SUSPENDED} && index( $digestshadow, '*LOCKED*' ) == 0 ) {
        $digestshadow = substr( $digestshadow, 8 );
    }

    return 1 if !length $digestshadow;    #just in case

    $self->start_action( $self->_locale()->maketext('Restoring Web Disk Digest Shadow') );

    ## only put user in Digest Auth database if their username is not changing; otherwise notify
    if ( !$self->local_username_is_different_from_original_username() ) {
        if ( $digestshadow !~ m/^[a-f0-9]+$/ ) {
            return ( 0, $self->_locale()->maketext( "The Web Disk Digest Shadow may only contain the following characters: [join,~, ,_1]", [ 'a-f', '0-9' ] ) );
        }
        elsif ( length $digestshadow > $MAX_DIGESTSHADOW_SECRET_LENGTH ) {
            return ( 0, $self->_locale()->maketext( "The Web Disk Digest Shadow may not exceed [quant,_1,character,characters].", $MAX_DIGESTSHADOW_SECRET_LENGTH ) );
        }

        #TODO: error handling?
        Cpanel::Auth::Digest::DB::Manage::set_entry( $newuser, $digestshadow );
    }
    else {
        my $locale  = Cpanel::Locale->get_handle();
        my $olduser = $self->olduser();               # case 113733: Used only for display

        require Cpanel::Notify::Deferred;

        Cpanel::Notify::Deferred::notify(
            application      => 'restorepkg',
            interval         => 1,
            status           => 'change user name success',
            class            => 'DigestAuth::Disable',
            constructor_args => [
                'to'                              => $newuser,
                'username'                        => $newuser,
                'olduser'                         => $olduser,
                'newuser'                         => $newuser,
                'origin'                          => 'Transfer System',
                notification_targets_user_account => 1,
            ],
        );

        my @messages = (
            $locale->maketext( "To change the account username from “[_1]” to “[_2]” requires Digest Authentication to be disabled.", $olduser, $newuser ),
            $locale->maketext("Use the Web Disk Accounts page in cPanel to re-enable Digest Authentication."),
        );

        $self->warn($_) for @messages;
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
