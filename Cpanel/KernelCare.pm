package Cpanel::KernelCare;

# cpanel - Cpanel/KernelCare.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                ();
use Cpanel::FindBin                  ();
use Cpanel::SafeRun::Object          ();
use Cpanel::KernelCare::Availability ();
use Cpanel::Pkgr                     ();
use Cpanel::OS                       ();
use Cpanel::JSON                     ();
use Try::Tiny;

use constant KERNELCARE_PACKAGE_NAME => q{kernelcare};

# kernelcare related system states
our $KC_NONE              = 0;            #KC is not installed (checks rpm database), IP has no valid license
our $KC_UNSET             = 1;            #KC is installed, but not licensed and free patch set is not set
our $KC_MISSING           = 2;            #KC is not installed, but is licensed.
our $KC_FREE_PATCH_SET    = 4;            #KC is installed, but only the free patch set has been set
our $KC_DEFAULT_PATCH_SET = 8;            #KC is installed and licensed, but only the paid patch set has been set
our $KC_EXTRA_PATCH_SET   = 16;           #KC is installed and licensed, and both the paid and free patch sets are set
our $KC_UNKNOWN_PATCH_SET = -1;           #KC is installed, but we were unable to determine the patch set.
our $cmd                  = 'kcarectl';

our $type_map = { 'unset' => $KC_UNSET, 'free' => $KC_FREE_PATCH_SET, 'default' => $KC_DEFAULT_PATCH_SET, 'extra' => $KC_EXTRA_PATCH_SET, 'unknown' => $KC_UNKNOWN_PATCH_SET };

sub system_supports_kernelcare {
    return Cpanel::KernelCare::Availability::kernel_is_supported() && Cpanel::OS::supports_kernelcare();
}

# Free KC tier symlink patcheset only supports CentOS 6/7/8
# Note: This check implicitly ensures the system is not running CloudLinux
sub system_supports_kernelcare_free {

    return Cpanel::OS::supports_kernelcare_free();
}

sub kernelcare_responsible_for_running_kernel_updates {
    my $kernelcare_state = get_kernelcare_state();
    my $ret              = 1;
    if ( $kernelcare_state == $KC_NONE or $kernelcare_state == $KC_UNSET or $kernelcare_state == $KC_MISSING or $kernelcare_state == $KC_FREE_PATCH_SET ) {
        $ret = 0;
    }
    return $ret;
}

my $_get_kernelcare_state;

sub _clear_kernelcare_state {
    return undef $_get_kernelcare_state;
}

sub get_kernelcare_state {
    return $_get_kernelcare_state if $_get_kernelcare_state;

    # determine if IP has a valid license
    my $license = try {
        Cpanel::KernelCare::Availability::system_license_from_cpanel()
    }
    catch {
        die Cpanel::Exception->create(
            "Error querying for KernelCare license: [_1]",
            [ Cpanel::Exception::get_string_no_id($_) ]
        );
    };

    # determine if the package is installed
    my $has_pkg = Cpanel::Pkgr::is_installed(KERNELCARE_PACKAGE_NAME);

    # check in the event that the kernelcare RPM is not installed
    unless ($has_pkg) {

        # not license, not installed
        return ( $_get_kernelcare_state = $KC_NONE ) if not $license;

        # licensed, not installed
        return ( $_get_kernelcare_state = $KC_MISSING ) if $license;
    }

    # assume kernelcare RPM is installed, determine patch type
    my $patch_type = get_patch_type();

    return defined $type_map->{$patch_type} ? ( $_get_kernelcare_state = $type_map->{$patch_type} ) : 'unknown';

}

sub _get_exec {
    return Cpanel::FindBin::findbin($cmd) // die Cpanel::Exception::create( 'Service::BinaryNotFound', [ service => $cmd ] );
}

sub updates_available {    ##no critic (RequireFinalReturn)
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => ['--check'],
    );
    if ( $proc->signal_code() ) {
        $proc->die_if_error();    # This will die if reached.
    }

    # Process valid exit codes.
    return 1 if !$proc->error_code();        # New kernel available.
    return 0 if $proc->error_code() == 1;    # No patches available.

    # All other exit codes are unexpected.
    $proc->die_if_error();                   # If reached, this line will die.
}

sub get_running_version {
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => ['--uname'],
    );
    $proc->die_if_error();

    my $stdout = $proc->stdout();
    chomp $stdout;
    return $stdout;
}

