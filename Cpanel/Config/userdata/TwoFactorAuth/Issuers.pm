package Cpanel::Config::userdata::TwoFactorAuth::Issuers;

# cpanel - Cpanel/Config/userdata/TwoFactorAuth/Issuers.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base qw(Cpanel::Config::userdata::TwoFactorAuth::Base);

use Cpanel::Hostname         ();
use Cpanel::Reseller         ();
use Cpanel::AcctUtils::Owner ();

sub DATA_FILE {
    my $self = shift;
    return $self->base_dir() . '/issuer_userdata.json';
}

sub get_system_wide_issuer {
    my $self = shift;

    my $userdata = $self->read_userdata();
    return $userdata->{'system_wide_issuer'} if $userdata->{'system_wide_issuer'};

    # Default to the system hostname if no 'issuer' is configured on the server.
    return Cpanel::Hostname::gethostname();
}

sub get_issuer {
    my ( $self, $username ) = @_;

    my $userdata = $self->read_userdata();

    return $userdata->{$username} if $userdata->{$username} && Cpanel::Reseller::isreseller($username);

    my $owner = Cpanel::AcctUtils::Owner::getowner($username);
    return $userdata->{$owner} if $userdata->{$owner};

    return $self->get_system_wide_issuer();
}

sub set_issuer {
    my ( $self, $username, $issuer ) = @_;
    return if $self->{'_read_only'};

    my $userdata = $self->read_userdata();
    if ( length $issuer ) {
        $userdata->{ $username ne 'root' ? $username : 'system_wide_issuer' } = $issuer;
    }
    else {
        delete $userdata->{ $username ne 'root' ? $username : 'system_wide_issuer' };
    }

    $self->{'_transaction_obj'}->set_data($userdata);

    return 1;
}

sub remove_issuer {
    my ( $self, $username ) = @_;
    return if $self->{'_read_only'};

    my $userdata = $self->read_userdata();
    return 1 if !exists $userdata->{$username};

    delete $userdata->{$username};
    $self->{'_transaction_obj'}->set_data($userdata);

    return 1;
}

1;
