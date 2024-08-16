
# cpanel - Whostmgr/Imunify360.pm                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Imunify360;

use cPstrict;
use Carp ();

use Try::Tiny;

use Cpanel::Autodie::IO                  ();
use Cpanel::Autodie::Open                ();
use Cpanel::Binaries                     ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::KernelCare                   ();
use Cpanel::Logger                       ();
use Cpanel::OS                           ();
use Cpanel::ProcessCheck::Outdated       ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Systemd                      ();
use Whostmgr::KernelCare                 ();
use Whostmgr::Plugins                    ();
use Whostmgr::Templates::Chrome::Rebuild ();

use Cpanel::Locale 'lh';

use base 'Whostmgr::Store';

###########################################################
# Constants
###########################################################

use constant BACKGROUND_INSTALL       => 1;
use constant HUMAN_PRODUCT_NAME       => 'Imunify360';
use constant INSTALL_DURATION_WARNING => 15;

# These two ids were verified as correct 2019-02-11 using https://verify.cpanel.net/api/addons?ip=...... for a licensed IP address
use constant PRODUCT_ID    => 'Imunify360';
use constant PACKAGE_ID_RE => qr/-IMUNIFY360-/;    # e.g., PARTNERNAME-IMUNIFY360-UNLIMITED or ANOTHERNAME-IMUNIFY360-SOLO
use constant CPLISC_ID     => 'immunify360';       # XXX this misspelling is in the license system

# These two short names were verified as correct 2019-02-08 using https://aa.store.manage.testing.cpanel.net/
use constant STORE_ID_UNLIMITED => 373;                                                                     # monthly_imunify360_unlimited
use constant STORE_ID_SOLO      => 369;                                                                     # monthly_imunify360_solo
use constant RPM_NAME           => 'imunify360-firewall';                                                   # RPM Name
use constant INSTALL_GET_URL    => 'https://www.repo.imunify360.cloudlinux.com/defence360/i360deploy.sh';
use constant PURCHASE_START_URL => 'scripts14/purchase_imunify360_init';
use constant PID_FILE           => '/var/run/store-imunify360-install-running';
use constant LOG_PATH           => '/var/cpanel/logs/imunify360-install.log';

use constant MANAGE2_PRODUCT_NAME => 'imunify360';

sub IS_AVAILABLE_ON_THIS_OS {
    return Cpanel::OS::supports_imunify_360();
}

use constant SERVER_TYPE_AVAILABILITY => {
    standard  => 1,
    vm        => 1,
    container => 1,
};

use constant HOST_LICENSE_TYPE_AVAILABILITY => {
    unlimited => 1,
    solo      => 1,
};

use constant AGENT_READ_TIMEOUT => 60;

###########################################################
# Implementation of core functionality
###########################################################

sub new {
    my ( $package, %attrs ) = @_;

    $attrs{redirect_path} //= 'cgi/securityadvisor/index.cgi';
    return $package->SUPER::new(%attrs);
}

sub install_implementation {
    my ($self) = @_;

    # should not go more than 5 minutes without some sort of output from the installer
    my $IMUNIFY360_INSTALL_READ_TIMEOUT = 300;

    my ( $temp, $temp_filename ) = $self->get_installer();

    my $bash_bin = Cpanel::Binaries::path('bash');
    die lh()->maketext('The system could not find the “[asis,bash]” binary in the expected location while preparing to install [asis,Imunify360].') if !-x $bash_bin;

    Cpanel::Autodie::Open::open( my $log_fh, '>', $self->LOG_PATH );

    Cpanel::SafeRun::Object->new_or_die(
        program => $bash_bin,
        args    => [
            $temp_filename,
            '--yes',    # See LC-10633
            '--key',
            'IPL',
        ],
        after_fork => sub {
            $0 = 'Install Imunify360';
        },
        stdout       => $log_fh,
        stderr       => $log_fh,
        read_timeout => $IMUNIFY360_INSTALL_READ_TIMEOUT,
    );

    Cpanel::Autodie::IO::close($log_fh);

    $self->_install_kc_extra_if_applicable();

    $self->_restart_outdated_services();

    # This should be done automatically when the plugin is registered with AppConfig, but for now
    # we are working around the problem this way. This is to get the entry to show up in the WHM
    # navigation bar.
    Whostmgr::Plugins::update_cache();
    Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();

    $self->_register_IPL;

    return 1;
}

sub handle_error {
    my ( $self, %args ) = @_;
    return $self->default_error_handler(%args);
}

###########################################################
# Imunify360-specific helpers
###########################################################

sub _install_kc_extra_if_applicable {
    my ($self) = @_;

    eval {
        if ( $self->_kc_extra_needed() ) {
            Cpanel::KernelCare::set_extra_patch();
        }
    };
    if ( my $exception = $@ ) {
        die Cpanel::Exception::create(
            'Store::PartialSuccess',
            [
                detail => Cpanel::Exception::get_string($exception),
            ],
        );
    }
    return;
}

