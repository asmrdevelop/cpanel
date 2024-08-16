package Cpanel::Auth::Shadow;

# cpanel - Cpanel/Auth/Shadow.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = 1.2;

use strict;
use AcctLock                       ();
use Cpanel::Transaction::File::Raw ();
use Cpanel::Locale::Lazy 'lh';

our $shadow_file                                  = '/etc/shadow';
our $DEFAULT_DAYS_BEFORE_PASSWORD_MAY_BE_CHANGE   = 0;               # zero means any time
our $DEFAULT_DAYS_AFTER_PASSWORD_MUST_BE_CHANGED  = 99999;           # humans do not live this long
our $DEFAULT_DAYS_TO_WARN_BEFORE_PASSWORD_EXPIRED = 7;               # one week

sub _get_mod_time {
    return int( time / ( 60 * 60 * 24 ) );
}

sub update_shadow {
    my ( $user, $crypted_pass ) = @_;

    AcctLock::acctlock();

    my ( $status, $statusmsg, $old_crypted_pw ) = update_shadow_without_acctlock( $user, $crypted_pass );

    AcctLock::acctunlock();

    return ( $status, $statusmsg, $old_crypted_pw );
}

sub update_shadow_without_acctlock {
    my ( $user, $crypted_pass ) = @_;

    # from crypt() man page
    # Note: crypt() does not technically allow _, however on older versions
    # we allowed _s so we allow them though for now
    return ( 0, "Crypted password may only contain A-Z a-z 0-9 \$ . / ! = * _" ) if $crypted_pass !~ m/^[A-Za-z0-9\$\.\/!=\*\_]+$/;

    my $mytime  = _get_mod_time();
    my $trans   = Cpanel::Transaction::File::Raw->new( 'path' => $shadow_file );
    my $dataref = $trans->get_data();

    my $seenline        = 0;
    my $user_line_start = "$user:";
    my @SHADOW;

    my $old_crypted_pass;

    foreach my $line ( split( m{\n}, $$dataref ) ) {
        if ( rindex( $line, $user_line_start, 0 ) == 0 ) {

            #operator:*:10325:-1:-1:-1:-1:-1:-1
            my @LINE = split( m/:/, $line );

            $old_crypted_pass = $LINE[1];
            $LINE[1] = $crypted_pass;

            $LINE[2] = $mytime;
            for ( 0 .. 8 ) { $LINE[$_] ||= ''; }    # Must be filled or system tools will error
            $line     = join( ':', @LINE );
            $seenline = 1;
        }
        push @SHADOW, $line;
    }

    push @SHADOW, join( ':', $user, $crypted_pass, $mytime, $DEFAULT_DAYS_BEFORE_PASSWORD_MAY_BE_CHANGE, $DEFAULT_DAYS_AFTER_PASSWORD_MUST_BE_CHANGED, $DEFAULT_DAYS_TO_WARN_BEFORE_PASSWORD_EXPIRED, '', '', '' ) if !$seenline;
    $$dataref = join( "\n", @SHADOW ) . "\n";

    my ( $status, $statusmsg ) = $trans->save_and_close();
    if ($status) {
        $statusmsg = _password_changed_msg($user);
    }
    return ( $status, $statusmsg, $old_crypted_pass );

}

sub _password_changed_msg {    # to be mocked in tests
    return lh->maketext( "Password for “[_1]” has been changed.", $_[0] );
}

1;
