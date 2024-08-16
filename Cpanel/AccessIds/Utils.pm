package Cpanel::AccessIds::Utils;

# cpanel - Cpanel/AccessIds/Utils.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ArrayFunc::Uniq ();
use Cpanel::Debug           ();

sub normalize_user_and_groups {
    require Cpanel::AccessIds::Normalize;
    goto \&Cpanel::AccessIds::Normalize::normalize_user_and_groups;
}

sub normalize_code_user_groups {
    require Cpanel::AccessIds::Normalize;
    goto \&Cpanel::AccessIds::Normalize::normalize_code_user_groups;
}

sub set_egid {
    my @gids = @_;

    if ( !@gids ) {
        Cpanel::Debug::log_die("No arguments passed to set_egid()!");
    }

    if ( scalar @gids > 1 ) {
        @gids = Cpanel::ArrayFunc::Uniq::uniq(@gids);
    }

    _check_positive_int($_) for @gids;

    my $new_egid = join( q{ }, $gids[0], @gids );

    return _set_var( \$), 'EGID', $new_egid );
}

sub set_rgid {
    my ( $gid, @extra_gids ) = @_;

    if (@extra_gids) {
        Cpanel::Debug::log_die("RGID can only be set to a single value! (Do you want set_egid()?)");
    }

    _check_positive_int($gid);

    return _set_var( \$(, 'RGID', $gid );
}

sub set_euid {
    my ($uid) = @_;

    _check_positive_int($uid);

    return _set_var( \$>, 'EUID', $uid );
}

sub set_ruid {
    my ($uid) = @_;

    _check_positive_int($uid);

    return _set_var( \$<, 'RUID', $uid );
}

sub _check_positive_int {
    if ( !length $_[0] || $_[0] =~ tr{0-9}{}c ) {
        Cpanel::Debug::log_die("“$_[0] is not a positive integer!");
    }

    return 1;
}

sub _set_var {
    my ( $var_r, $name, $desired_value ) = @_;

    my $old_value = $$var_r;
    $$var_r = $desired_value;

    return $desired_value eq $$var_r ? 1 : validate_var_set(
        $name,             # The name of the value like 'RUID'
        $desired_value,    # The value we wanted it to be set to
        $$var_r,           # Deferenced variable being set, ex $<
        $old_value         # The value before we set it.
    );
}

sub validate_var_set {
    my ( $name, $desired_value, $new_value, $old_value ) = @_;

    my $error;

    # We can not rely on checking $! when setting $). Assigning to this magic
    # variable attempts to access ngroups_max from /proc under the hood.
    # If this file does not exist, $! will contain a "No such file or directory"
    # error, even though the setgroups() call will otherwise succeed.
    # This will happen if we attempt to setuids in a chroot, for instance.

    # We are not guaranteed to get the same value back from $) that we put in.
    # If we have multiple, space-separated, valued returned, we need to normalize
    # the results before comparison.

    if ( $new_value =~ tr/ // ) {

        # We should only be hitting this case when we are changing the effective
        # group ids, with supplemental ids.

        my ( $desired_first, @desired_parts ) = split( ' ', $desired_value );
        my ( $new_first,     @new_parts )     = split( ' ', $new_value );

        if ( $new_first != $desired_first ) {
            $error = 1;
        }
        elsif ( @desired_parts && @new_parts ) {
            if ( scalar @desired_parts == 1 && scalar @new_parts == 1 ) {
                if ( $new_parts[0] != $desired_parts[0] ) {
                    $error = 1;
                }
            }
            else {
                @desired_parts = sort { $a <=> $b } Cpanel::ArrayFunc::Uniq::uniq(@desired_parts);
                @new_parts     = sort { $a <=> $b } Cpanel::ArrayFunc::Uniq::uniq(@new_parts);

                for my $i ( 0 .. $#desired_parts ) {
                    if ( $new_parts[$i] != $desired_parts[$i] ) {
                        $error = 1;
                        last;
                    }
                }
            }
        }
    }
    else {
        if ( $new_value != $desired_value ) {
            $error = 1;
        }
    }

    return 1 if !$error;

    if ( defined $old_value ) {
        Cpanel::Debug::log_die("Failed to change $name from “$old_value” to “$desired_value”: $!");
    }
    Cpanel::Debug::log_die("Failed to change $name to “$desired_value”: $!");

    return 0;    #not reached
}

1;
