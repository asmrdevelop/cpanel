package Cpanel::IpTables::TempBan;

# cpanel - Cpanel/IpTables/TempBan.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent             qw{Cpanel::IpTables};
use Cpanel::Time::Clf  ();
use Cpanel::OSSys::Env ();

#
# Example:
#
# perl -MCpanel::IpTables::TempBan -e '
#    my $hulk = Cpanel::XTables::TempBan->new("chain"=>"cphulk");
#    $hulk->init_chain("INPUT");
#    $hulk->add_temp_block("198.12.2.2",time()+800);
#    $hulk->add_temp_block("192.221.22.22",time()-10);
#    $hulk->expire_time_based_rules();
# '
#
# perl -MCpanel::IpTables -e '
#    my $hulk = Cpanel::IpTables->new("chain"=>"cphulk");
#    $hulk->init_chain("INPUT");
#    $hulk->add_temp_block("2001:db8:85a3:0:0:8a2e:370:7334",time()+800);
#    $hulk->add_temp_block("192.221.22.22",time()-10);
#    $hulk->expire_time_based_rules();
# '
#
our $ONE_DAY = 86400;

###########################################################################
#
# Method:
#   can_temp_ban
#
# Description:
#   Returns whether this module can be used: 1 if yes, 0 if no
#
sub can_temp_ban {
    my ($self) = @_;

    return 0 if $self->{'version'} < 1.4;

    return 1;
}

###########################################################################
#
# Method:
#   add_temp_block
#
# Parameters:
#   ip          - The IP address to block
#   expire_time - The time when the block should expire in unixtime.
#
# Description:
#   Temporarly block an IP address from connecting to the server until
#   the expire_time is reached
#
sub add_temp_block {
    my ( $self, $ip, $expire_time ) = @_;

    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    my $utc_expire_datetime = Cpanel::Time::Clf::time2utctime($expire_time);

    # Multiple --match rules are broken under virtuozzo and
    # continue to be broken as of Oct 6 2017.  The NEW
    # state rule is a courtsey to keep users from accidently locking
    # themselves out when they are already connected
    # and not a strict or documneted requirement.  For virtuozzo
    # we will avoid the new state match to work around the bug.
    $self->{'can_use_state'} //= Cpanel::OSSys::Env::get_envtype() eq 'virtuozzo' ? 0 : 1;

    return $self->exec_checked_calls( [ [ '--append', $self->{'chain'}, '--source', $ipdata, ( $self->{'can_use_state'} ? ( '--match', 'state', '--state', 'NEW' ) : () ), '--match', 'time', '--utc', '--datestop', $utc_expire_datetime, '--jump', 'DROP' ] ] );
}

###########################################################################
#
# Method:
#   remove_temp_block
#
# Parameters:
#   ip          - The IP address to unblock
#
# Description:
#   Remove the block for an IP address.
#
sub remove_temp_block {
    my ( $self, $ip ) = @_;
    my $prefix = ( $self->{'ipversion'} == 4 ) ? 32 : 128;

    $ip = "$ip/$prefix" if $ip !~ tr{/}{};

    my $ipdata = $self->validate_ip_is_correct_version_or_die($ip);

    my @calls;
    my $rules_ref = $self->get_chain_rules();
    foreach my $rule ( @{$rules_ref} ) {
        if ( $rule->[0] eq '-A' ) {
            my $rule_ip = $self->_arg_after_key( $rule, 's' );

            next unless defined $rule_ip;
            next unless $ip eq $rule_ip;

            $rule->[0] = '-D';
            push @calls, $rule;
        }
    }

    return 0 unless @calls;

    $self->exec_checked_calls( \@calls );
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
sub expire_time_based_rules {
    my ($self) = @_;

    require HTTP::Date;
    my $now = time() + 2;    # It takes about two seconds to list the rules
    my @calls;
    my $rules_ref = $self->get_chain_rules();
    foreach my $rule ( @{$rules_ref} ) {
        if ( $rule->[0] eq '-A' ) {
            my $utc_time = $self->_arg_after_key( $rule, 'timestop' );
            if ( my $utc_date_time = $self->_arg_after_key( $rule, 'datestop' ) ) {
                if ( $utc_date_time =~ m{T} ) {
                    my ( $date, $time ) = split( m{T}, $utc_date_time );
                    $time          = $utc_time if length $utc_time;
                    $utc_date_time = join( 'T', $date, $time );
                }
                else {
                    $utc_date_time .= 'T' . ( $utc_time || '00:00:00' );
                }
                my $unix_time = HTTP::Date::str2time( $utc_date_time, 'UTC' );
                if ( $unix_time <= $now ) {
                    $rule->[0] = '-D';
                    push @calls, $rule;
                }
            }
        }
    }

    $self->exec_checked_calls( \@calls );
    return 1;
}

###########################################################################
#
# Method:
#   check_chain_position
#
# Description:
#   Check to make sure the jump to the cphulk chain appears in the correct
#   position (first) of the INPUT chain. If not, correct it. This need to be
#   first is unique to cPHulk and so should not be part of the parent class
#   interface.
#
sub check_chain_position {
    my ($self) = @_;

    my ($output_list)    = $self->exec_checked_calls( [ [ '-L', 'INPUT', '1' ] ] );
    my $first_chain_jump = shift @$output_list;
    my ($chain)          = split /\s+/, $first_chain_jump;

    if ( $chain && $chain eq $self->{chain} ) {
        return 1;    # OK
    }

    eval { $self->exec_checked_calls( [ [ '-D', 'INPUT', '-j', $self->{chain} ] ] ); };
    my $delete_exception = $@;    # should normally be ignored; only reported if subsequent insert also fails

    eval { $self->exec_checked_calls( [ [ '-I', 'INPUT', '-j', $self->{chain} ] ] ); };
    my $insert_exception = $@;

    if ($insert_exception) {
        die "Delete: $delete_exception\nInsert: $insert_exception\n";
    }

    return 1;
}

1;
