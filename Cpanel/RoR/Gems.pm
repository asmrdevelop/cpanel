
# cpanel - Cpanel/RoR/Gems.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::RoR::Gems;

use strict;

use Cpanel::FileUtils::Path ();
use Cpanel::CachedCommand   ();
use Cpanel::DataStore       ();

my @paths;

sub write_gemrc {
    my ($homedir) = @_;
    if ( !$homedir ) {
        return;
    }
    my $paths = _gempaths();
    return if !$paths;

    my $gemrc = {
        'gem'     => '--remote --gen-rdoc --run-tests',
        'rdoc'    => '--inline-source --line-numbers',
        'gemhome' => $homedir . '/ruby/gems',
        'gempath' => $paths,
    };

    Cpanel::DataStore::store_ref( $homedir . '/.gemrc', $gemrc );
    if ( -e $homedir . '/.gemrc' ) {
        return 1;
    }
}

*cache_gempaths = \&_gempaths;

sub _gempaths {
    return \@paths if @paths;
    my $gem = Cpanel::FileUtils::Path::findinpath('gem');
    return if !$gem;

    my $gem_out = Cpanel::CachedCommand::cachedcommand( $gem, 'environment', 'gempath' );
    foreach my $dir ( split( /\n/, $gem_out ) ) {
        chomp $dir;
        if ( -e $dir ) {
            push @paths, $dir;
        }
    }
    return \@paths;
}

sub has_gems {
    my $gem = Cpanel::FileUtils::Path::findinpath('gem');
    if ($gem) {
        return 1;
    }
    else {
        return;
    }
}

sub update_gemhome {
    my ( $oldhomedir, $newhomedir ) = @_;
    my $gemrc = $newhomedir . '/.gemrc';
    if ( -e $gemrc ) {
        my $yaml = Cpanel::DataStore::load_ref($gemrc) || return;
        if ( $yaml->{gemhome} && $yaml->{gemhome} =~ s{^\Q$oldhomedir\E/}{$newhomedir/} ) {
            Cpanel::DataStore::store_ref( $gemrc, $yaml );
        }
    }
    return 1;
}

1;
