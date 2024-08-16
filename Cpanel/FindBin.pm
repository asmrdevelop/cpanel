package Cpanel::FindBin;

# cpanel - Cpanel/FindBin.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant _ENOENT => 2;

our $VERSION = 1.2;

my %bin_cache;
my @default_path = qw( /usr/bin /usr/local/bin /bin /sbin /usr/sbin /usr/local/sbin );

sub findbin {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $binname = shift;
    return if !$binname;

    my @lookup_path = get_path(@_);

    my $nocache = grep( /nocache/, @_ );

    if ( !$nocache && exists $bin_cache{$binname} && $bin_cache{$binname} ne '' ) {
        return $bin_cache{$binname};
    }

    foreach my $path (@lookup_path) {
        next unless -d $path;

        $path .= "/$binname";

        if ( -e $path ) {
            if ( -x _ ) {
                $bin_cache{$binname} = $path unless $nocache;
                return $path;
            }
            else {
                warn "“$path” exists but is not executable; ignoring.\n";
            }
        }
        elsif ( $! != _ENOENT() ) {
            warn "stat($path): $!\n";
        }
    }
    return;
}

sub get_path {
    if ( !$_[0] ) {
        return @default_path;
    }
    elsif ( scalar @_ > 1 ) {
        my %opts;
        %opts = @_ if ( scalar @_ % 2 == 0 );
        if ( exists $opts{'path'} && ref $opts{'path'} eq 'ARRAY' ) {
            return @{ $opts{'path'} };
        }
        else {
            return @_;
        }
    }
    elsif ( ref $_[0] eq 'ARRAY' ) {
        return @{ $_[0] };
    }
    return @default_path;
}

1;
