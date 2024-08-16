package Cpanel::Init::Initd;

# cpanel - Cpanel/Init/Initd.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::Debug      ();
use Cpanel::LoadModule ();

extends 'Cpanel::Init::Base';

has 'check_config' => ( is => 'rw', default => '/sbin/chkconfig' );

sub BUILD {
    my ($self) = @_;

    $self->init_dir('/etc/init.d') if !$self->has_init_dir;
    $self->setup_enabler;

    return;
}

sub install_helpers {
    my ($self) = @_;

    my $from = $self->scripts_dir . $self->service_manager . '/' . 'cpfunctions';
    my $to   = $self->init_dir . '/';

    Cpanel::LoadModule::load_perl_module('File::Copy');
    my $copy_ok = File::Copy::copy( $from, $to );

    if ( !$copy_ok ) {
        my $err = $self->prog_name . ': Unable to copy cpfunctions to ' . $self->init_dir . ': ' . $!;
        Cpanel::Debug::log_warn($err);
        Cpanel::LoadModule::load_perl_module('Carp');
        Carp::croak($err);
    }

    return $copy_ok;
}

sub CMD_install_all {
    my ($self) = @_;

    my $retval = $self->SUPER::CMD_install_all;

    # Install cpfunctions too.
    $self->install_helpers();

    return $retval;
}

sub CMD_install {
    my ( $self, $service, @opts ) = @_;

    my $retval = $self->SUPER::CMD_install( $service, @opts );

    if ( !-e $self->init_dir . '/' . 'cpfunctions' ) {

        # Install cpfunctions too.
        $self->install_helpers();
    }
    return $retval;
}

1;

__END__

=head1 NAME

Cpanel::Init::Initd

=head1 PROTECTED INTERFACE

=head2 Methods

=over 4

=item CMD_install_all

This method will install all initscripts including the cpfunctions library.

=back
