package Cpanel::Kernel::Status;

# cpanel - Cpanel/Kernel/Status.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception          ();
use Cpanel::Kernel             ();
use Cpanel::Kernel::GetDefault ();
use Cpanel::KernelCare         ();
use Cpanel::OS                 ();
use Cpanel::SysPkgs            ();
use Cpanel::SafeRun::Object    ();

sub _shared_check() {
    die Cpanel::Exception::create( 'Unsupported', 'Cannot update this system’s kernel.' ) if !Cpanel::Kernel::can_modify_kernel();

    my $bkv = Cpanel::Kernel::GetDefault::get();
    die Cpanel::Exception->create('Cannot determine startup kernel version.') if !$bkv;

    my $rkv = Cpanel::Kernel::get_running_version();
    return ( $bkv, $rkv );
}

# only checks for version mismatch between running and boot kernel versions for non-custom/non-KernelCare kernels;
sub reboot_status() {
    my ( $boot_kernelversion, $running_kernelversion ) = _shared_check();
    my $output = {
        running_version => $running_kernelversion,
        boot_version    => $boot_kernelversion,
        reboot_required => 0,
        custom_kernel   => 0,
        has_kernelcare  => 0,
    };

    # return if custom kernel, do not suggest reboot ( so don't check for boot/running mismatch )
    if ( $running_kernelversion !~ Cpanel::OS::stock_kernel_version_regex() ) {
        $output->{'custom_kernel'} = 1;
        return $output;
    }

    # return if KernelCare is INSTALLED and *LICENSED*; we're not going to try to do mind KernelCare
    # That means, "kernelcare_responsible_for_running_kernel_updates" returns false if KC is not installed or if it has the free
    # patch set (only) enabled
    if ( Cpanel::KernelCare::kernelcare_responsible_for_running_kernel_updates() ) {
        $output->{'has_kernelcare'} = 1;
        return $output;
    }

    # legitimate kernel version mismatch, suggest reboot
    if ( $running_kernelversion ne $boot_kernelversion ) {
        $output->{'reboot_required'} = 1;
    }

    return $output;
}

# existing method kept currently to support the call in SecurityAdvisor
sub kernel_status (%opts) {

    my ( $boot_kernelversion, $running_kernelversion ) = _shared_check();

    my $output = {
        reboot_required => $running_kernelversion ne $boot_kernelversion,
        running_version => $running_kernelversion,
        boot_version    => $boot_kernelversion,
    };

    return { %$output, custom_kernel => 1 } if $running_kernelversion !~ Cpanel::OS::stock_kernel_version_regex();

    if ( $opts{updates} ) {

        # Do the force check first, as we don't expect updates often, so we can
        # shortcut the second check.
        my ($update) = updates_available( force => 1 );
        if ($update) {
            $output->{update_excluded} = 1 if !updates_available();
        }
        $output->{update_available} = $update;
        $output->{running_latest}   = !$output->{reboot_required} && !$update;
    }

    $output->{has_kernelcare} = Cpanel::KernelCare::kernelcare_responsible_for_running_kernel_updates();
  WHEN_HAS_KERNELCARE:
    if ( $output->{has_kernelcare} ) {

        # Set the effective running kernel version, but not before saving off the
        # unpatched kernel version.
        $output->{unpatched_version} = $output->{running_version};
        $output->{running_version}   = Cpanel::KernelCare::get_running_version();

        # Note: logically, if KernelCare is managing the running kernel; then it's improper
        # to check the running kernal against the boot kernel in order to determine if a
        # reboot is required; we need to be comparing the unpatched kernel version to the
        # boot kernel version; this will indicate when the boot kernel has been updated out of
        # band (e.g., via yum update), but the machine has not been restarted and therefore has
        # not yet had a chance to boot into the new boot kernel.
        my $matching = $output->{unpatched_version} eq $output->{boot_version};

        # Since KernelCare can - but does not always - omit the arch, we need to do
        # two comparisons.
        if ( !$matching ) {
            my $boot = $output->{boot_version};
            $boot =~ s/\.(?:noarch|x86_64|i[3-6]86)$//;
            $matching = $output->{unpatched_version} eq $boot;
        }

        $output->{patch_available} = Cpanel::KernelCare::updates_available() if $opts{updates};

        # Update calculated values with new KernelCare information.
        if ( $output->{patch_available} ) {
            $output->{reboot_required} = undef;
            $output->{running_latest}  = 0;
        }
        elsif ( my $update = $output->{update_available} ) {

            # Determine if KernelCare is already running this new update.
            my $VR             = "$update->{version}-$update->{release}";
            my $update_applied = $VR eq $output->{running_version} || "$VR.$update->{arch}" eq $output->{running_version};

            $output->{reboot_required} = $update_applied ? 0 : !$matching;
            $output->{running_latest}  = $update_applied;
        }
        else {
            $output->{reboot_required} = !$matching;    # will be 0 when unpatched_version and boot_version are the same
            $output->{running_latest}  = $matching;
        }
    }

    return $output;
}

# Determine the type of kernel we are currently running to append to our pattern, if we are running 5.4.0-80-generic, we don't want it
# to tell us we can upgrade to 5.8.0-81-lowlatency or 5.8.0-81-oracle , for example.
sub get_kernel_type {
    return Cpanel::SafeRun::Object->new( 'program' => '/usr/bin/uname', 'args' => [qw{ -r }], 'timeout' => 60 )->stdout();
}

