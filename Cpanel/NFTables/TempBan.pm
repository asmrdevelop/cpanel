package Cpanel::NFTables::TempBan;

# cpanel - Cpanel/NFTables/TempBan.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw{Cpanel::NFTables};

=head1 NAME

Cpanel::NFTables::TempBan

=head1 SYNOPSIS

    perl -MCpanel::XTables::TempBan -e '
       my $hulk = Cpanel::XTables::TempBan->new("chain"=>"cphulk");
       $hulk->init_chain("INPUT");
       $hulk->add_temp_block("198.12.2.2",time()+800);
       $hulk->add_temp_block("192.221.22.22",time()-10);
       $hulk->expire_time_based_rules();
    '

    perl -MCpanel::XTables -e '
       my $hulk = Cpanel::XTables->new("chain"=>"cphulk");
       $hulk->init_chain("INPUT");
       $hulk->add_temp_block("2001:db8:85a3:0:0:8a2e:370:7334",time()+800);
       $hulk->add_temp_block("192.221.22.22",time()-10);
       $hulk->expire_time_based_rules();
    '

=head1 DESCRIPTION

This modules is a *subclass* of Cpanel::XTables meant to be delivered via
the Cpanel::XTables::TempBan factory class.

It implements NFTables specific logic.

=head2 SEE ALSO

Cpanel::NFTables
Cpanel::XTables::TempBan

=head1 METHODS

=head2 can_temp_ban

Returns 1, as we can temp ban with nftables.

=cut

#
# Example:
#
#
our $ONE_DAY = 86400;

sub can_temp_ban {
    return 1;
}

=head2 add_temp_block

    Parameters:
      ip          - The IP address to block
      expire_time - The time when the block should expire in unixtime.

    Description:
      Temporarly block an IP address from connecting to the server until
      the expire_time is reached

=cut

sub add_temp_block ( $self, $ip, $expire_time ) {
    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    # XXX I don't know whether 'state' will be fine on Virtuozzo yet on nftables!
    # For now will just assume things are fine on vzzo.
    my $set   = "$self->{'chain'}-TempBan";
    my $type  = 'ipv' . $self->ipversion() . '_addr';
    my $calls = [];

    # Add the set if it does not exist
    if ( !$self->set_exists($set) ) {

        # nftables doesn't use a timeout value of a unix epoch, but rather an addition of time, such as 10s, 14m, 3h, or all three, like 2h30m20s
        # to ensure we have a viable value, check the expire_time value and calculate what it should be if passed an epoch.
        my $cur_time = time();
        if ( $expire_time > $cur_time ) {
            $expire_time = $expire_time - $cur_time;
        }
        push @$calls, [ qw{add set }, $self->IP_FAMILY, $self->TABLE, $set, '{', 'type', "$type;", qw{flags timeout; timeout}, "${expire_time}s", qw/; }/ ],;
    }

    # Add the chain rule if it does not exist. Ordering is important, as the
    # set must exist first before the chain rule.
    if ( !grep { $_->{'chain'} eq 'cphulk' } @{ $self->get_rules() } ) {
        push @$calls, [ qw{add rule }, $self->IP_FAMILY, $self->TABLE, $self->{'chain'}, qw{ip saddr}, "\@$set", qw{drop} ];
    }

    # Add ip as element to set
    push @$calls, [ qw{add element }, $self->IP_FAMILY, $self->TABLE, $set, '{', $ipdata, '}' ];
    return $self->exec_checked_calls($calls);
}

=head2 remove_temp_block

    Parameters:
      ip          - The IP address to unblock

    Description:
      Remove the block for an IP address.

=cut

sub remove_temp_block ( $self, $ip ) {
    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    my $set   = "$self->{'chain'}-TempBan";
    my $calls = [ [ qw{delete element }, $self->IP_FAMILY, $self->TABLE, $set, '{', $ipdata, '}' ] ];
    eval { $self->exec_checked_calls($calls) };
    die $@ if $@ && $@ !~ qr/No such file or directory/;
    return 1;
}

###########################################################################
#
# Method:
#   expire_time_based_rules
#
# Description:
#   Remove temporary blocking rules from iptables once they
#   have expired.
#   NOTE: Even if this method is never called, the rules will still stop
#   actually blocking anything; they'll just sit there inert until they're
#   reaped.
#
#  Notes:
#    This needs to understand the following formats
#    -A cphulk -s 10.215.217.79/32 -m state --state NEW -m time --datestop 2014-10-28 --timestop 01:30:08 --utc -j DROP
#    -A cphulk -s 10.215.217.79/32 -m state --state NEW -m time --timestart 00:00:00 --timestop 01:30:08 --datestop 2014-10-28T00:00:00 --utc -j DROP
#    -A cphulk -s 10.215.217.79/32 -m state --state NEW -m time --datestop 2014-10-28T01:30:08 --utc -j DROP

=head2 expire_time_based_rules

    Returns 1, as time based rules expire themselves in NFTables.
    Delete them if you wanna get rid of them early.

=cut

sub expire_time_based_rules {
    return 1;    # NFTables reaps them automatically, yay
}

=head2 check_chain_position

    Returns 1, as we do not appear to need this currently.

=cut

sub check_chain_position {
    return 1;
}

1;
