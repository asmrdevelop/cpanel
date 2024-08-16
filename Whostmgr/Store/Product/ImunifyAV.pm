
# cpanel - Whostmgr/Store/Product/ImunifyAV.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Store::Product::ImunifyAV;

use strict;
use warnings;
use Cpanel::Autodie::IO     ();
use Cpanel::Autodie::Open   ();
use Cpanel::Binaries        ();
use Cpanel::Logger          ();
use Cpanel::OS              ();
use Cpanel::Pkgr            ();
use Cpanel::SafeRun::Object ();

use Cpanel::Locale 'lh';

use base 'Whostmgr::Store';

=head1 NAME

Whostmgr::Store::Product::ImunifyAV - Install implementation subclass
for ImunifyAV (non-paid version)

=cut

###########################################################
# Extra Special Love (unique to this module)
###########################################################

# We have to write this file or we default to providing the upsell to
# ImunifyAVPlus via CloudLinux.
use constant BILLING_CONFIG => '/etc/sysconfig/imunify360/custom_billing.config';

# This touch file is not used by this module. It is only used by
# Cpanel::TaskProcessors::ImunifyTasks, which itself is only used
# when installing ImunifyAV as part of the initial cPanel installation.
use constant DISABLE_TOUCH_FILE => '/var/cpanel/noimunifyav';

###########################################################
# Constants
###########################################################

use constant HUMAN_PRODUCT_NAME => 'ImunifyAV';

# License system - not applicable to this package (see is_product_licensed method override)
use constant PRODUCT_ID    => 'n/a';
use constant PACKAGE_ID_RE => 'n/a';
use constant CPLISC_ID     => 'n/a';

# Store
use constant STORE_ID_UNLIMITED => 'n/a';
use constant STORE_ID_SOLO      => 'n/a';

# Manage2
use constant MANAGE2_PRODUCT_NAME => 'n/a';

# Everything else ...
use constant RPM_NAME        => 'imunify-antivirus';
use constant INSTALL_GET_URL => 'https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh';
use constant PID_FILE        => '/var/run/store-imunifyav-install-running';
use constant LOG_PATH        => '/var/cpanel/imunifyav-install.log';

#Intentionally left blank, there is no purchase here.
use constant PURCHASE_START_URL => '/';

sub IS_AVAILABLE_ON_THIS_OS {
    return Cpanel::OS::supports_imunify_av();
}

use constant SERVER_TYPE_AVAILABILITY => {
    standard  => 1,
    vm        => 1,
    container => 0,
};

use constant HOST_LICENSE_TYPE_AVAILABILITY => {
    unlimited => 1,
    solo      => 1,
};

###########################################################
# Implementation of core functionality
###########################################################

=head1 OBJECT INTERFACE

The purchase and install interface of this class is the same one
offered by the parent class. See C<Whostmgr::Store> for documentation
on this.

=head1 IMPLEMENTATION METHODS (not meant to be called directly)

=head2 new()

Takes one extra argument more than the parent class.

=over

=item * wait - Bool (Optional) - Tells the installer if we want to wait for it to finish or run in the background.

=back

=cut

sub new {
    my ( $package, %opts ) = @_;

    my $self = $package->SUPER::new(%opts);
    $self->{wait} = $opts{wait} ? 1 : 0;
    return $self;
}

=head2 install_implementation()

The implementation of the installation. This is not meant to be called
directly, but rather as part of the install interface offered by the
parent class.

=cut

sub install_implementation {
    my ($self) = @_;

    my $IMUNIFYAV_INSTALL_TIMEOUT = 300;

    my ( $temp, $temp_filename ) = $self->get_installer();

    my $bash_bin = Cpanel::Binaries::path('bash');
    die lh()->maketext('The system could not find the “[asis,bash]” binary in the expected location while preparing to install [asis,ImunifyAV].') if !-x $bash_bin;

    Cpanel::Autodie::Open::open( my $log_fh, '>>', $self->LOG_PATH );

    my $lock_logger              = Cpanel::Logger->new( { alternate_logfile => $self->LOG_PATH } );
    my $lock_released_on_destroy = Cpanel::Pkgr::lock_for_external_install($lock_logger);

    my $install_obj = Cpanel::SafeRun::Object->new(
        program => $bash_bin,
        args    => [
            $temp_filename,
        ],
        after_fork => sub {
            $0 = 'Install ImunifyAV';
        },
        stdout  => $log_fh,
        stderr  => $log_fh,
        timeout => $IMUNIFYAV_INSTALL_TIMEOUT,
    );

    Cpanel::Autodie::IO::close($log_fh);

    if ( $install_obj->CHILD_ERROR() ) {
        my $tail_bin = Cpanel::Binaries::path('tail');
        my $tail_obj = Cpanel::SafeRun::Object->new_or_die(
            program => $tail_bin,
            args    => [
                '-n20',
                $self->LOG_PATH
            ],
        );
        die lh()->maketext( 'The log file contained the following information: [_1]', $tail_obj->stdout );
    }

    write_billing_config();

    return 1;
}

=head2 write_billing_config()

Special mechanism to configure upsells from WITHIN ImunifyAV (outside of WHM).

=cut

sub write_billing_config {
    open( my $fh, '>', BILLING_CONFIG ) or die "Couldn't open file $!";

    my $conf_file = <<~END_OF_CONFIG;
      CUSTOM_BILLING:
        upgrade_url: ../../../scripts14/purchase_imunifyavplus_init_IMUNIFY
        billing_notifications: false
        ip_license: true
      END_OF_CONFIG

    print $fh $conf_file;

    close($fh);

    return 1;
}

=head2 handle_error()

The error handling implementation. This is not meant to be called directly.

=cut

sub handle_error {
    my ( $self, %args ) = @_;

    die $args{error};
}

=head2 is_product_licensed()

For ImunifyAV (the free version, as opposed to ImunifyAV+), this is always true because
the license is valid without any purchase.

=cut

sub is_product_licensed {
    return 1;
}

=head2 get_product()

This method should not be called because the Store interaction is skipped for ImunifyAV.
The method override is just to ensure that any incorrect use is flagged directly rather
than through a confusing failure later in the process.

=cut

sub get_product {
    require Carp;
    Carp::confess('Not applicable');
}

=head2 wait_for_daemon()

(instance method)

ImunifyAV.pm overrides this method to allow the install to go into the background.
The zero return indicates that waiting did not happen, so no attempt will be made
to (prematurely) inpsect the log for an outcome.

We run the normal parent class version of this method if the wait object attribute
is set to true.

=cut

sub wait_for_daemon {
    my ( $self, $pid, $interval ) = @_;

    return $self->SUPER::wait_for_daemon( $pid, $interval ) if $self->{wait};
    return 0;
}

1;
