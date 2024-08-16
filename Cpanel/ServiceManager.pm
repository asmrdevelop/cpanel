package Cpanel::ServiceManager;

# cpanel - Cpanel/ServiceManager.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 MODULE

=head2 NAME

Cpanel::ServiceManager

=head2 DESCRIPTION

Base instantiator module for Cpanel::ServiceManager services. Provided merely as convenience to callers.

=head2 SYNOPSIS

    my $service = Cpanel::ServiceManager->new( 'service' => $DESIRED_SERVICE );

=cut

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::LoadModule::Custom           ();
use Cpanel::RestartSrv::Initd            ();
use Cpanel::RestartSrv::Systemd          ();
use Cpanel::ServiceManager::Base         ();
use Cpanel::LoadModule                   ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::LoadModule::Utils            ();

=head1 METHODS

=head2 OBJECT

=head3 new

Creates an instance of the specified service object from the Cpanel::ServiceManager::Service namespace based on the L<Cpanel::ServiceManager::Base> class.

Note: this method will throw an exception on error.

B<Input>

    HASH of options
        service - name of service from Cpanel::ServiceManager::Service namespace or a systemd service name like “getty@tty1”

B<Output>

    OBJECT based on Cpanel::ServiceManager::Base from Cpanel::ServiceManager::Service::$service

=cut

sub new {
    my ( $class, %opts ) = @_;

    if ( !$opts{service} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("[ARGUMENT] You must supply the service name.");    # no passwords please
    }

    my $module = ( $opts{'service'} =~ tr<A-Z><a-z>r );
    substr( $module, 0, 1 ) =~ tr<a-z><A-Z>;                                                #capitalize

    #e.g., for the cpanel-dovecot-solr plugin
    $module =~ tr<-><_>;

    my $package = __PACKAGE__ . "::Services::$module";

    my $load_err;
    if ( Cpanel::LoadModule::Utils::is_valid_module_name($package) ) {
        local $@;
        if ( eval { Cpanel::LoadModule::Custom::load_perl_module($package); 1 } ) {
            return $package->new(%opts);
        }
        $load_err = $@;
        if ( eval { $load_err->isa('Cpanel::Exception::ModuleLoadError') } ) {

            if ( $load_err->get('error') !~ m{locate.*in.*\@INC} ) {

                # If its not a missing module we should log
                # so we do not guess what is going on here
                local $@ = $load_err;
                warn;
            }
        }
    }

    Cpanel::Validate::FilesystemNodeName::validate_or_die( $opts{'service'} );

    # if this is an init/systemd script, use the base object #
    if ( Cpanel::RestartSrv::Initd::has_service_via_initd( $opts{'service'} ) || Cpanel::RestartSrv::Systemd::has_service_via_systemd( $opts{'service'} ) ) {

        # if the service is managed by systemd or initd,
        # then avoid the "service enabled" checks as we
        # perform the restarts directly through those systems.
        #
        # TODO: query initd/systemd for the disabled status
        return Cpanel::ServiceManager::Base->new( %opts, is_enabled => 1 );
    }

    # preserve the original error message on a sandbox for easier development
    die Cpanel::Exception::create( 'Services::Unknown', [ 'service' => $opts{'service'}, 'longmess' => $opts{'longmess'} ] )
      if !$load_err || !-e q{/var/cpanel/dev_sandbox};

    local $@ = $load_err;
    die;

}

1;

__END__

=head1 MISC

=head2 SEE ALSO

L<Cpanel::ServiceManager::Base>
