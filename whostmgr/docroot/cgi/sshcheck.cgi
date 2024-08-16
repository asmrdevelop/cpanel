#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/sshcheck.cgi       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Encoder::Tiny ();
use Cpanel::Form          ();
use Whostmgr::ACLS        ();
use IO::Socket::INET      ();

Whostmgr::ACLS::init_acls();

my %FORM = Cpanel::Form::parseform();

print "Content-type: text/html\r\n\r\n";

if ( !Whostmgr::ACLS::hasroot() ) {
    print "Access Denied\n";
    exit;
}

my $server      = $FORM{'server'};
my $safe_server = Cpanel::Encoder::Tiny::safe_html_encode_str($server);
my $port        = int $FORM{'port'} || 22;
my $failreason  = 'Connection Timeout';
my $fail        = 1;
my $sshver;
eval {
    $SIG{'__DIE__'} = 'DEFAULT';
    local $SIG{'ALRM'} = sub { die; };
    alarm(12);

    my $sock = IO::Socket::INET->new(
        'Proto'    => 'tcp',
        'PeerAddr' => $server,
        'PeerPort' => $port,
        'Blocking' => 1,
        'Timeout'  => 10
    );
    if ( !$sock ) {
        $failreason = "Unable to connect to $safe_server:$port: $!";
        die;
    }
    $sshver = readline($sock);
    close($sock);
};

my $safe_sshver = Cpanel::Encoder::Tiny::safe_html_encode_str($sshver);

if ( $sshver eq '' ) {
    print qq{<span class="error">Connecting to Remote Server Failed: $failreason\n</span>};
}
elsif ( $sshver =~ /ssh/i ) {
    print "Remote Server Ok: $safe_sshver\n";
}
else {
    print qq{<span class="error">Remote Server not running ssh on port $port ?!?!: $safe_sshver</span>\n};
}
