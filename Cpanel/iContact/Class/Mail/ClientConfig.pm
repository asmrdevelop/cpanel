package Cpanel::iContact::Class::Mail::ClientConfig;

# cpanel - Cpanel/iContact/Class/Mail/ClientConfig.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::DAV::Provider ();

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my %service_to_required_args_map = (
    'email' => [
        qw{
          activesync_available
          activesync_port
          has_plaintext_authentication
          inbox_service
          inbox_username
          smtp_username
          display
          domain
          mail_domain
          inbox_host
          inbox_port
          inbox_insecure_port
          smtp_host
          smtp_port
          smtp_insecure_port
        }
    ],
    'caldav'  => ['cal_contacts_config'],
    'carddav' => ['cal_contacts_config'],
);

if ( !Cpanel::DAV::Provider::installed() ) {
    delete $service_to_required_args_map{'caldav'};
    delete $service_to_required_args_map{'carddav'};
}

my @required_args = qw(
  selected_account_services
  account
);
my @optional_args = qw(from_archiving selected_device);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args )
    );
}

sub _verify_required_args {
    my ( $class, %opts ) = @_;

    # Augment required args before verification based on the services
    # under consideration
    foreach my $service ( keys( %{ $opts{'selected_account_services'} } ) ) {
        next if !exists( $service_to_required_args_map{$service} );
        push @required_args, @{ $service_to_required_args_map{$service} };
    }

    return $class->SUPER::_verify_required_args(%opts);
}

1;
