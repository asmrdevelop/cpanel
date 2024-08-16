package Cpanel::Logd::MiniDynamic;

# cpanel - Cpanel/Logd/MiniDynamic.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SafeDir::Read ();
our $symlink_dir = '/var/cpanel/log_rotation';    # no trailing slash
our $symlink_ext = 'cpanellogd';                  # no preceding dot

# TODO: create an Errno replacment that AutoLoads each value
# so we don't have to compile in the whole thing
our $EINVAL = 22;
our $ENOENT = 2;

sub get_logd_link_entry_of_path {
    my ( $path, $match ) = @_;

    my $search_string        = ".$symlink_ext";
    my $search_string_length = length $search_string;

    foreach my $cust ( grep { substr( $_, -$search_string_length ) eq $search_string } Cpanel::SafeDir::Read::read_dir($symlink_dir) ) {
        next if $match && $cust !~ $match;
        my $target = get_path_of_logd_link_entry($cust);
        return $cust if $target eq $path;
    }
    return;
}

sub get_path_of_logd_link_entry {
    my ($ent) = @_;
    $ent = _fixup_entry_name($ent);
    local $!;
    my $target = readlink("$symlink_dir/$ent");
    return ''                                                      if $! == $EINVAL;
    warn "get_path_of_logd_link_entry($ent) failed with error: $!" if $! && $! != $ENOENT;    # previous behavior was to continue on so we just warn
    return $target;
}

sub _fixup_entry_name {
    my ($ent) = @_;

    # remove in prep for next regex and general sanity .foo.foo.foo
    {
        if ( substr( $ent, -1 - length $symlink_ext ) eq ".$symlink_ext" ) {
            substr( $ent, -1 - length $symlink_ext ) = q<>;
            redo;
        }
    }

    # kill all non \w chars
    $ent =~ s{[^\w-]}{}g;

    # since we know its gone at this point
    return "$ent.$symlink_ext";
}

1;
