package Cpanel::Server::xferstream;

# cpanel - Cpanel/Server/xferstream.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Rand::Get      ();
use Cpanel::PwCache        ();
use Cpanel::Tar            ();
use Cpanel::PwCache::Group ();

sub do_acctxferstream_to_fh {
    my ( $server_obj, $user, $fh ) = @_;

    $fh ||= $server_obj->connection->get_socket();
    $fh->autoflush(1);

    my $tag = '--' . Cpanel::Rand::Get::getranddata( 128, undef, 10 );

    my $tarcfg = Cpanel::Tar::load_tarcfg();
    my ( $xferuid, $xfergid, $user_homedir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3, 7 ];
    my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user($user);

    $server_obj->switchuser( $user, $xferuid, $xfergid, @supplemental_gids );    #will die if fails
    $server_obj->memorized_chdir($user_homedir) || $server_obj->internal_error("Could not memorized_chdir to $user_homedir: $!");

    print {$fh} "HTTP/1.1 200 OK\r\nX-Complete-Tag: $tag\r\nContent-type: cpanel/acctxferstream\r\nConnection: close\r\n\r\n" or $server_obj->check_pipehandler_globals();
    $server_obj->sent_headers_to_socket();

    my $err_obj = $server_obj->create_tar_to_fh( '.', $fh );

    #If died by signal or couldn't run tar, show error.
    #Unfortunately, checking for ENOENT would be useless because tar itself
    #uses ENOENT to indicate a general failure. :-/
    if ( $err_obj->signal_code() || ( $err_obj->error_code() && $err_obj->error_name() || q<> ) eq 'EACCES' ) {
        my $error = $err_obj->autopsy();

        $server_obj->get_log('error')->warn("do_acctxferstream_to_fh: $error");

        print {$fh} "acctxferstream_error: $error\n\n";

        $server_obj->killconnection('acctxferstream_error');
    }
    else {
        print {$fh} $tag . "\n" or $server_obj->check_pipehandler_globals();
    }

    return $err_obj;
}

1;
