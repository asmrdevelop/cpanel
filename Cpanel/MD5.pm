
# cpanel - Cpanel/MD5.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::MD5;

use Cpanel::SafeRun::Simple ();

sub getmd5sum {
    if ( $INC{'Digest/MD5.pm'} || eval { require Digest::MD5; } ) {
        goto \&_get_md5sum_from_xs;
    }
    goto \&_get_md5sum_from_binary;
}

sub _get_md5sum_from_xs {
    my ($file) = @_;

    my $md5 = Digest::MD5->new();
    if ( open( my $fh, '<', $file ) ) {
        $md5->addfile($fh);
        return $md5->hexdigest;
    }
    return;
}

sub _get_md5sum_from_binary {
    my $file = shift;
    my $mbuf;

    my $bintouse;
    my @md5sums = qw(/bin/md5sum /usr/bin/md5sum /usr/local/bin/md5sum);
    foreach my $md5sumbin (@md5sums) {
        if ( -e $md5sumbin ) {
            if ( !-x _ ) {
                chmod 0755, $md5sumbin || next;
            }
            $bintouse = $md5sumbin;
            last;
        }
    }
    if ($bintouse) {
        $mbuf = Cpanel::SafeRun::Simple::saferun( $bintouse, $file );
    }
    else {
        $mbuf = Cpanel::SafeRun::Simple::saferun( 'md5', '-r', $file );
    }
    chomp($mbuf);
    my $md5 = ( split( /\s+/, $mbuf ) )[0];
    return $md5;
}

1;
