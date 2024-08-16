package Whostmgr::XMLUI::Hostname;

# cpanel - Whostmgr/XMLUI/Hostname.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::Hostname   ();
use Whostmgr::XMLUI      ();
use Whostmgr::ApiHandler ();

sub sethostname {
    my %OPTS     = @_;
    my $hostname = $OPTS{'hostname'};

    my ( $status, $statusmsg, $warnref, $msgref ) = Whostmgr::Hostname::sethostname($hostname);

    # $msgref is an array of messages. Whostmgr::ApiHandler will add multiple msgs to the output. Need to combine them.
    my $messages;
    foreach my $msgs_line ( @{$msgref} ) {
        chomp $msgs_line;
        $messages .= $msgs_line . "\n";
    }
    chomp $messages;    # remove trailing newline

    my @RSD = ( { 'status' => $status, 'statusmsg' => $statusmsg, 'warns' => $warnref, 'msgs' => $messages } );
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'sethostname'} = \@RSD;

    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'sethostname', 'NoAttr' => 1 );

}

1;
