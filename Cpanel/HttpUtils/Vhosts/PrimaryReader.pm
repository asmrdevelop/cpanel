package Cpanel::HttpUtils::Vhosts::PrimaryReader;

# cpanel - Cpanel/HttpUtils/Vhosts/PrimaryReader.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: If you need to edit this datastore, use the "Primary" class.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::ConfigFiles                         ();
use Cpanel::Transaction::File::LoadConfigReader ();

#----------------------------------------------------------------------
sub new {
    my ($class) = @_;

    return bless {
        _transaction => scalar Cpanel::Transaction::File::LoadConfigReader->new(
            path      => $Cpanel::ConfigFiles::APACHE_PRIMARY_VHOSTS_FILE,
            delimiter => '=',
        )

    }, $class;
}

#----------------------------------------------------------------------
#Getters

sub get_primary_ssl_servername {
    die "No IP!" if !$_[1];    #Programmer error
    return $_[0]->{'_transaction'}->get_entry("$_[1]:SSL");
}

sub get_primary_non_ssl_servername {
    die "No IP!" if !$_[1];    #Programmer error
    return $_[0]->{'_transaction'}->get_entry( $_[1] );
}

1;
