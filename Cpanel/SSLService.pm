package Cpanel::SSLService;

# cpanel - Cpanel/SSLService.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Config::LoadConfig ();
use Cpanel::SSL::Defaults      ();
use Cpanel::LoadFile           ();
use Cpanel::NetSSLeay::BIO     ();

our $DHPARAM_PATH = '/usr/local/cpanel/etc/dhparam_from_cpanel.pem';

my $dh;

=head1 NAME

Cpanel::SSLService

=head1 DESCRIPTION

Load SSL settings for cpsrvd and cpdavd

=head1 FUNCTIONS

=cut

sub getsslargs {
    my ($service_name) = @_;
    $service_name ||= '';

    my %ARGS = ( 'SSL_use_cert' => '1' );
    if ( -e '/var/cpanel/ssl/cpanel/mycpanel.pem' ) {
        $ARGS{'SSL_cert_file'} = $ARGS{'SSL_key_file'} = '/var/cpanel/ssl/cpanel/mycpanel.pem';
    }
    elsif ( -e '/var/cpanel/ssl/cpanel/cpanel.pem' ) {
        $ARGS{'SSL_cert_file'} = $ARGS{'SSL_key_file'} = '/var/cpanel/ssl/cpanel/cpanel.pem';
    }
    else {
        die 'SSL PEM file (/var/cpanel/ssl/cpanel/(my)?cpanel.pem) is missing!';
    }
    if ( -e '/var/cpanel/ssl/cpanel/mycpanel.cabundle' ) {
        $ARGS{'SSL_ca_file'} = '/var/cpanel/ssl/cpanel/mycpanel.cabundle';
    }

    if ($service_name) {
        if ( -d "/var/cpanel/conf/$service_name" && -e "/var/cpanel/conf/$service_name/ssl_socket_args" ) {

            # Usage is safe as we own the dir and file
            my $srv_config_hr = Cpanel::Config::LoadConfig::loadConfig( "/var/cpanel/conf/$service_name/ssl_socket_args", -1, '=' );
            if ( $srv_config_hr && ref $srv_config_hr ) {

                $srv_config_hr = validate_ssl_args( \%ARGS, $srv_config_hr );
                if ($srv_config_hr) {
                    %ARGS = ( %ARGS, %{$srv_config_hr}, );
                }
                else {
                    warn "$service_name: invalid SSL settings loaded from /var/cpanel/conf/$service_name/ssl_socket_args; using defaults";
                }
            }
        }
    }

    # TODO: Consolidate cipher string to cpanel.config
    $ARGS{'SSL_cipher_list'} ||= Cpanel::SSL::Defaults::default_cipher_list();
    $ARGS{'SSL_version'}     ||= Cpanel::SSL::Defaults::default_protocol_list( { 'type' => 'negative', 'delimiter' => ':', 'negation' => '!', separator => '_' } );
    $ARGS{'SSL_ca_file'}     ||= '';                                                                                                                                  #prevent stating random files
    $ARGS{'SSL_dh'}          ||= _get_memorized_dh();

    return %ARGS;
}

=head2 validate_ssl_args($args, $to_validate)

Validate that the arguments in C<$to_validate> (a hashref) are suitable for
creating an SSL context with IO::Socket::SSL.  C<$args> is a hashref of
arguments that are assumed to be known-good, such as SSL certificate path.

The combination of the two must be sufficient to instantiate an SSL context.

Returns C<$to_validate> on success and undef on failure.  Due to the limitations
of the validation technique, no information is available as to what caused
validation to fail.

=cut

sub validate_ssl_args {
    my ( $args, $to_validate ) = @_;

    my $ctx = try {

        require IO::Socket::SSL;
        IO::Socket::SSL::SSL_Context->new( ( %$args, %$to_validate ) );
    };

    # If the context was created successfully, the args are at least basically
    # valid.  We may have still specified something unusable (like an unusable
    # cipher suite list), but this is the best we can do here.
    return $ctx ? $to_validate : undef;
}

sub _get_memorized_dh {
    return $dh ||= do {
        my $parm_text = Cpanel::LoadFile::load($DHPARAM_PATH);

        my $bio_obj = Cpanel::NetSSLeay::BIO->new_s_mem();
        $bio_obj->write($parm_text);

        $bio_obj->PEM_read_bio_DHparams();
    };
}

1;
