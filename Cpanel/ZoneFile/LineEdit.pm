package Cpanel::ZoneFile::LineEdit;

# cpanel - Cpanel/ZoneFile/LineEdit.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::LineEdit

=head1 SYNOPSIS

    my $edit_obj = Cpanel::ZoneFile::LineEdit->new(
        zone => 'free-willy.tld',
        serial => 2021021602,
    );

    my $old_hr = $edit_obj->get_item_by_line(23);

    $edit_obj->add( 'the-name', 14400, 'TXT', 'épée', 'foo bar' );

    $edit_obj->edit( 12, 14401, 'new', 'values' );

    $edit_obj->remove( 23 );

    $edit_obj->save();

=head1 DESCRIPTION

This class implements an interactive zone editor that makes multiple
updates to the zone in a single push of the DNS zone to dnsadmin.

Edits to the zone happen against the zone’s RFC-1035 format.
As of this writing that’s the backend storage format, but that could
change down the road.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::DnsUtils::CheckZone         ();
use Cpanel::DnsUtils::Fetch             ();
use Cpanel::DnsUtils::AskDnsAdmin       ();
use Cpanel::Exception                   ();
use Cpanel::Time                        ();
use Cpanel::ZoneFile::LineEdit::Backend ();
use Cpanel::ZoneFile::Parse             ();
use Cpanel::ZoneFile::Versioning        ();
use Cpanel::DnsUtils::AskDnsAdmin       ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

%OPTS are:

=over

=item * C<zone> - The name of the zone to edit.

=item * C<serial> - The SOA record’s serial number. Must match
the same value in the zone, or an exception is thrown to indicate an
invalid edit.

=back

Specific exceptions:

=over

=item * L<Cpanel::Exception::Stale> is thrown if the given C<serial>
mismatches the zone’s serial number.

=item * C<Cpanel::Exception::InvalidParameter> is thrown for invalid-input
cases.

=back

=cut

sub new ( $class, %opts ) {
    my $zonename = $opts{'zone'} or die Cpanel::Exception::create_raw( 'MissingParameter', 'Need “zone”' );
    my $serial   = $opts{'serial'} // die Cpanel::Exception::create_raw( 'MissingParameter', 'Need “serial”' );

    $zonename =~ s<\.\z><>;

    my $zonetext = Cpanel::DnsUtils::Fetch::fetch_zones( zones => [$zonename] )->{$zonename};

    my $parse_ar = Cpanel::ZoneFile::Parse::parse_string( $zonetext, $zonename );

    _validate_serial_number( $zonename, $parse_ar, $serial );

    return bless {
        name     => $zonename,
        parse_ar => $parse_ar,
        new      => [],
    }, $class;
}

=head2 $item_hr = I<OBJ>->get_item_by_line( $LINE_INDEX )

Gives the hashref that corresponds to the item on the indicated line.

Undef is returned if no such item exists. Otherwise,
the return format is that from L<Cpanel::ZoneFile::Parse>’s
C<parse_string()> function.

=cut

sub get_item_by_line ( $self, $line_index ) {
    my $parse_ar = $self->{'parse_ar'};

    my ($found) = grep { $_->{'line_index'} == $line_index } @$parse_ar;

    return $found;
}

sub _validate_serial_number ( $zonename, $parse_ar, $serial ) {
    my $old_serial;

    for my $item (@$parse_ar) {
        next if !$item->{'record_type'};
        next if $item->{'record_type'} ne 'SOA';

        $old_serial = $item->{'data'}[2];
        last;
    }

    if ( defined $old_serial ) {
        if ( $serial ne $old_serial ) {
            die Cpanel::Exception::create( 'Stale', 'The given serial number ([_1]) does not match the [asis,DNS] zone’s serial number ([_2]). Refresh your view of the [asis,DNS] zone, then resubmit.', [ $serial, $old_serial ] );
        }
    }
    else {
        warn "No serial number found in $zonename’s zone! Skipping validation.\n";
    }

    return;
}

=head2 I<OBJ>->add( $NAME, $TTL, $RTYPE, @VALUE )

Adds an entry to the end of the zone file.

Note that the order of arguments corresponds to the order in which the
different pieces appear in a zone file record: name, TTL, type, value(s).
(cf. RFC 1035, section 5.1)

