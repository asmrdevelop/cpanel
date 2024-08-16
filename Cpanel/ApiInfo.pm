package Cpanel::ApiInfo;

# cpanel - Cpanel/ApiInfo.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Transaction::File::JSONReader ();

sub LOCAL_SPEC_FILE_DIR {
    return '/var/cpanel/api_spec';
}

sub SYSTEM_SPEC_FILE_DIR {
    return '/usr/local/cpanel/var/api_spec';
}

sub SPEC_FILE_PATH {
    my ($self) = @_;

    my $file_name = $self->SPEC_FILE_BASE();

    #FIXME: would it be better to just overwrite this?
    return ( $file_name =~ /dist/ ? $self->SYSTEM_SPEC_FILE_DIR() : $self->LOCAL_SPEC_FILE_DIR() ) . '/' . $self->SPEC_FILE_BASE() . '.json';
}

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    if ( $> == 0 ) {
        my $base_dir = ( $class =~ m/dist/i ) ? $self->SYSTEM_SPEC_FILE_DIR() : $self->LOCAL_SPEC_FILE_DIR();
        if ( -d $base_dir ) {
            chmod( 0755, $base_dir );
        }
        else {
            require Cpanel::SafeDir::MK;
            Cpanel::SafeDir::MK::safemkdir( $base_dir, '0755' ) or do {
                die "The system failed to create the directory $base_dir because of an error: $!\n";
            };
        }
    }

    return $self;
}

sub verify {
    my ($self) = @_;

    require Cpanel::Transaction::File::JSON;
    my $transaction = Cpanel::Transaction::File::JSON->new(
        path        => $self->SPEC_FILE_PATH(),
        permissions => 0644,
    );

    my $need_update = $self->_update_transaction($transaction);

    if ($need_update) {
        $transaction->save_canonical_or_die();
    }

    my ( $close_ok, $close_err ) = $transaction->close();
    die $close_err if !$close_ok;

    return $need_update;
}

sub get_data {
    my ($self) = @_;

    my $sp = $self->SPEC_FILE_PATH();

    my $datastore = Cpanel::Transaction::File::JSONReader->new( path => $self->SPEC_FILE_PATH() );

    return $self->_get_public_data_from_datastore($datastore);
}

1;
