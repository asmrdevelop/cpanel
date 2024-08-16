package Cpanel::Dir::Loader;

# cpanel - Cpanel/Dir/Loader.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub load_multi_level_dir {

    my $dir = shift;
    my %DL;

    if ( opendir my $dir_fh, $dir ) {
        while ( my $diritem = readdir $dir_fh ) {
            next if ( $diritem =~ m/^\./ );
            if ( opendir my $subdir_fh, $dir . '/' . $diritem ) {
                my @subdir_list = sort readdir($subdir_fh);
                closedir($subdir_fh);
                foreach my $subdiritem (@subdir_list) {
                    next if $subdiritem =~ m/^\./;
                    push @{ $DL{$diritem} }, $subdiritem;
                }
            }
        }
        closedir $dir_fh;
    }
    return ( wantarray ? %DL : \%DL );
}

sub load_dir_as_array {
    my $dir = shift;
    my %DL  = load_dir_as_hash_with_value( $dir, 1 );
    return keys %DL;
}

sub load_dir_as_hash_with_value {
    my $dir   = shift;
    my $value = shift;
    my %DL;
    if ( opendir my $dir_fh, $dir ) {
        while ( my $diritem = readdir $dir_fh ) {
            next if $diritem =~ m/^\./;
            $DL{$diritem} = $value;
        }
        closedir $dir_fh;
    }
    return ( wantarray ? %DL : \%DL );
}

1;