=cut

sub add ( $self, $dname, $ttl, $type, @value ) {
    if ( $type eq 'SOA' ) {
        die _only1soa_err();
    }

    push @{ $self->{'new'} }, _build_line( $self->{'name'}, $dname, $ttl, $type, @value );

    return;
}

sub _only1soa_err {
    return Cpanel::Exception::create( 'InvalidParameter', 'Only one [asis,SOA] record can exist in a given [asis,DNS] zone.' );
}

=head2 I<OBJ>->edit( $LINE_INDEX, $NAME, $TTL, $RTYPE, @VALUE )

Edits a record. $RTYPE may be undef to preserve the existing
record’s type.

Note that, as with C<add()>, the order of arguments matches
zone file formatting.

=cut

sub edit ( $self, $lineidx, $dname, $ttl, $rtype, @value ) {    ## no critic qw(ManyArgs) - done for consistency w/ add function
    my $original = $self->_verify_lineidx_for_new_op($lineidx);

    if ( $original->{'record_type'} eq 'SOA' ) {
        if ( $rtype ne 'SOA' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The [asis,SOA] record’s type cannot change.' );
        }

        my $old_dname = $original->{'dname'} =~ s<\.\z><>r;

        if ( $old_dname ne ( $dname =~ s<\.\z><>r ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', "The [asis,SOA] record’s name cannot change." );
        }

        if ( $original->{'data'}[2] ne $value[2] ) {
            die Cpanel::Exception::create( 'InvalidParameter', "This system forbids direct updates to the [asis,SOA] record’s serial number. Provide the old serial number ([_1]) instead, and the system will upate the serial number for you.", [ $original->{'data'}[2] ] );
        }

        _bump_soa_serial( \@value );

        $self->{'new_serial'} = $value[2];
    }
    elsif ( $rtype eq 'SOA' ) {
        die _only1soa_err();
    }

    $self->{'edits'}{$lineidx} = _build_line( $self->{'name'}, $dname, $ttl, $rtype, @value );

    return;
}

=head2 I<OBJ>->remove( $LINE_INDEX )

Enqueues an entry, by line index, for removal.

=cut

sub remove ( $self, $lineidx ) {
    my $original = $self->_verify_lineidx_for_new_op($lineidx);

    if ( $original->{'record_type'} eq 'SOA' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Every [asis,DNS] zone must contain an [asis,SOA] record.' );
    }

    $self->{'removals'}{$lineidx} = 1;

    return;
}

sub _verify_lineidx_for_new_op ( $self, $lineidx ) {
    my ($original) = grep { $_->{'line_index'} == $lineidx } $self->{'parse_ar'}->@*;

    if ( !$original || $original->{'type'} ne 'record' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'No record exists at line [numf,_1] in the “[_2]” [asis,DNS] zone.', [ $lineidx, $self->{'name'} ] );
    }

    if ( exists $self->{'edits'}{$lineidx} || exists $self->{'removals'}{$lineidx} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'You submitted multiple edits for line index [numf,_1]. This interface forbids multiple edits per line.', [$lineidx] );
    }

    return $original;
}

sub _build_line ( $zonename, $dname, $ttl, $type, @value ) {
    if ( '.' ne substr( $dname, -1 ) ) {
        $dname .= ".$zonename.";
    }

    my $text = Cpanel::ZoneFile::LineEdit::Backend::build_line( $dname, $ttl, $type, @value );

    # To accommodate pre-9.6 BIND, we have to encode CAA as generic RDATA.
    if ( $type eq 'CAA' ) {
        require Cpanel::DnsUtils::CAA;
        require Cpanel::DnsUtils::GenericRdata;

        my $rdata = Cpanel::DnsUtils::CAA::encode_rdata(@value);

        my $generic_rdata = Cpanel::DnsUtils::GenericRdata::encode($rdata);

        $text =~ s<CAA(\s+).*><TYPE257$1$generic_rdata> or do {

            # A sanity check:
            Carp::confess('CAA record didn’t yield a CAA string??');
        };
    }

    $text =~ s<\A(\S+)\.\Q$zonename\E\.><$1>;

    return $text;
}

