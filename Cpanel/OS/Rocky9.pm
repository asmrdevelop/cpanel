package Cpanel::OS::Rocky9;

# cpanel - Cpanel/OS/Rocky9.pm                     Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Rocky;
use parent 'Cpanel::OS::Rhel9';

use constant is_supported => 1;    # Rockylinux 9

use constant pretty_distro => Cpanel::OS::Rocky->pretty_distro;

use constant supports_imunify_av      => 0;
use constant supports_imunify_av_plus => 0;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Rocky9 - Rocky9 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Rocky9> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Rocky9>.
