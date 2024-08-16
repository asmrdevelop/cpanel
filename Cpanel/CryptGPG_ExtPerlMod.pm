package Cpanel::CryptGPG_ExtPerlMod;

# cpanel - Cpanel/CryptGPG_ExtPerlMod.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Carp;
use Cpanel::Carp         ();
use Crypt::GPG           ();
use Cpanel::Binaries     ();
use Cpanel::SafeStorable ();

Cpanel::Carp::enable();

our $VERSION = '1.0';

sub keydb {
    my ($rargs) = @_;
    my $gpg     = Crypt::GPG->new;
    my $gpg_bin = find_gpg();
    $gpg->{'GPGBIN'} = $gpg_bin;
    my @keys = $gpg->keydb( ( $rargs->{'id'} ) );
    Cpanel::SafeStorable::nstore_fd( \@keys, \*STDOUT );
}

sub delkey {
    my ($rargs) = @_;
    my $gpg     = Crypt::GPG->new;
    my $gpg_bin = find_gpg();
    $gpg->{'GPGBIN'} = $gpg_bin;
    print( $gpg->delkey( ( $rargs->{'key'} ) ) ? 1 : 0 );
}

sub find_gpg {
    my $gpg = Cpanel::Binaries::path('gpg');

    if ( -x $gpg ) {
        return $gpg;
    }

    return;
}

1;
