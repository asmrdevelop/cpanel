package Cpanel::SysPkgs::SCL;

# cpanel - Cpanel/SysPkgs/SCL.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::SysPkgs::SCL

=head1 DESCRIPTION

Accessor functions for retrieving Software Collection (SCL) compatible packages
information.

=cut

use strict;
use warnings;

=pod

=head1 VARIABLES

=head2 B<$SCL_PREFIX_DIR>

The directory which stores the prefix files for each SCL-style
package.  Each of these files will contain the install root of the
package in question (default /etc/scl/prefixes).

=cut

our $SCL_PREFIX_DIR = '/etc/scl/prefixes';

=pod

=head2 B<$PACKAGE_VERSION_FORMAT>

The regular expression which defines what we'll look for as a legal
package version suffix (default \d+[-_0-9A-Za-z]*)

=cut

our $PACKAGE_VERSION_FORMAT = '\d+[-_0-9A-Za-z]*';

=pod

=head1 SUBROUTINES

=head2 B<get_scl_versions($base)>

Finds and returns a list of SCL-compatible packages installed on the
system.  It must match $base$PACKAGE_VERSION_FORMAT.

    INPUT
        - scalar -- The base package name you're looking for (e.g. ea-php,
          ea-ruby, etc)

    OUTPUT
        - array ref - List of installed package names that match the
          language prefix.  If none are installed, the array will be
          empty.

=cut

sub get_scl_versions {
    my $base = shift;
    require Cpanel::SafeDir::Read;
    my @installed = Cpanel::SafeDir::Read::read_dir( $SCL_PREFIX_DIR, sub { $_[0] =~ m/\A$base$PACKAGE_VERSION_FORMAT\z/ } );
    return \@installed;
}

=head2 B<get_scl_prefix($package)>

Retrieve the root filesystem path specified within an SCL package.
This does not validate the path.

    INPUT
        - scalar -- package name

    OUTPUT
        - scalar -- filesystem path

=cut

sub get_scl_prefix {
    my $package = shift;
    my $root    = '';

    my $file = "$SCL_PREFIX_DIR/$package";
    if ( open my $fh, '<', $file ) {
        $root = <$fh> || '';
        close $fh;
        chomp $root;
        $root .= "/$package" unless $root eq '';
    }
    return $root;
}

=head1 CONFIGURATION AND ENVIRONMENT

The module requires no configuration files or environment variables.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

There are 2 limitations to this module:

  All SCL functions expect that the installed packages conform to SCL
  standards.  Thus, the prefix file will be in $SCL_PREFIX_DIR and
  will contain the path to the root of the package installation.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited

=cut

1;

__END__
