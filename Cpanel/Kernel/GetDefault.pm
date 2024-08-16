package Cpanel::Kernel::GetDefault;

# cpanel - Cpanel/Kernel/GetDefault.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS      ();
use Cpanel::Autodie ();

=head1 NAME

Cpanel::Kernel::GetDefault

=head1 SYNOPSIS

    use Cpanel::Kernel::GetDefault
    my $def_kv = Cpanel::Kernel::GetDefault::get();

=head1 DESCRIPTION

Module for getting the default kernel version, whether it is on a debian or
rhel derivative distribution (so that you don't have to remember what it takes
to get it on these various distros).

=head1 FUNCTIONS

=head2 C<< get() >>

Returns the version of the kernel that should be running on the next boot,
assuming fallback mechanisms or once-only boots are not employed.  See
L<https://www.gnu.org/software/grub/manual/legacy/Making-your-system-robust.html>
for a brief description of these exclusions.

B<Dies:> if the configuration file cannot be parsed or if it employs a I<saved>
default.

Additionally, on RHEL derivatives, this will die if the grubby bin has problems.

B<Returns:> the kernel version, if it can be determined; empty string, otherwise.

=cut

sub get() {

    my $check_kernel_version_method = Cpanel::OS::check_kernel_version_method();

    if ( $check_kernel_version_method eq 'grubby' ) {
        return _get_version_using_grubby();
    }
    elsif ( $check_kernel_version_method eq 'boot-vmlinuz-file' ) {
        return _get_version_from_symlink(q[/boot/vmlinuz]);
    }
    else {
        die "Unable to get kernel on " . Cpanel::OS::display_name() . " systems\n";
    }
}

sub _get_version_from_symlink ($file) {
    return _get_version_from_image_name( Cpanel::Autodie::readlink($file) );
}

sub _get_version_using_grubby() {
    require Cpanel::Binaries;
    my $grubby_bin = Cpanel::Binaries::path('grubby');

    if ( !-x $grubby_bin ) {
        die qq[Unable to locale grubby binary. You may need to re-install the grubby package.\n];
    }

    require Cpanel::SafeRun::Object;
    my $out = Cpanel::SafeRun::Object->new_or_die(
        'program' => $grubby_bin,
        'args'    => ['--default-kernel'],
    )->stdout();

    return _get_version_from_image_name($out);
}

sub _get_version_from_image_name ($kernel) {

    return '' unless defined $kernel;

    # This used to do tr/\n//d
    # instead of changing behavior here where "non-matching" results of grubby/symlink read
    # die, I'm going to allow fallback to return '', as that's what it has done for a long
    # time. That said, just using tr to do what chomp does better (catch other newline chars)
    # seems like something it was advisable to replace with chomp.
    # Besides, if you don't get something that "looks like a kernel version", we may as well
    # just say "nah, there's no default", not die. Chances are you probably wouldn't boot if
    # the output was some sort of incoherent result like "Whee\n\nWiddly" anyways.
    chomp($kernel);

    # strip off /boot/vmlinuz-
    # unfortunately we can't expect that this will always been named vmlinuz, assume that the first
    # digit following a dash in the response is the beginning of the kernel version.
    return $1 if $kernel =~ /[a-zA-Z\/_]+?-(\d.+)$/a;

    # this is a valid response for instances that do not have their own kernel configuration
    return '';
}

1;
