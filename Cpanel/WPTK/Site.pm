package Cpanel::WPTK::Site;

# cpanel - Cpanel/WPTK/Site.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::WPTK::Site

=head1 SYNOPSIS

use Cpanel::WPTK::Site ();
my $can = Cpanel::WPTK::Site::can_install();

=head1 DESCRIPTION

Support module for integrating WP Toolkit functionality with our frontend interfaces.

=cut

use cPstrict;

use Cpanel::Binaries ();

sub _wpt_is_installed {
    return -x Cpanel::Binaries::path('wp-toolkit') ? 1 : 0;
}

=head1 FUNCTIONS

=head2 can_install

Verifies that the system has WP Toolkit installed and that the docroot
is empty (allowing for safe installation without clobbering existing content).

=head3 RETURNS

Returns 1 if the answer is yes, 0 if no.

=cut

sub can_install {
    return 0 unless _wpt_is_installed();
    return is_docroot_empty();
}

=head2 is_docroot_empty

Verifies that the user's docroot is empty.

=head3 RETURNS

Returns 1 if the answer is yes, 0 if no.

=cut

sub is_docroot_empty {
    return unless defined $Cpanel::homedir;
    my $docroot = $Cpanel::homedir . '/public_html';

    #Always returns false if docroot does not exist.
    return 0 unless -d $docroot;

    my $dh;
    opendir( $dh, $docroot ) or return 0;
    while ( my $f = readdir $dh ) {
        chomp($f);
        next     if $f =~ m/^\./;
        return 0 if $f =~ m/^wp-/;
        next     if -d "$docroot/$f";
        return 0;
    }
    closedir $dh;

    return 1;
}

1;
