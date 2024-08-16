package Cpanel::RpmUtils::Parse;

# cpanel - Cpanel/RpmUtils/Parse.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub parse_rpm_arch {
    my ($filename) = @_;

    #
    # Example:
    #
    # cpanel-perl-522-Acme-Bleach-1.150-1.cp1156.x86_64.rpm
    # ea-php70-libc-client-2007f-7.7.1.x86_64
    # glibc-common-2.12-1.192.el6.x86_64.rpm
    #
    $filename =~ s{\.rpm$}{};

    my @rpm_parts = split( /\./, $filename );

    my $arch = pop @rpm_parts;    # x86_64     (glibc-common-2.12-1.192.el6)

    my $name_with_version = join( '.', @rpm_parts );    # glibc-common-2.12-1.192.el6

    my $name_version_parse = parse_rpm($name_with_version);

    return {
        'arch' => $arch,
        %$name_version_parse,
    };
}

sub parse_rpm {
    my ($name_with_version) = @_;
    my @name_version_parts = split( m{-}, $name_with_version );

    my $release = pop @name_version_parts;    # 1.192.el6  (glibc-common-2.12)
    my $version = pop @name_version_parts;    # 2.12  (glibc-common)

    my $name = join( '-', @name_version_parts );
    $name =~ s/^\d+://;                       # TODO/YAGNI: include epoch (or lack thereof) in results?

    return {
        'release' => $release,
        'version' => $version,
        'name'    => $name
    };
}

1;
