package Cpanel::Sysup;

# cpanel - Cpanel/Sysup.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This script ensures a minimal set of packages are (and stay) installed for cPanel

use cPstrict;

use Try::Tiny;

use Cpanel::EA4::Install      ();
use Cpanel::Debug             ();
use Cpanel::ConfigFiles       ();
use Cpanel::OS                ();
use Cpanel::Pkgr              ();
use Cpanel::SysPkgs           ();
use Cpanel::LoadModule        ();
use Cpanel::Update::Logger    ();
use Cpanel::Version           ();
use Cpanel::Services::Enabled ();
use Cpanel::Server::Type      ();

=head1 METHODS

=over

=cut

sub new ( $class, $self = undef ) {
    $self //= {};
    bless $self, $class;

    return $self;
}

sub logger ($self) {
    ref $self eq __PACKAGE__ or die("You must call this as a method.");

    return $self->{'logger'} //= Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'info', 'timestamp' => 0 } );
}

sub run ( $self, %opts ) {
    ref $self eq __PACKAGE__ or _croak("run() must be called as a method.");

    # Ensure that EA repo is always installed Unless this is during the install, in which case we have to save that for later.
    if ( !$opts{'skipreposetup'} && !$ENV{CPANEL_BASE_INSTALL} ) {
        ensure_ea4_repo_is_installed(
            log_info        => sub { Cpanel::Debug::log_info(@_); },
            log_error       => sub { Cpanel::Debug::log_warn(@_); return $self->_notify(@_) },
            skip_repo_setup => -f $Cpanel::ConfigFiles::SKIP_REPO_SETUP_FLAG,
        );
    }

    # Try to install packages.
    my $pkg_list = $self->needed_packages( $opts{'supplemental_packages'} );
    push @$pkg_list, $self->optional_packages();
    push @$pkg_list, get_ea4_tooling_pkgs() unless $ENV{CPANEL_BASE_INSTALL};

    return $self->install_packages($pkg_list);
}

sub get_ea4_tooling_pkgs {

    # Ensure that universal-hooks package is always installed
    #
    # This is needed so that we are able to use package hooks to fix community packages without resorting to things like autofixers
    if ( Cpanel::Server::Type::is_dnsonly() ) {
        return Cpanel::OS::ea4tooling_dnsonly()->@*;
    }

    return Cpanel::OS::ea4tooling()->@*;
}

sub ensure_ea4_repo_is_installed (%options) {

    if ( !Cpanel::EA4::Install::ea4_repo_already_installed() ) {
        $options{log_info}->("ea4: installing repo");
        return Cpanel::EA4::Install::install_ea4_repo(%options);
    }

    $options{log_info}->("ea4: repo already installed");

    return 1;
}

=item B<install_packages>

Install any Package packages not installed yet. Uses Cpanel::SysPkgs to install missing Packages.
If any packages are found again after the Cpanel::SysPkgs call then this function ends
with a return;

=cut

sub install_packages ( $self, $pkgs_wanted ) {
    ref $self eq __PACKAGE__ or _croak("install_packages() must be called as a method.");

    my @pkgs_needed = $self->get_outstanding_packages( $pkgs_wanted->@* )->@*;

    if (@pkgs_needed) {

        # In 11.52 we install nscd for the first time, and
        # this is the first version where nscd is considered a service.
        # Creating this touch file will flag the service as being disabled
        # so the check_unmonitored_enabled_services script will not
        # send out a warning while we are doing this upgrade.  One of
        # the post sync cleanup tasks in /ulc/install/CPanelPost.pm will
        # will decide whether to enable the service or fully disable it.
        if ( grep { $_ eq 'nscd' } @pkgs_needed ) {
            Cpanel::Services::Enabled::touch_disable_file('nscd');
        }

        # Setup sytem default excludes
        $self->_syspkgs->check_and_set_exclude_rules();    # previously known as checkyum
        $self->_syspkgs->install( 'pkglist' => \@pkgs_needed );

        # If packages still need to be installed, updatenow should fail and indicate there is a problem.
        my @uninstalled_pkgs = @{ $self->get_outstanding_packages( $pkgs_wanted->@* ) };
        if (@uninstalled_pkgs) {
            my $message = "Sysup: Needed system packages were not installed: " . join( ", ", @uninstalled_pkgs );
            $self->logger->error($message);
            $self->_notify($message);
            return;
        }

        return 1;
    }

    $self->logger->info("All Needed Packages are already installed.\n");

    return 1;
}

