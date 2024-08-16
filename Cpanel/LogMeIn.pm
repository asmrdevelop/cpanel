package Cpanel::LogMeIn;

# cpanel - Cpanel/LogMeIn.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# LogMeIn.pm is dual licensed, and may also be licensed under the following
# license
#

#
#Copyright (c) 2013, cPanel, Inc.
#All rights reserved.
#
#Redistribution and use in source and binary forms, with or without modification,
#are permitted provided that the following conditions are met:
#
#Redistributions of source code must retain the above copyright notice, this list
#of conditions and the following disclaimer. Redistributions in binary form must
#reproduce the above copyright notice, this list of conditions and the following
#disclaimer in the documentation and/or other materials provided with the
#distribution. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
#ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
#OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
#IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

use strict;
use Net::SSLeay             ();
use Cpanel::JSON            ();
use Cpanel::Encoder::URI    ();
use Cpanel::Services::Ports ();

my %SERVICE_PORTS = (
    'cpanel'  => $Cpanel::Services::Ports::SERVICE{'cpanels'},
    'whm'     => $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
    'webmail' => $Cpanel::Services::Ports::SERVICE{'webmails'},
);

sub get_loggedin_url {
    my %OPTS = @_;

    my $user                   = $OPTS{'user'};
    my $pass                   = $OPTS{'pass'};
    my $hostname               = $OPTS{'hostname'};
    my $service                = $OPTS{'service'};
    my $active_token_for_reuse = $OPTS{'active_token_for_reuse'} || 0;
    my $goto_uri               = ( $OPTS{'goto_uri'}        || '/' );
    my $port                   = ( $SERVICE_PORTS{$service} || $SERVICE_PORTS{'cpanel'} );

    my ( $page, $result, @HEADERS ) = Net::SSLeay::post_https(
        $hostname,
        $port,
        '/login/?login_only=1',
        Net::SSLeay::make_headers( 'Connection' => 'close' ),
        Net::SSLeay::make_form( 'user' => $user, 'pass' => $pass, 'goto_uri' => $goto_uri, 'active_token_for_reuse' => $active_token_for_reuse )
    );
    my $session;

    for ( my $i = 0; $i <= $#HEADERS; $i += 2 ) {
        my ( $name, $value ) = @HEADERS[ $i .. $i + 1 ];

        if ( $name eq 'SET-COOKIE' && $value =~ m{session=([^\;]+)} ) {
            $session = $1;
            last;
        }
    }

    local $@;
    my $page_struct    = eval { Cpanel::JSON::Load($page) };
    my $json_parse_err = $@;

    if ( $session && $result =~ /^HTTP\S+\s+[32]/ ) {

        # Security tokens may be manually turned off so
        # we provide an empty string in that case.
        my $security_token = $page_struct && $page_struct->{'security_token'} || '';

        my $extra = $goto_uri eq '/' ? '' : '&goto_uri=' . Cpanel::Encoder::URI::uri_encode_str($goto_uri);
        return ( 1, 'Login OK', 'https://' . $hostname . ':' . $port . $security_token . '/login/?session=' . $session . $extra, $security_token );
    }

    my $error = $page_struct && $page_struct->{'message'};
    $error ||= "$result: $json_parse_err: $page";

    return ( 0, $error );
}

1;

__END__

use lib '/usr/local/cpanel';
use Cpanel::LogMeIn ();

my $user = '__USERNAME__'; #or lookup
my $pass = '__PASSWORD__'; #or lookup
my $host = '__HOSTNAME__'; #or lookup
my $service = 'cpanel'; #or whm or webmail

my($login_ok,$login_message,$login_url) = Cpanel::LogMeIn::get_loggedin_url('user'=>$user,'pass'=>$pass,'hostname'=>$host,'service'=>$service,'goto_uri'=>'/');

if ($login_ok) {
    print "Location: $login_url\r\n\r\n";
} else {
    print "Content-type: text/plain\r\n\r\n";
    print "LOGIN FAILED: $login_message\n";
}

exit (0);