sub _bump_soa_serial ($soa_data_ar) {
    my $today_serial = Cpanel::Time::time2dnstime() . '00';
    my $old_serial   = $soa_data_ar->[2];

    if ( $today_serial > $old_serial ) {
        $soa_data_ar->[2] = $today_serial;
    }
    else {
        $soa_data_ar->[2]++;
    }

    return;
}

=head2 $new_serial = I<OBJ>->save()

Publishes the zone. May only be called once on I<OBJ>; a subsequent
invocation will trigger an exception.

This returns the SOA record’s new serial number. Each record will occupy
the same number of lines in the file as it took before, so it is possible
for a caller to re-edit the zone file without first needing to grab the
zone’s contents separately. (If the zone happens to change in between
the caller’s edits, the second edit will fail because of an invalid serial
number.)

=cut

sub save ($self) {
    if ( $self->{'saved'} ) {
        Carp::confess('Repeat save attempted!');
    }

    my $new_zone_text = q<>;

    my $has_at_least_one_ns_record;
    my $version_line_seen;

    for my $item_index ( 0 .. $#{ $self->{'parse_ar'} } ) {
        my $item = $self->{'parse_ar'}[$item_index];

        # We write out each record on a single line. Thus, a record that
        # was multi-line when we parsed the zone will now be all on a single
        # line. When this module first shipped that meant that all subsequent
        # records would then be on a different-numbered line after the save.
        # That turned out to be suboptimal for our UI.
        #
        # We now do something a bit nicer: each record takes up the same
        # number of lines before and after the save. We achieve this by
        # postfixing enough blank lines after each formerly-multi-line
        # record so that the next record still starts on the same line that
        # it did before.
        #
        # This approach of deducing a record’s “line height” by comparing
        # to the next item in the zone-file parse only works, of course,
        # for non-final entries in the zone file.
        #
        my $next_item   = $self->{'parse_ar'}[ 1 + $item_index ];
        my $extra_lines = $next_item ? ( $next_item->{'line_index'} - $item->{'line_index'} - 1 ) : 0;

        my $itemtype = $item->{'type'};

        next if $self->{'removals'}{ $item->{'line_index'} };

        my $new_text;

        if ( $itemtype eq 'record' ) {
            if ( $item->{'record_type'} eq 'NS' ) {
                $has_at_least_one_ns_record = 1;
            }

            $new_text = $self->{'edits'}{ $item->{'line_index'} } // do {
                my @data = $item->{'data'}->@*;

                if ( $item->{'record_type'} eq 'SOA' ) {
                    _bump_soa_serial( \@data );
                    $self->{'new_serial'} = $data[2];
                }

                _build_line(
                    $self->{'name'},
                    @{$item}{ 'dname', 'ttl', 'record_type' },
                    @data,
                );
            };
        }
        elsif ( grep { $_ eq $itemtype } qw( comment control ) ) {
            $new_text = $item->{'text'};

            if ( $itemtype eq 'comment' ) {
                if ( !$version_line_seen && ( index( $new_text, 'cPanel' ) != -1 ) && $new_text =~ $Cpanel::ZoneFile::Versioning::STARTMATCH ) {
                    $new_text          = Cpanel::ZoneFile::Versioning::version_line($1);
                    $version_line_seen = 1;
                }
            }
        }
        else {

            # Shouldn’t happen unless C::ZoneFile::Parse changes.
            Carp::confess("Unknown item type: $itemtype");
        }

        $new_zone_text .= "$new_text\n";
        $new_zone_text .= "\n" for ( 1 .. $extra_lines );
    }

    if ( !$version_line_seen ) {
        warn "No cPanel version line seen in edited DNS zone ($self->{'name'})!\n";
    }

    if ( !$has_at_least_one_ns_record ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Every [asis,DNS] zone must contain at least one “[_1]” record.', ['NS'] );
    }

    $new_zone_text .= "$_\n" for $self->{'new'}->@*;

    my $zonename = $self->{'name'};

    Cpanel::DnsUtils::CheckZone::assert_validity(
        $zonename,
        $new_zone_text,
    );

    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', 0, $zonename, $new_zone_text );
    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADBIND', 0, $zonename );

    $self->{'saved'} = 1;

    return $self->{'new_serial'};
}

#----------------------------------------------------------------------

1;