sub _syspkgs ($self) {
    return $self->{'_syspkg'} if $self->{'_syspkg'};
    return $self->{'_syspkg'} = Cpanel::SysPkgs->new( $self->{'logger'} ? ( 'logger' => $self->{'logger'} ) : () )
      || die "The system could not create the SysPkgs object.\n";
}

=item B<get_outstanding_packages>

determines what Packages have yet been installed ( or provided ) on the system

=cut

sub get_outstanding_packages ( $self, @pkgs_wanted ) {
    ref $self eq __PACKAGE__ or _croak("get_outstanding_packages() must be called as a method.");

    # alternative pkgs are provided in an ARRAYREF as the last element #
    pop @pkgs_wanted if !defined $pkgs_wanted[-1];

    # use two passes:
    # 1. first check if the pkg is installed
    # 2. then apply a backup plan to check if the capability is available

    my $installed_pkgs = Cpanel::Pkgr::installed_packages();

    my @pkgs_tocheck;
    foreach my $pkgs (@pkgs_wanted) {
        $pkgs = [$pkgs] unless ref $pkgs eq 'ARRAY';

        push @pkgs_tocheck, $pkgs unless grep { $installed_pkgs->{$_} } @$pkgs;
    }

    # 2. we now have a short list, so we can check if the capability is provided by another package
    my %missings;
    foreach my $pkgs (@pkgs_tocheck) {

        foreach my $pkg (@$pkgs) {

            # we only need to have one of these pkgs available
            if ( Cpanel::Pkgr::is_capability_available($pkg) ) {
                $missings{ $pkgs->[0] } = 0;
                last;
            }
            $missings{ $pkgs->[0] } = 1;
        }
    }

    return [ grep { $missings{$_} } sort keys %missings ];
}

# send iContact notification of update failure
sub _notify ( $self, $message ) {

    my $fullmessage = <<END;
Updating to the latest version of cPanel & WHM $Cpanel::Version::LTS did not succeed. Basic requirements for cPanel & WHM were unable to be installed. The specific failure was:

$message

For more information on this error, and guidance on resolving the error, please go to go.cpanel.net/sysupfailed
END

    if ( try { Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::sysup::Notify') } ) {

        require Cpanel::Notify;
        Cpanel::Notify::notification_class(
            'class'            => 'sysup::Notify',
            'application'      => 'sysup::Notify',
            'constructor_args' => [
                'origin'          => 'cPanel',
                'update_version'  => $Cpanel::Version::LTS,
                'failure_message' => $message
            ]
        );
    }
    else {
        require Cpanel::iContact;
        Cpanel::iContact::icontact(
            application => 'sysup',
            subject     => 'cPanel update failure during sysup',
            message     => $fullmessage,
        );
    }
    return;
}

=item B<needed_packages>

$self->needed_packages($include_supplemental_packages)

Get all Package packages required for the particular centhat distribution
currently installed.

If $include_supplemental_packages is passed the system will include packages
we have historicly installed but do need need for a base cPanel install anymore.
We still install them since users may rely on them.

=cut

sub needed_packages ( $self, $include_supplemental_packages = 1 ) {
    ref $self eq __PACKAGE__ or _croak("needed_packaged() must be called as a method.");

    $include_supplemental_packages //= 1;    #defaults to on

    my @packages = Cpanel::OS::packages_required()->@*;
    if ($include_supplemental_packages) {
        push @packages, Cpanel::OS::packages_supplemental()->@*;

        # NOTE: Cpanel::SysPkgs::YUM will take care to use the EPEL repo if installed, even if it is not enabled.
        push @packages, Cpanel::OS::packages_supplemental_epel()->@* if $self->_syspkgs->is_epel_installed;
    }

    return \@packages;
}

=item B<optional_packages>

Install all Package packages required for the particular centhat distribution
currently installed, unless they are excluded.

=cut

sub optional_packages ($self) {
    ref $self or die("You must call this as a method.");

    my @entries = (

        # only check the first value for each array ref
        [qw/nscd unscd/],
    );

    my @results;
    my $syspkgs = $self->_syspkgs();

    foreach my $entry (@entries) {
        my ( $main_pkg, @others ) = $entry->@*;

        # Do not consider secondary choices in determining whether a package is
        # available.  We may not ship them to customers; instead, they may be
        # provided by a third party.
        push @results, $entry unless $syspkgs->has_exclude_rule_for_package($main_pkg);
    }

    return @results;
}

sub _croak {
    require Carp;
    goto \&Carp::croak;
}

=back

=cut

1;
