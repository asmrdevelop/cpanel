package Cpanel::RPM::Versions::Pkgr;

# cpanel - Cpanel/RPM/Versions/Pkgr.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::RPM::Versions::Pkgr

=head1 DESCRIPTION

A class invoked by Cpanel::RPM::Versions::File on all systems. It then re-blesses to a child
class based on what distro it detects as present.

=head1 SYNOPSIS

    my $pkgr = Cpanel::RPM::Versions::Pkgr->new;
    $pkgr->installed_packages
    $pkgr->uninstall_packages
    ...

=cut

use cPstrict;

use Cpanel::OS                       ();
use Cpanel::Fcntl::Constants         ();
use Cpanel::RPM::Versions::Pkgr::DEB ();    # PPI USE OK -- Needed during updatenow.static. Let's not try to dynamically load this.b
use Cpanel::RPM::Versions::Pkgr::RPM ();    # PPI USE OK -- Needed during updatenow.static. Let's not try to dynamically load this.b

use constant PKGR_INSTALL_IN_PROGRESS => '/var/cpanel/install_rpms_in_progress';

=head1 METHODS

=head2 new ($class, logger => $my_logger )

Called by Cpanel::RPM::Versions::File. Provides a blessed class based on which distro is present.
The interface will be the same for any distro so Cpanel::RPM::Versions::File doesn't have to worry
about it.

=cut

sub new ( $class, %args ) {

    my $pkgr;
    if ( $class =~ m/^Cpanel::RPM::Versions::Pkgr::(\S+)/ ) {
        $pkgr = $1;
    }
    else {
        $pkgr = determine_package_system();
    }

    $args{'packaging'} = lc($pkgr);

    my $new_class = "Cpanel::RPM::Versions::Pkgr::${pkgr}";

    my $self = bless \%args, $new_class;

    return $self;
}

=head2 pkgr ($self)

The subclass must define pkgr or this will die when called here.

=cut

sub pkgr ($self) { die "unimplemented" }

=head2 logger ($self)

A helper to return the logger provided at ->new

=cut

sub logger ($self) { return $self->{'logger'} }

=head2 clear_installed_packages_cache ($self)

Forgets the previous call to get a list of installed packages. This can be expensive
so we traditionally cache this call unless we know something changed.

=cut

sub clear_installed_packages_cache ($self) {
    delete $self->{'installed_packages'};
    return;
}

=head2 run_with_logger ( $self, @args )

Passes the local $logger and @args into its pkgr object so they can run a given command. Output is logged as
it goes. Errors are noted when the command completes.

=cut

sub run_with_logger ( $self, @args ) {

    # pkgr is implemented in the child class.
    return $self->pkgr->cmd_with_logger( $self->logger, @args );
}

=head2 run_with_logger_no_timeout ( $self, @args )

Similar to run_with_logger but without any timeout enabled.
Note: you should prefer to use run_with_logger
this is only used for the RPM transaction.

=cut

sub run_with_logger_no_timeout ( $self, @args ) {

    # pkgr is implemented in the child class.
    return $self->pkgr->cmd_with_logger_no_timeout( $self->logger, @args );
}

=head2 determine_package_system ( $self )

Uses basic checks to determine what packaging system is present on the local system. This information will
be used by new to determine what subclass to bless as.

=cut

sub determine_package_system {

    return 'RPM' if Cpanel::OS::is_rpm_based();
    return 'DEB' if Cpanel::OS::is_apt_based();

    die("Unable to determine the packaging system for this OS");
}

=head2 acquire_lock ( $self )

Creates a file lock to assure no other process is trying to interact with the local
packaging system at the same time.

NOTE: The system will hang indefinitely until the lock is released.

=cut

sub acquire_lock ($self) {

    return if $self->{'nolock'};

    # already holding a lock
    return 1 if $self->{'lock_fh'} && ref $self->{'lock_fh'};

    open( my $fh, '>>', PKGR_INSTALL_IN_PROGRESS )
      or die 'Failed to create install in progress file (' . PKGR_INSTALL_IN_PROGRESS . "): $!";

    my $loop = 0;
    while ( !flock( $fh, $Cpanel::Fcntl::Constants::LOCK_EX | $Cpanel::Fcntl::Constants::LOCK_NB ) ) {
        $self->logger->warning( sprintf( "Waiting for lock file %s to be released. Try `fuser %s`", PKGR_INSTALL_IN_PROGRESS, PKGR_INSTALL_IN_PROGRESS ) ) if ( $loop++ % 60 == 4 );
        sleep 1;
    }

    flock( $fh, $Cpanel::Fcntl::Constants::LOCK_EX )
      or die 'Failed to lock install in progress file (' . PKGR_INSTALL_IN_PROGRESS . "): $!";

    $self->{'lock_fh'} = $fh;

    return 2;
}

=head2 DESTROY ( $self )

Any system locks are released on DESTROY.

=cut

sub DESTROY ($self) {
    return unless $self->{'lock_fh'};

    delete $self->{'lock_fh'};
    unlink PKGR_INSTALL_IN_PROGRESS;
    return 1;
}

1;
