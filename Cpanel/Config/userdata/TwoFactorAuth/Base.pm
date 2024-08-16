package Cpanel::Config::userdata::TwoFactorAuth::Base;

# cpanel - Cpanel/Config/userdata/TwoFactorAuth/Base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Transaction::File::JSONReader ();

# Used for mocking in unit tests
sub base_dir { return '/var/cpanel/authn/twofactor_auth'; }

sub new {
    my ( $class, $opts ) = @_;
    die "Can not initialize the base class directly" if $class eq __PACKAGE__;

    $opts = {} if !$opts || ref $opts ne 'HASH';

    my $self = bless {}, $class;
    $self->_initialize($opts);

    return $self;
}

sub read_userdata {
    my $self = shift;
    return $self->{'_data'} if $self->{'_data'} && 'HASH' eq ref $self->{'_data'};

    my $data = $self->{'_transaction_obj'}->get_data();
    $self->{'_data'} = ( ref $data eq 'SCALAR' ? ${$data} : $data ) || {};
    return $self->{'_data'};
}

sub save_changes_to_disk {
    my $self = shift;
    return if $self->{'_read_only'};

    return $self->{'_transaction_obj'}->save_or_die();
}

sub _initialize {
    my ( $self, $opts ) = @_;

    if ( !-d base_dir() ) {
        _create_base_dir();
    }

    my %new_args = (
        path        => $self->DATA_FILE(),
        permissions => 0600,
        ownership   => [ 0, 0 ],
    );

    if ( $opts && $opts->{'read_only'} ) {
        $self->{'_read_only'}       = 1;
        $self->{'_transaction_obj'} = Cpanel::Transaction::File::JSONReader->new(%new_args);

    }
    else {
        require Cpanel::Transaction::File::JSON;
        $self->{'_transaction_obj'} = Cpanel::Transaction::File::JSON->new(%new_args);
    }

    return 1;
}

sub _create_base_dir {
    #
    # This logic is tied to how permissions on /var/cpanel have to be set:
    #
    # /var/cpanel has to be 755
    # /var/cpanel/authn has to be 711
    # and finally, our directory has to be only accessible to root
    # /var/cpanel/authn/twofactor_auth has to be 700
    #
    # In reality we will most likely never get to a stage where
    # /var/cpanel doesn't exist when we hit this code path, but the 'fallback'
    # code exists to ensure that this call itself doesn't fail in such situations.
    require File::Path;
    require File::Spec;
    my @dirs    = File::Spec->splitdir( base_dir() );
    my $top_dir = File::Spec->catfile( @dirs[ 0 .. 2 ] );
    File::Path::make_path( $top_dir, { 'mode' => 0755 } ) if !-e $top_dir;
    foreach my $index ( 3 .. $#dirs ) {
        $top_dir = File::Spec->catfile( $top_dir, $dirs[$index] );
        if ( $index != $#dirs ) {
            File::Path::make_path( $top_dir, { 'mode' => 0711 } ) if !-e $top_dir;
        }
        else {
            File::Path::make_path( $top_dir, { 'mode' => 0700 } ) if !-e $top_dir;
        }
    }

    return;
}

1;