sub updates_available (%opts) {

    die Cpanel::Exception::create( 'Unsupported', 'Cannot update this system’s kernel.' ) if !Cpanel::Kernel::can_modify_kernel();
    $opts{'pattern'} = Cpanel::OS::kernel_package_pattern();
    my $kernel_type = get_kernel_type();

    chomp $kernel_type;

    if ( $kernel_type =~ m/\-([a-z]+)$/ ) {
        $opts{'pattern'} .= '.*-' . $1;
    }

    local $ENV{'LANG'}   = 'C';
    local $ENV{'LC_ALL'} = 'C';

    my $results = Cpanel::SysPkgs->new()->search(%opts);
    return unless $results;

    # Some SysPkgs implementations always place the result in an array reference
    if ( ref $results eq 'ARRAY' ) {
        return unless scalar @$results;
        $results = $results->[0];
    }

    # If the most recent version of our current kernel is installed, there are no updates available
    if ( ref $results eq 'HASH' && defined( $results->{'installed'} ) && $results->{'installed'} =~ m/installed/ ) {
        return;
    }
    else {
        return $results;
    }
}

1;

__END__

=head1 NAME

Cpanel::Kernel::Status - Get kernel status information

=head1 DESCRIPTION

Get kernel status information

=head1 FUNCTIONS

=head2 C<< reboot_status() >>

Determines if reboot is necessary due to mismatch between
the running kernel version and the boot kernel version. If
KernelCare is detected or a custom kernel is detected, it
returns without recommending reboot.

=head2 C<< kernel_status(%opts) >>

Collects and returns a swath of data about the kernel.

=over

=item C<< updates => $bool >> [in, optional]

Whether to check for updates to the kernel.

If true, this option causes kernel_status() to check for updates.  By doing so,
kernel_status() can determine if the system is running the latest kernel.
However, checking for kernel updates takes extra time, as it often involves
external resources.

Defaults to false.

=back

B<Returns:> a hashref with the following keys:

=over

=item C<< has_kernelcare => 1 | 0 >>

Indicates whether KernelCare is installed on this system.

B<Note:> It is possible to have KernelCare installed on an unsupported system.

=item C<< unpatched_version => $ver >> [conditional]

The unpatched version of the running kernel.  This is the kernel that the
system started with at boot time.

This key is only returned if the system has KernelCare installed.

=item C<< running_version => $ver >>

The currently running kernel version.

If KernelCare is installed, this includes the KernelCare patches that were
applied to the kernel.

B<Note:> The kernel version reported by KernelCare I<sometimes> omits the
architecture, like C<.x86_64>, from the reported version.

=item C<< boot_version => $ver >>

The version of the kernel that will be run next boot, as defined by GRUB.

=item C<< reboot_required => 1 | 0 | undef >>

Indicates whether a reboot is required to get the boot kernel version to run.

This key only considers currently installed kernels; updates, when available,
will have no effect on this value.  So, despite needing to reboot I<after> the
update is installed, this key may return false when an update is available.

If a KernelCare patch is available, this value will be false, as we cannot tell
if a reboot is required.

B<Note:> If C<patch_available> is true, you should apply the patch and re-run
this check to determine if the patch was sufficient to update the kernel.  It
is possible the patch doesn't provided the latest version, especially if an
update was very recently released.

=item C<< custom_kernel => 1 >> [conditional]

Indicates the currently running kernel is custom and not provided by a known
packager.  If a custom kernel is detected, update information cannot be
provided and will thus be omitted.

This key is only returned if it is true.

=item C<< patch_available => 1 | 0 >> [conditional]

Indicates whether a KernelCare patch is available.

This key is only returned if the C<updates> parameter is given, the system has
KernelCare installed, and the kernel is not known to be custom.

=item C<< update_available => \%details >> [conditional]

Indicates whether an RPM update is available.

If an update is available, this key contains details about that update, as
returned by C<update_available()>; otherwise, it is false.

This key is only returned if the C<updates> parameter is given and the kernel
is not known to be custom.

B<Note:> The C<reboot_required> key may return false even when an update is
available for installation.

=item C<< update_excluded => 1 >> [conditional]

Indicates the kernel package is excluded from yum commands.

If an update for the kernel exists, but it is excluded from updates by a yum
config file, then this key will be included in the return and will be set to a
true value.

This key is only returned if it is true.

=item C<< running_latest => 1 | 0 >> [conditional]

Indicates whether the running kernel is up-to-date with the latest changes from
the package provider.

This key is only returned if the C<updates> parameter is given and the kernel is
not known to be custom.

=back

B<Dies:> with

=over

=item C<Cpanel::Exception>

When unable to open GRUB resources to determine what the boot version is.

=item C<Cpanel::Exception::Unsupported>

When the kernel cannot be modified, and therefore, no action can be taken to
improve the kernel status.

=back


=head2 C<< updates_available(%opts) >>

Checks whether an update is available for the kernel.

B<Note:> This currently only checks 'kernel'; systems using e.g. 'kernel-xen'
will not find the results useful.

=over

=item C<< all => 1 >> [in, optional]

Return all available kernels.

By default, only the latest kernel is returned, as that is generally the
desired kernel.

=item C<< force => 1 >> [in, optional]

Show updates even if the kernel is excluded from updates.

If the kernel package is excluded from updates in one of the yum config files,
then any updates available will not be shown.  Use this flag to always return
available updates, regardless of the configuration file settings.

=back

B<Returns:> false, if no updates are available; otherwise, an array where each
entry is a hashref containing details about the update:

=over

=item C<< name => $package >>

Currently, this value is always 'kernel'.

=item C<< version => $version >>

The version of the kernel.

=item C<< release => $release >>

The distributor's release version.

=item C<< arch => $arch >>

The architecture of the kernel.

=item C<< rpm => $unique_name >>

The full name of the RPM providing this version of the kernel.

=back

B<Dies:> with C<Cpanel::Exception::Unsupported> when the kernel cannot be
updated on this system.

=cut
