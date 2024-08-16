package Cpanel::Security::Advisor::Assessors::Symlinks;

# cpanel - Cpanel/Security/Advisor/Assessors/Symlinks.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Sys::Uname ();

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;

    if ( $self->has_cpanel_hardened_kernel() ) {
        $self->add_warn_advice(
            'key'  => 'Symlinks_protection_no_longer_support_hardened_kernel',
            'text' => $self->_lh->maketext('Unsupported cPanel hardened kernel detected.'),

            'suggestion' => $self->_lh->maketext(
                "[asis,cPanel] no longer supports the hardened kernel. We recommend that you use [asis,KernelCare’s] free symlink protection. In order to enable [asis,KernelCare], you must replace the hardened kernel with a standard kernel. For instructions, please read the document on [output,url,_1,How to Manually Remove the cPanel-Provided Hardened Kernel,_2,_3].",
                'https://go.cpanel.net/uninstallhardenedkernel', 'target', '_blank'
            ),
        );

    }
    return 1;
}

sub has_cpanel_hardened_kernel {
    my $self         = shift;
    my $kernel_uname = ( Cpanel::Sys::Uname::get_uname_cached() )[2];
    my $ret;
    if ( $kernel_uname =~ m/(?:cpanel|cp)6\.x86_64/ ) {
        $ret = 1;
    }
    return $ret;
}

1;
