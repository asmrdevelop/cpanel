package Cpanel::OS::Almalinux9;

# cpanel - Cpanel/OS/Almalinux9.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Almalinux;
use parent 'Cpanel::OS::Rhel9';

use constant is_supported => 1;    # Almalinux 9

use constant pretty_distro => Cpanel::OS::Almalinux->pretty_distro;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Almalinux9 - Almalinux9 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Almalinux9> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Almalinux9>.
