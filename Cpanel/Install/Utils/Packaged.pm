
# cpanel - Cpanel/Install/Utils/Packaged.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Install::Utils::Packaged;

use strict;
use warnings;

use Cpanel::Install::Utils::Logger ();
use Cpanel::Pkgr                   ();
use Cpanel::SysPkgs                ();

my $max_retries = 3;

=encoding utf-8

=head1 NAME

Cpanel::Install::Utils::Packaged - Install packages if they are missing

=head1 SYNOPSIS

    use Cpanel::Install::Utils::Packaged;

    if ( Cpanel::Install::Utils::Packaged::install_needed_packages('glibc','psmisc') ) {
        # great success!
    }

=head2 install_needed_packages(@pkgs)

This function will install packages that do not currently exist on this system
and will return true on success.

=over 2

=item Input

=over 3

=item @packages C<ARRAY>

    A list of packages to install

=back

=item Output

=over 3

=item $status C<SCALAR>

    Returns 1 on success and 0 on failure.

=back

=back

=cut

sub install_needed_packages {
    my (@packages) = @_;

    my $installed_versions_hr = Cpanel::Pkgr::installed_packages(@packages);
    if ( my @need_packages = grep { !$installed_versions_hr->{$_} } @packages ) {
        my $syspkgs = Cpanel::SysPkgs->new( output_obj => Cpanel::Install::Utils::Logger::get_output_obj() );
        for my $attempt ( 1 .. $max_retries ) {
            if ( $syspkgs->install_packages( 'packages' => \@need_packages ) ) {
                return 1;
            }
            Cpanel::Install::Utils::Logger::WARN("Attempt $attempt/$max_retries to install packages “@need_packages” was unsuccessful.");
        }
        Cpanel::Install::Utils::Logger::ERROR("Failed to install packages: @need_packages");
        return 0;
    }
    return 1;
}
1;

__END__
