package Cpanel::OS::Almalinux;

# cpanel - Cpanel/OS/Almalinux.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::OS::Rhel';

use constant is_supported => 0;

use constant pretty_distro => 'AlmaLinux';

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Almalinux - Almalinux base class

=head1 SYNOPSIS

    use parent 'Cpanel::OS::Almalinux';

=head1 DESCRIPTION

This package is an interface for all Almalinux distributions.
You should not use it directly.
