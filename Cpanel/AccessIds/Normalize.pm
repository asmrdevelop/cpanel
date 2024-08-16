package Cpanel::AccessIds::Normalize;

# cpanel - Cpanel/AccessIds/Normalize.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ArrayFunc::Uniq ();
use Cpanel::PwCache         ();
use Cpanel::PwUtils         ();
use Cpanel::Exception       ();

=encoding utf-8

=head1 NAME

Cpanel::AccessIds::Normalize - Tools for converting users and groups to uids and gids

=head1 SYNOPSIS

    use Cpanel::AccessIds::Normalize;

    # If you're using the wheel group as sudo...
    use Cpanel::OS ();
    # 'wheel' on RHEL, 'sudo' on Ubuntu
    my $sudoer_group = Cpanel::OS::sudoers();

    my($uid,$gid,...) = Cpanel::AccessIds::Normalize::normalize_user_and_groups('bob', $sudoers);
    my($code,$uid,$gid,...) = Cpanel::AccessIds::Normalize::normalize_code_user_groups('bob', sub{}, $sudoers);

=cut

=head2 normalize_user_and_groups($user, $group, ...)

Agnostic as to username/uid and groupname/gid.

If given just a user:
   - returns uid and user's gid

If given a user and group(s):
   - returns uid and gids for each *given* group
   - does NOT return the user's gid unless it was part of the group list

=cut

sub normalize_user_and_groups {
    my ( $user, @groups ) = @_;

    if ( ( scalar @groups == 1 && !defined $groups[0] ) || ( scalar @groups > 1 && scalar( grep { !defined } @groups ) ) ) {
        require Cpanel::Carp;    # no load module for memory
        die Cpanel::Carp::safe_longmess("Undefined group passed to normalize_user_and_groups");
    }
    my $uid;

    if ( defined $user && $user !~ tr{0-9}{}c ) {
        if ( scalar @groups == 1 && $groups[0] !~ tr{0-9}{}c ) {    # we already have a gid
            return ( $user, $groups[0] );
        }
        $uid = $user;

        # If we only have one group lets try to return early
        # and optimize this case which is the most common
        if ( scalar @groups == 1 && $groups[0] !~ tr{0-9}{}c ) {    # we already have a gid
            return ( $uid, $groups[0] );
        }
    }
    elsif ( !scalar @groups ) {
        ( $uid, @groups ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3 ];

        if ( !defined $uid ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
        }
        return ( $uid, @groups );
    }
    else {
        $uid = Cpanel::PwUtils::normalize_to_uid($user);
    }

    my @gids =
      @groups
      ? ( map { !tr{0-9}{}c ? $_ : scalar( ( getgrnam $_ )[2] ) } @groups )
      : ( ( Cpanel::PwCache::getpwuid_noshadow($uid) )[3] );

    if ( scalar @gids > 2 ) {
        return ( $uid, Cpanel::ArrayFunc::Uniq::uniq(@gids) );
    }
    elsif ( scalar @gids == 2 && $gids[0] eq $gids[1] ) {
        return ( $uid, $gids[0] );
    }

    return ( $uid, @gids );
}

=head2 normalize_code_user_groups( @args )

Searches args for a coderef and returns the list
reordered with the coderef first after the non-code
argument has been passed to normalize_user_and_groups()

=cut

sub normalize_code_user_groups {
    my @args = @_;

    my $code_index;
    for my $i ( 0 .. $#args ) {
        if ( ref $args[$i] eq 'CODE' ) {
            $code_index = $i;
            last;
        }
    }

    die "No coderef found!" if !defined $code_index;

    my $code = splice( @args, $code_index, 1 );

    return ( $code, normalize_user_and_groups( grep { defined } @args ) );
}

1;