sub _install_kernelcare_via_whostmgr_kernelcare {
    Whostmgr::KernelCare->new()->ensure_kernelcare_installed();
    return;
}

sub _kc_extra_needed {
    my ($self) = @_;

    return if not $self->needs_kernelcare();

    my $kc_state = Cpanel::KernelCare::get_kernelcare_state();
    if ( $kc_state == $Cpanel::KernelCare::KC_NONE || $kc_state == $Cpanel::KernelCare::KC_MISSING ) {

        _install_kernelcare_via_whostmgr_kernelcare();
        $kc_state = Cpanel::KernelCare::get_kernelcare_state();
    }

    # "Extra" is the highest KernelCare state. We only need to switch if we're not already on "extra."
    return if $kc_state == $Cpanel::KernelCare::KC_EXTRA_PATCH_SET;

    return 1;
}

sub get_kernelcare_manage2_data ($self) {
    return $self->get_manage2_data('kernelcare');
}

sub needs_kernelcare ($self) {

    return 0 unless Cpanel::OS::supports_kernelcare();

    # It doesn't make sense to attempt to manage the kernel of a container from within the container.
    return 0 if $self->server_type eq 'container';

    # Partners may disable KernelCare availability via Manage2
    return 0 if $self->get_manage2_data('kernelcare')->{'disabled'};

    return 1;
}

sub _restart_outdated_services {
    eval {
        my $service_bin = Cpanel::Binaries::path('service');

        my @services = Cpanel::ProcessCheck::Outdated::outdated_services();

        my @imunify_services = grep { /imunify360|wsshdict/ } @services if (@services);

        if (@imunify_services) {
            my $logger = Cpanel::Logger->new();
            $logger->info("Outdated Services found:");

            foreach my $service (@services) {
                $logger->info("-- $service");

                Cpanel::SafeRun::Object->new_or_die(
                    program => $service_bin,
                    args    => [ $service, 'restart' ],
                );
            }
        }
    };
    if ( my $exception = $@ ) {
        die Cpanel::Exception::create(
            'Store::PartialSuccess',
            [
                detail => Cpanel::Exception::get_string($exception),
            ],
        );
    }
    return;
}

sub is_running {
    my ($self) = @_;

    return try {
        Cpanel::Systemd::systemctl( '--quiet', 'is-active', 'imunify360.service' );
        1;
    }
}

# Custom method for Imunify360 only (not part of Store.pm interface).
# Give it a $checker sub that inspects the parsed Imunify360
# configuration for the presence of some wanted or unwanted setting
# and returns either a true/false value or something else, like
# the value of the setting itself.
#
# Use `imunify360-agent config show --json -v` as a reference for
# which settings exist.
#
# Example usage:
#
# if ( Whostmgr::Imunify360->new()->check_config( sub { shift()->{'items'}{'SMTP_BLOCKING'}{'enable'} } ) ) {
#     ... # SMTP_BLOCKING is enabled
# }
sub check_config {
    my ( $self, $checker ) = @_;
    Carp::croak('You must provide a subroutine to check_config()') if ref $checker ne 'CODE';
    my $agent_bin = _agent_bin();
    my $outcome   = eval {
        my $agent_obj = Cpanel::SafeRun::Object->new_or_die(
            program      => $agent_bin,
            args         => [ 'config', 'show', '--json' ],
            read_timeout => AGENT_READ_TIMEOUT,
        );
        my $config = Cpanel::JSON::Load( $agent_obj->stdout );
        $checker->($config);
    };
    if ( my $exception = $@ ) {
        my $logger = Cpanel::Logger->new();
        $logger->info("Unable to check Imunify360 configuration: $exception");
        return;
    }
    return $outcome;
}

###########################################################
# v80 compatibility
###########################################################

sub get_imunify360_data {
    return __PACKAGE__->new->get_manage2_data('imunify360');
}

sub is_imunify360_licensed {
    return __PACKAGE__->new->is_product_licensed;
}

sub is_imunify360_installed {
    return __PACKAGE__->new->is_product_installed;
}

sub get_imunify360_price {
    return __PACKAGE__->new->get_product_price;
}

sub get_kernelcare_data {
    return __PACKAGE__->new->get_kernelcare_manage2_data();
}

sub _agent_bin {
    return Cpanel::Binaries::path('imunify360-agent');
}

sub _register_IPL {
    my $agent_bin = _agent_bin();
    eval {
        Cpanel::SafeRun::Object->new_or_die(
            program      => $agent_bin,
            args         => [qw(register IPL)],
            read_timeout => AGENT_READ_TIMEOUT,
        );
    };
    if ( my $exception = $@ ) {
        my $logger = Cpanel::Logger->new();
        $logger->info("imunify360-agent register IPL: $exception");
    }
    return;
}

1;
