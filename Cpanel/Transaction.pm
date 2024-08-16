package Cpanel::Transaction;

# cpanel - Cpanel/Transaction.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Httpd     ();
use Cpanel::LoadModule             ();
use Cpanel::Transaction::File::Raw ();

sub get_httpd_conf {
    my %opts = @_;

    local $@;

    my $trans_obj = eval { Cpanel::Transaction::File::Raw->new( path => Cpanel::ConfigFiles::Httpd::find_httpconf(2), %opts ); };

    return ( 0, $@ ) if !$trans_obj;

    return ( 1, $trans_obj );
}

sub get_httpd_conf_datastore {
    my %opts = @_;

    Cpanel::LoadModule::loadmodule('Transaction::File::JSON');

    local $@;

    my $trans_obj = eval { 'Cpanel::Transaction::File::JSON'->new( path => Cpanel::ConfigFiles::Httpd::find_httpconf() . '.datastore', %opts ); };

    return ( 0, $@ ) if !$trans_obj;

    return ( 1, $trans_obj );
}

1;