# Note, throws exception if KernelCare is not installed
sub get_patch_type {
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => [ '--info', '--json' ],
    );
    $proc->die_if_error();

    my $stdout = $proc->stdout();
    my $json;
    {
        local $@;
        eval { $json = Cpanel::JSON::Load($stdout); };

        # perhaps they are running an older kcarectl that does not output json...
        if ( $@ && $stdout ) {
            my @lines = split /\n/, $stdout;
            if ( ( my $description ) = grep { /kpatch-description/ } @lines ) {
                $description =~ m/^kpatch-description: ([\d]+)-(.*):/;
                return ($2) ? $2 : 'default';
            }
            elsif ( grep { /No patches applied/ } @lines ) {
                return 'unset';
            }

            return 'unknown';
        }
    }

    return defined $json->{'patch-type'} ? $json->{'patch-type'} : 'unknown';
}

sub set_free_patch {
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => [qw/--set-patch-type free --update/],
    );
    _handle_kcarectl_errors($proc);
    return 1;
}

sub set_default_patch {
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => [qw/--set-patch-type default --update/],
    );
    _handle_kcarectl_errors($proc);
    return 1;
}

sub set_extra_patch {
    my $proc = Cpanel::SafeRun::Object->new(
        program => _get_exec(),
        args    => [qw/--set-patch-type extra --update/],
    );
    _handle_kcarectl_errors($proc);
    return 1;
}

# kcarectl prints its error output to stdout, so we need custom handling to make sure we grab it
sub _handle_kcarectl_errors {
    my ($saferun_obj) = @_;

    if ( $saferun_obj->error_code() ) {
        die Cpanel::Exception::create(
            'ProcessFailed::Error',
            [
                process_name => $saferun_obj->program(),
                error_code   => $saferun_obj->error_code(),
                stderr       => $saferun_obj->stdout,         # mismatch is intentional
            ]
        );
    }

    # Fall back to default error handling for any case(s) not specifically covered here (signal)
    $saferun_obj->die_if_error();

    return;
}

1;

__END__

=head1 NAME

Cpanel::KernelCare - Query information about KernelCare

=head1 DESCRIPTION

Query information about KernelCare.

=head1 FUNCTIONS

=head2 C<< system_supports_kernelcare() >>

Returns whether or not the system can install and use KernelCare.

B<Returns:> 1 if KernelCare can be used; 0 otherwise.

=head2 C<< system_supports_kernelcare_free() >>

Returns undef if the server is not running CentOS 6 or CentOS 7. Returns 1 if
it is.

B<Note:> This check is necessary because the free symlink patch set is only needed
on CentOS 6 and CentOS 7.

=head2 C<< kernelcare_responsible_for_running_kernel_updates() >>

Returns whether KernelCare is installed; checks to see if the RPM is
installed rather than just checking for /usr/bin/kcarectl.

B<Note:> A system can have KernelCare, but not support it. That is, it can be
installed but unusable.  See C<system_supports_kernelcare>.

B<Returns:> 1 if KernelCare is installed; 0 otherwise.

=head2 C<< get_running_version() >>

Gets the KernelCare safe kernel version.

B<Returns:> the kernel version.

B<Dies:> if unable to determine the KernelCare kernel version.

=head2 C<< updates_available() >>

Check if KernelCare patches are available to apply to the running kernel.

B<Returns:> 1 if patches are available; 0 otherwise.

B<Dies:> if unable to determine if KernelCare patches are available.

=head2 C<< get_kernelcare_state() >>

Returns a determined state that can be used to make decisions based when KernelCare must be considered.

Returns one of the following states:

=over 4

=item B<$KC_NONE>              - not installed (checks rpm database), IP has no valid license

=item B<$KC_UNSET>             - installed, but not licensed and free patch set is not set

=item B<$KC_MISSING>           - not installed, but is licensed.

=item B<$KC_FREE_PATCH_SET>    - installed, but only the free patch set has been set

=item B<$KC_DEFAULT_PATCH_SET> - installed and licensed, but only the paid patch set has been set

=item B<$KC_EXTRA_PATCH_SET>   - installed and licensed, and both the paid and free patch sets are set

=back

=head2 C<< get_patch_type() >>

If set, will return the patch set that is enabled. Depends on KernelCare being installed and uses the C<< --info >> option.

An exception is thrown if this method is called and KernelCare is not installed.

=head2 C<< set_free_patch >>

Issues the proper C<< kcarectl >> command to set the free patch set. Note: this will replace any patch set currently enabled with the free one.

=head2 C<< set_default_patch >>

Issues the proper C<< kcarectl >> command to set the default patch set. Note: this will replace any patch set currently enabled with the default one.

=head2 C<< set_extra_patch >>

Issues the proper C<< kcarectl >> command to set the extra patch set. Note: this will replace any patch set currently enabled with the extra one.

=cut
