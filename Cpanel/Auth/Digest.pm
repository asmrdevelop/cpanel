package Cpanel::Auth::Digest;

# cpanel - Cpanel/Auth/Digest.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Session::Load ();
use Cpanel::Session       ();
use Digest::MD5           ();

sub parse_digest_request {
    my $parsedata = shift;
    $parsedata =~ s/\s*,\s*$//;

    return {
        map {
            $_ = [ ( split( /=/, $_, 2 ) )[ 0, 1 ] ];
            $_->[1] =~ s/^"//;
            $_->[1] =~ s/"$//;
            ( $_->[0], $_->[1] )
        } ( split( /\s*\,\s*/, $parsedata ) )
    };
}

sub get_last_nc {
    my $session = shift;
    $session =~ s/\///g;
    my $SESSION_ref = Cpanel::Session::Load::loadSession($session);
    return $SESSION_ref->{'nc'} || 0;
}

sub set_nc {
    my ( $session, $nc, $user, $keep_session ) = @_;
    $session =~ s/\///g;
    $nc      =~ s/[\r\n]//g;
    $user    =~ s/[\r\n]//g;
    ($nc)   = $nc   =~ /^([0-9a-f]+)$/;
    ($user) = $user =~ /^([-._A-Za-z0-9]+)$/;

    if ( my $SESSION_ref = $keep_session ? Cpanel::Session::Load::loadSession($session) : {} ) {
        $SESSION_ref->{'nc'}   = $nc;
        $SESSION_ref->{'user'} = $user;
        Cpanel::Session::saveSession( $session, $SESSION_ref );
    }

    return 1;
}

sub do_digest_auth {
    my %OPTS               = @_;
    my $digest_request_ref = $OPTS{'auth_request'};
    my $digest_ha1         = $OPTS{'digest_ha1'};
    my $current_uid        = $OPTS{'current_uid'};
    my $user               = $OPTS{'user'};

    if ( !Cpanel::Session::Load::session_exists( $digest_request_ref->{'opaque'} ) ) {
        return ( 0, { 'reason' => 'nosession' } );
    }
    elsif ( !$digest_ha1 ) {
        return ( 0, { 'reason' => 'noha1' } );
    }
    elsif (defined $digest_ha1
        && $digest_request_ref->{'opaque'}
        && $digest_request_ref->{'nonce'}
        && $digest_request_ref->{'cnonce'}
        && $digest_request_ref->{'nc'}
        && $digest_request_ref->{'qop'}
        && $digest_request_ref->{'uri'} ) {
        my $last_nc = get_last_nc( $digest_request_ref->{'opaque'} );
        if ( hex $digest_request_ref->{'nc'} > hex $last_nc ) {
            my $ha1      = $digest_ha1;
            my $ha2      = Digest::MD5::md5_hex( $ENV{'REQUEST_METHOD'} . ':' . $digest_request_ref->{'uri'} );
            my $response = Digest::MD5::md5_hex( $ha1 . ':' . $digest_request_ref->{'nonce'} . ':' . ( $digest_request_ref->{'nc'} ) . ':' . $digest_request_ref->{'cnonce'} . ':' . $digest_request_ref->{'qop'} . ':' . $ha2 );
            if ( $digest_request_ref->{'response'} eq $response ) {
                $current_uid = $>                                                                    if !defined $current_uid;
                set_nc( $digest_request_ref->{'opaque'}, ( $digest_request_ref->{'nc'} ), $user, 0 ) if $current_uid == 0;
                return ( 1, { 'reason' => 'success', 'nc' => hex( $digest_request_ref->{'nc'} ) } );
            }
            else {
                return ( 0, { 'reason' => 'authfailed' } );
            }
        }
        else {
            return ( 0, { 'reason' => 'stalenc', 'lastnc' => hex($last_nc), 'nc' => hex( $digest_request_ref->{'nc'} ) } );
        }
    }
    else {
        return ( 0, { 'reason' => 'noauth' } );
    }

}

1;
