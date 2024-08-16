package Whostmgr::Cron;

# cpanel - Whostmgr/Cron.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This module allows root to read and edit crontab files with file locking.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Cron::Edit             ();
use Cpanel::Locale                 ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::OS                     ();

#This variable is a global for testing purposes only.
#It's underscore-prefixed because nothing else should really hit it;
#edits from userland should go through the crontab executable.
our $_USER_CRON_DIR;

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub sync_user_cron_shell {
    my ($user) = @_;

    my ( $username_ok, $username_msg ) = Cpanel::Cron::Edit::validate_username($user);
    return ( 0, $username_msg ) if !$username_ok;

    $_USER_CRON_DIR ||= Cpanel::OS::user_crontab_dir();

    my $crontab = "$_USER_CRON_DIR/$user";

    local $@;
    my $transaction = eval { Cpanel::Transaction::File::Raw->new( path => $crontab ) };

    if ( !$transaction ) {
        return ( 0, "The system failed to obtain a read/write lock on the file “$crontab” because of an error: $@" );
    }

    my $err;

    my ( $ok, $is_changed ) = Cpanel::Cron::Edit::fix_user_crontab( $user, $transaction->get_data() );
    if ( !$ok ) {
        $err = $is_changed;
    }
    elsif ($is_changed) {
        my ( $save_ok, $save_msg ) = $transaction->save();

        if ( !$save_ok ) {
            $err = $save_msg;
        }
    }

    my ( $close_ok, $close_msg ) = $transaction->close();

    if ( !$close_ok ) {
        $err = $err ? "$err\n$close_msg" : $close_msg;
    }

    return $err ? ( 0, $err ) : 1;
}

1;
