package Cpanel::SSH::CredentialCheck;

# cpanel - Cpanel/SSH/CredentialCheck.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule ();
use Cpanel::Exception  ();
use Cpanel::Capture    ();
use Try::Tiny;

sub remote_basic_credential_check {
    ## no args
    my ( $args, $metadata ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Remote');

    my ( $remoteobj, $err_obj );
    try {
        $remoteobj = Whostmgr::Remote->new($args);
    }
    catch {
        $err_obj = $_;
    };

    if ($err_obj) {
        @{$metadata}{qw(result reason)} = ( 0, Cpanel::Exception::get_string($err_obj) );
        return;
    }

    my $ret = Cpanel::Capture::trap_stdout(
        sub {
            return $remoteobj->remote_basic_credential_check();
        }
    );

    my $output = $ret->{'output'};
    my ( $result, $reason, $remote_response, $data, $escalation_method_used_name ) = @{ $ret->{'return'} };

    $metadata->{'result'} = $result || 0;
    $metadata->{'reason'} = $reason || $ret->{'EVAL_ERROR'};

    return { 'output' => $output, 'response' => $remote_response, 'escalation_method_used' => $escalation_method_used_name };
}

1;
