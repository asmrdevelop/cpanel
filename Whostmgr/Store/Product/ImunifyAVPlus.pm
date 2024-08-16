
# cpanel - Whostmgr/Store/Product/ImunifyAVPlus.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Store::Product::ImunifyAVPlus;

use strict;
use warnings;
use Cpanel::Autodie::IO     ();
use Cpanel::Autodie::Open   ();
use Cpanel::FindBin         ();
use Cpanel::Binaries        ();
use Cpanel::JSON            ();
use Cpanel::OS              ();
use Cpanel::SafeRun::Object ();

use Cpanel::Locale 'lh';

use base 'Whostmgr::Store';

=head1 NAME

Whostmgr::Store::Product::ImunifyAVPlus - Purchase and install implementation
subclass for ImunifyAV+

=cut

###########################################################
# Constants
###########################################################

use constant HUMAN_PRODUCT_NAME => 'ImunifyAV+';

# for verify.cpanel.net
use constant PRODUCT_ID    => 'ImunifyAV+';
use constant PACKAGE_ID_RE => qr/IMUNIFYAV\+/;
use constant CPLISC_ID     => 'immunifyav';      # XXX this misspelling is in the license system

use constant STORE_ID_UNLIMITED => 447;
use constant STORE_ID_SOLO      => 447;

use constant MANAGE2_PRODUCT_NAME => 'imunify_av_plus';

# Everything else ...
use constant RPM_NAME           => 'imunify-antivirus';
use constant INSTALL_GET_URL    => 'https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh';
use constant PID_FILE           => '/var/run/store-imunifyavplus-install-running';
use constant LOG_PATH           => '/var/cpanel/logs/imunifyavplus-install.log';
use constant PURCHASE_START_URL => 'scripts14/purchase_imunifyavplus_init';

sub IS_AVAILABLE_ON_THIS_OS {
    return Cpanel::OS::supports_imunify_av_plus();
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

=head2 install_implementation()

The implementation of the installation. This is not meant to be called
directly, but rather as part of the install interface offered by the
parent class.

=cut

sub install_implementation {
    my ($self) = @_;

    my $IMUNIFY_INSTALL_TIMEOUT = 300;

    my ( $temp, $temp_filename ) = $self->get_installer();

    my $bash_bin = Cpanel::Binaries::path('bash');
    die lh()->maketext('The system could not find the “[asis,bash]” binary in the expected location while preparing to install [asis,ImunifyAV+].') if !-x $bash_bin;

    Cpanel::Autodie::Open::open( my $log_fh, '>>', $self->LOG_PATH );

    my $install_obj = Cpanel::SafeRun::Object->new(
        program => $bash_bin,
        args    => [
            $temp_filename,
            qw{--key IPL},    # 'IPL' means this is an IP-based license. See https://docs.imunifyav.com/imunifyav/
        ],
        after_fork => sub {
            $0 = 'Install ImunifyAV+';
        },
        stdout  => $log_fh,
        stderr  => $log_fh,
        timeout => $IMUNIFY_INSTALL_TIMEOUT,
    );

    Cpanel::Autodie::IO::close($log_fh);

    if ( $install_obj->CHILD_ERROR() ) {
        my $tail_bin = Cpanel::Binaries::path('tail');
        my $tail_obj = Cpanel::SafeRun::Object->new(
            program => $tail_bin,
            args    => [
                '-n20',
                $self->LOG_PATH
            ],
        );
        die lh()->maketext( 'The log file contained the following information: [_1]', $tail_obj->stdout );
    }

    return 1;
}

sub handle_error {
    my ( $self, %args ) = @_;
    return $self->default_error_handler(%args);
}

=head2 ensure_installed()

This implementation is for ImunifyAV+ only:

Overrides the parent class method so as to force an "install" even when the RPM is already present.
This is necessary for ImunifyAV+ because both the free version and the paid version use the exact same
RPM. The RPM is normally how we check whether something is installed, but in the case of an upgrade from
ImunifyAV to ImunifyAV+, we still need to use the install script for activating the license, even though
the RPMs themselves are already there.

=cut

sub ensure_installed {
    my ($self) = @_;

    my ( $install_ok, $install_detail ) = $self->install();

    my $ok = $self->is_product_installed();

    local $@;
    $ok &&= eval {
        my $json         = _get_iav_rstatus();
        my $license_info = Cpanel::JSON::Load($json);

        if ( $license_info->{license_type} ne 'imunifyAVPlus' && $license_info->{license_type} ne 'imunify360' ) {    # 360 for IPs that automatically get a 360 license
            die "Got unexpected license type '$license_info->{license_type}'\n";
        }
        1;
    };
    $install_detail .= "\n$@" if $@;

    return ( $ok ? 1 : 0, $install_detail );
}

sub _get_iav_rstatus {

    # both utilities have the same rstatus usage
    my $utility = Cpanel::FindBin::findbin('imunify-antivirus') || Cpanel::FindBin::findbin('imunify360-agent');

    if ( !$utility ) {
        die "Neither imunify-antivirus nor imunify360-agent found. Cannot look up license status.\n";
    }

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => $utility,
        args    => [qw(rstatus --json)],
    );

    return $run->stdout;
}

1;
