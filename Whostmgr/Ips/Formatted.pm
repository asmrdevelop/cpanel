package Whostmgr::Ips::Formatted;

# cpanel - Whostmgr/Ips/Formatted.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

require 5.010;    # For defined or.

use strict;

use Cpanel::Locale ();
use Cpanel::NAT    ();
use Whostmgr::Ips  ();
use Cpanel::DIp    ();

my $locale;

sub locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

=head1 SUBROUTINES

=over 4

=item C<_get_ip_notes>

=over 12

=item input: hash reference describing an ip status ( can come from Cpanel::DIp::get_ip_info )

=item output: string formatted in html and localized describing the IP status

=back

Returns a localized string in html format and localized from an IP information ( can come from Cpanel::DIp::get_ip_info )
describing the current IP status.

I<This sub was originaly located in bin/whostmgr2>

=cut

sub _get_ip_notes {
    my $ipdata = shift or return '';

    my @notes;
    if ( $ipdata->{'reserved'} && $ipdata->{'reserved_reason'} ) {
        push @notes, locale->maketext( 'Reserved ([_1])', $ipdata->{'reserved_reason'} );
    }
    elsif ( $ipdata->{'reserved'} ) {
        push @notes, locale->maketext('Reserved');
    }

    if ( $ipdata->{'shared'} ) {
        my $shared_count = @{ $ipdata->{'shared'} };
        if ( $shared_count > 10 ) {
            my @short_list = @{ $ipdata->{'shared'} }[ 0 .. 9 ];
            push @notes, locale->maketext( 'Main/shared IP for: [join,~, ,_1], and [quant,_2,other,others]', \@short_list, $shared_count - 10 );
        }
        elsif ($shared_count) {
            push @notes, locale->maketext( 'Main/shared IP for: [list_and,_1]', $ipdata->{'shared'} );
        }
    }

    if ( $ipdata->{'delegated'} ) {
        my $delegated_count = @{ $ipdata->{'delegated'} };
        if ( $delegated_count > 10 ) {
            my @short_list = @{ $ipdata->{'delegated'} }[ 0 .. 9 ];
            push @notes, locale->maketext( 'Delegated to: [join,~, ,_1], and [quant,_2,other,others]', \@short_list, $delegated_count - 10 );
        }
        elsif ($delegated_count) {
            push @notes, locale->maketext( 'Delegated to: [list_and,_1]', $ipdata->{'delegated'} );
        }
    }

    push @notes, locale->maketext( 'Dedicated to: [_1]', $ipdata->{'dedicated_user'} ) if ( $ipdata->{'dedicated_user'} );
    push @notes, locale->maketext( 'Nameserver: [_1]',   $ipdata->{'nameserver'} )     if ( $ipdata->{'nameserver'} );
    my $string = join( '<br />', @notes );
    return $string || '';
}

=item C<get_formatted_ip_data>

=over 12

=item input: none

=item output: array reference of hash describing each ip

=back

Sample output format:
C<<
[
    {
        local_ip  => 10.0.0.42,
        public_ip => 42.0.0.42,
        interface => eth0:cp42,
        removable => 1, # boolean
        notes     => 'string formated with _get_ip_notes',
        error_row => 1, # id referencing the row number
    },
    ...
]
>>

I<this code was originaly located in bin/whostmgr2 listips>

=cut

sub get_formatted_ip_data {

    my $iplist = Whostmgr::Ips::get_detailed_ip_cfg();
    my $ipdata = Cpanel::DIp::get_ip_info();
    my @table_data;

    my $is_nat = Cpanel::NAT::is_nat();

    if ($is_nat) {    ### NAT MODE ###
        my $ordered_list = Cpanel::NAT::ordered_list();

        my $if_map = {};
        foreach my $alias (@$iplist) {
            $alias->{'public_ip'}             = $alias->{'ip'};
            $alias->{'local_ip'}              = Cpanel::NAT::get_local_ip( $alias->{'ip'} );
            $if_map->{ $alias->{'local_ip'} } = $alias;
        }

        my $row_num = 0;
        foreach my $nat_data (@$ordered_list) {
            $row_num++;

            if ( ref $nat_data->[0] eq 'ARRAY' ) {
                foreach my $dupe_row (@$nat_data) {
                    my $local_ip = $dupe_row->[0] or next;

                    # Let the user remove unroutable IPs.
                    my $alias = $if_map->{$local_ip} // { removable => 1 };

                    push @table_data,
                      {
                        local_ip  => $local_ip,
                        public_ip => $dupe_row->[1] || '',
                        interface => $alias->{'if'},
                        removable => $alias->{'removable'},
                        notes     => _get_ip_notes( $ipdata->{$local_ip} ),
                        error_row => $row_num,
                      };
                }
            }
            else {
                my $local_ip = $nat_data->[0] or next;

                # Let the user remove unroutable IPs.
                my $alias = $if_map->{$local_ip} // { removable => 1 };

                push @table_data,
                  {
                    local_ip  => $local_ip,
                    public_ip => $nat_data->[1] || '',
                    interface => $alias->{'if'},
                    removable => $alias->{'removable'},
                    notes     => _get_ip_notes( $ipdata->{$local_ip} ),
                  };
            }
        }
    }
    else {    ### NOT IN NAT MODE ###
        foreach my $alias ( sort { $a->{'if'} cmp $b->{'if'} } @$iplist ) {
            my $ip = $alias->{'ip'};
            push @table_data,
              {
                local_ip  => $ip || '',
                public_ip => $ip || '',
                interface => $alias->{'if'},
                removable => $alias->{'removable'},
                notes     => _get_ip_notes( $ipdata->{$ip} ),
              };
        }
    }

    return \@table_data;
}

=back

=cut

1;
