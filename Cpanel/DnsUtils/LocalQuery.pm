package Cpanel::DnsUtils::LocalQuery;

# cpanel - Cpanel/DnsUtils/LocalQuery.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::LocalQuery

=head1 SYNOPSIS

    my $localdns = Cpanel::DnsUtils::LocalQuery->new(
        username => 'bob',
    );

    # Fetch home.bob.com’s A records, using only the local zone data.
    my @rrset = $localdns->ask_batch_sync( 'home.bob.com', 'A' );

=head1 DESCRIPTION

For performance reasons it’s sometimes advantageous to query local
DNS zone data rather than doing actual DNS queries. This module
facilitates that.

=cut

#----------------------------------------------------------------------

use Cpanel::ArrayFunc::Uniq       ();
use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::DnsUtils::Fetch       ();
use Cpanel::DnsUtils::Name        ();
use Cpanel::Config::WebVhosts     ();
use Cpanel::ZoneFile::Search      ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

%OPTS are:

=over

=item * C<username> - The name of the user whose zones to query.

=back

=cut

sub new ( $class, %opts ) {
    my $username = $opts{'username'} or die 'need “username”';

    my $vhconf = Cpanel::Config::WebVhosts->load($username);

    my @zones = (
        $vhconf->main_domain(),
        $vhconf->parked_domains(),
        keys %{ { $vhconf->addon_domains() } },
    );

    return bless { _username => $username, _zones => \@zones }, $class;
}

#----------------------------------------------------------------------

=head2 @results = I<OBJ>->ask_batch_sync( @REQUESTS )

Runs a set of queries in batch.

Each @REQUESTS is an arrayref of: [ $name, @TYPES ], e.g.:

    [ 'foo.example.com', 'A', 'AAAA' ]

(The above will query for C<foo.example.com>’s A I<and> AAAA records.)

Each @results is an arrayref of L<Net::DNS::RR> instances that represents
a single match from the corresponding @REQUESTS member.

=cut

sub ask_batch_sync ( $self, @requests ) {
    my @zonenames = map { $self->_determine_zone_or_die( $_->[0] ) } @requests;

    $self->_prefetch_zones(
        Cpanel::ArrayFunc::Uniq::uniq(@zonenames),
    );

    my @responses;

    for my $i ( 0 .. $#requests ) {
        my $req_ar    = $requests[$i];
        my $queryname = $req_ar->[0];
        my $zonename  = $zonenames[$i];
        my $zone_text = $self->{'_zonetext'}{$zonename};

        my $querytext;
        if ( $zonename eq $queryname ) {
            $querytext = "$queryname.";
        }
        else {
            $querytext = substr( $queryname, 0, -length($zonename) - 1 );
        }

        my @rrs = Cpanel::ZoneFile::Search::name_and_types(
            $zone_text,
            $zonename,
            $querytext,
            @{$req_ar}[ 1 .. $#$req_ar ],
        );

        push @responses, \@rrs;
    }

    return @responses;
}

#----------------------------------------------------------------------

sub _prefetch_zones ( $self, @zonenames ) {
    @zonenames = grep { !$self->{'_zonetext'}{$_} } @zonenames;

    if (@zonenames) {
        my $new_hr = Cpanel::DnsUtils::Fetch::fetch_zones(
            zones => \@zonenames,
            flags => $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY,
        );

        $self->{'_zonetext'}{$_} = $new_hr->{$_} for keys %$new_hr;
    }

    return;
}

sub _determine_zone_or_die ( $self, $name ) {
    my $zone_name = Cpanel::DnsUtils::Name::get_longest_short_match(
        $name,
        $self->{'_zones'},
    );

    if ( !$zone_name ) {
        die "$self->{'_username'} has no zone for $name!";
    }

    return $zone_name;
}

1;
