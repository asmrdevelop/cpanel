package Cpanel::SSLInstall::Service;

# cpanel - Cpanel/SSLInstall/Service.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Crypt::Algorithm ();
use Cpanel::SSLStorage::User ();
use Cpanel::OrDie            ();
use Cpanel::SSLInfo          ();
use Cpanel::SSLCerts         ();
use Cpanel::ServerTasks      ();

sub new {
    my ($class) = @_;

    return bless { '_cache' => {} }, $class;
}

sub install_cert_on_service_with_assets_from_sslstorage {
    my ( $self, %opts ) = @_;

    my $service  = $opts{'service'};
    my $cert_pem = $opts{'cert_pem'};

    foreach my $required (qw(service cert_pem)) {
        if ( !$opts{$required} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'MissingParameter', [ name => $required ] );
        }
    }

    my ( $key, $cabundle ) = $self->_save_cert_and_get_key_and_cabundle($cert_pem);

    # Send a notification upon install?
    my ( $status, $message ) = Cpanel::SSLCerts::installSSLFiles(    #
        'service' => $service,                                       #
        'crt'     => $cert_pem,                                      #
        'key'     => $key,                                           #
        ( $cabundle ? ( 'cab' => $cabundle ) : () )                  #
    );

    if ( !$status ) {
        warn $message;
        return 0;
    }

    return $self->_restart_service($service);
}

# tested directly
sub _save_cert_and_get_key_and_cabundle {
    my ( $self, $cert_pem ) = @_;
    my $storage = Cpanel::SSLStorage::User->new();
    my $retval  = Cpanel::OrDie::multi_return( sub { $storage->add_certificate( text => $cert_pem ); } );
    my $cert_id = $retval->{'id'};
    if ( !$self->{'_cache'}{'cabundle'}{$cert_id} ) {
        my $payload = Cpanel::OrDie::multi_return( sub { Cpanel::SSLInfo::fetch_crt_info( $cert_id, 'root' ) } );
        $self->{'_cache'}{'cabundle'}{$cert_id} = $payload->{'cabundle'};
    }
    my $cabundle = $self->{'_cache'}{'cabundle'}{$cert_id};

    my $key_cache_index = $retval->{'key_algorithm'};
    $key_cache_index .= '-' . Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $retval,
        rsa   => sub { $retval->{'modulus'} },
        ecdsa => sub {
            $retval->{'ecdsa_curve_name'} . '-' . $retval->{'ecdsa_public'};
        },
    );

    if ( !$self->{'_cache'}{'key'}{$key_cache_index} ) {
        my $keys = Cpanel::OrDie::multi_return(
            sub {
                $storage->find_keys(
                    map { $_ => $retval->{$_} } (
                        'key_algorithm',
                        'modulus',
                        'ecdsa_curve_name',
                        'ecdsa_public',
                    )
                );
            }
        );
        $self->{'_cache'}{'key'}{$key_cache_index} = $storage->get_key_text( $keys->[0] );
    }
    my $key = $self->{'_cache'}{'key'}{$key_cache_index} or die "install_cert_on_service_with_assets_from_sslstorage could not locate the key for the certificate";

    return ( $key, $cabundle );
}

sub _restart_service {
    my ( $self, $service ) = @_;

    # This must be done in the taskqueue otherwise we get unexpected
    # starts on fresh installs
    if ( $service eq 'cpanel' ) {

        # We use the same certificates for HTTPS service (formerly proxy) subdomains as we do for
        # cpsrvd, so ensure that that the configuration refers to the correct
        # one of cpanel.pem or mycpanel.pem.
        eval { Cpanel::ServerTasks::queue_task( [ 'CpServicesTasks', 'ApacheTasks' ], 'build_apache_conf', 'apache_restart --force', 'restartsrv cpsrvd', 'restartsrv cpdavd' ); };
    }
    else {
        # TODO: once we get rid of the wrappers for restartsrv_ftpserver, restartsrv_ftpd and can
        # make a symlink for restartsrv_ftp we can get rid of this ftp->ftpd rewrite
        my $restartsrv_name = ( $service eq 'ftp' ? 'ftpd' : $service );
        eval { Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], "restartsrv $restartsrv_name" ); };
    }

    return 1;
}

1;
