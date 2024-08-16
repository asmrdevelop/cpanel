package Cpanel::DnsUtils::FixTTLs;

# cpanel - Cpanel/DnsUtils/FixTTLs.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::FixTTLs

=head1 SYNOPSIS

    Cpanel::DnsUtils::FixTTLs::report_problems( $output_obj );

=head1 DESCRIPTION

This module identifies and (if desired) fixes problems with DNS
records’ TTLs.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Imports;

use List::Util ();

use Cpanel::Exception             ();
use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::DnsUtils::List        ();
use Cpanel::QuickZoneFetch        ();

use Whostmgr::ACLS ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 report_problems( $OUTPUT_OBJ )

Iterates through all DNS zones on the server and identifies—but does B<not>
fix—probles with records’ TTLs. $OUTPUT_OBJ is a L<Cpanel::Output> instance.

=cut

sub report_problems ($output_obj) {
    return _report_and_maybe_fix_problems( $output_obj, 0 );
}

=head2 report_and_fix_problems( $OUTPUT_OBJ )

Like C<report_problems()> but will try to fix the problems it reports.

=cut

sub report_and_fix_problems ($output_obj) {
    return _report_and_maybe_fix_problems( $output_obj, 1 );
}

#----------------------------------------------------------------------

sub _report_and_maybe_fix_problems ( $output_obj, $fix_yn ) {
    $output_obj->info( locale()->maketext('Fetching [asis,DNS] zone list …') );

    my $zonenames_ar = Cpanel::DnsUtils::List::listzones(
        hasroot => Whostmgr::ACLS::hasroot(),
    );

    $output_obj->info( locale()->maketext( 'Checking [numf,_1] [asis,DNS] [numerate,_1,zone,zones] …', 0 + @$zonenames_ar ) );

    # Randomize the order so that if this script runs concurrently on
    # multiple nodes within the same DNS cluster there is less chance
    # of 2+ nodes trying to alter the same zone concurrently.
    #
    # (We might also just restrict this script to locally-stored zones,
    # but that would leave non-cPanel DNS cluster nodes unfixed.)
    #
    my @shuffled = List::Util::shuffle @$zonenames_ar;

    for my $zonename (@shuffled) {
        try {
            my $zf_obj = Cpanel::QuickZoneFetch::fetch($zonename);

            _analyze_zone( $zonename, $zf_obj, $output_obj, $fix_yn );
        }
        catch {
            $output_obj->error( "$zonename: " . Cpanel::Exception::get_string($_) );
        };
    }

    return;
}

sub _analyze_zone ( $zonename, $zf_obj, $output_obj, $fix_yn ) {    ## no critic qw(ManyArgs) - mis-parse
    my %rrset_ttl_lookup;

    my %rrset_needs_update;

    for my $rec ( $zf_obj->find_records() ) {
        next if !length $rec->{'name'};

        my $rrset_key = "@{$rec}{'name', 'type'}";

        $rrset_ttl_lookup{$rrset_key}{ $rec->{'ttl'} } = undef;

        if ( 1 < keys %{ $rrset_ttl_lookup{$rrset_key} } ) {
            $rrset_needs_update{$rrset_key} = undef;
        }
    }

    return 0 if !%rrset_needs_update;

    $output_obj->warn( locale()->maketext( '“[_1]” is invalid.', $zonename ) );

    my $indent = $output_obj->create_indent_guard();

    for my $rrset_key ( sort keys %rrset_needs_update ) {
        my @ttls = keys %{ $rrset_ttl_lookup{$rrset_key} };

        @ttls = sort { $a <=> $b } @ttls;

        $output_obj->out( locale()->maketext( '[_1]: multiple [asis,TTL]s ([join,~, ,_2])', $rrset_key, \@ttls ) );

        next if !$fix_yn;

        my ( $name, $type ) = split m< >, $rrset_key;

        my $new_ttl = $ttls[0];

        my @recs = $zf_obj->find_records( name => $name, type => $type );

        $_->{'ttl'} = $new_ttl for @recs;

        $zf_obj->replace_records( \@recs );
    }

    if ($fix_yn) {
        $zf_obj->increase_serial_number();
        my $new_text_ar = $zf_obj->serialize();

        # Empty string is to have a trailing newline:
        my $new_text = join( "\n", @$new_text_ar, q<> );

        my $message = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', 0, $zonename, $new_text );

        if ($message) {
            $output_obj->warn($message);
        }
        else {
            $output_obj->success( locale()->maketext('Fixed.') );
        }
    }

    return 1;
}

1;
