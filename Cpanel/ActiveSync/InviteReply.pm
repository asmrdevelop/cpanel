# cpanel - Cpanel/ActiveSync/InviteReply.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ActiveSync::InviteReply;

use strict;
use warnings;
use DateTime;
use Email::MIME;
use HTTP::Tiny;
use XML::Parser;

local $SIG{__WARN__} = sub { die "[$0] Fatal warning: " . shift };

use subs 'logmsg';

my ( $USER, $HTTP_AUTH );

=head1 INVITE REPLY HANDLING

The procedure here at a high level is:

1) Examine the email message. If it looks like an invite reply,
search CCS for a copy of the event in question.

2) If found, update the VCALENDAR data from the email message
to have the same unique id as the copy of the event in CCS.

3) Use the amended VCALENDAR data to reply to the event over
CalDAV.

=head1 TERMINOLOGY

The term "VCALENDAR data" for our purposes here can be thought of
as interchangeable with "iCalendar data" or "ics data". The more
correct term for what we're dealing with is iCalendar, but
due to the relatedness of the formats VCALENDAR matches what you
can expect to see in the event data itself.

=head1 FUNCTIONS

=head2 process()

Main

=cut

sub process {
    ( $USER, $HTTP_AUTH, my $message ) = @_;
    $USER      or die 'need USER';
    $HTTP_AUTH or die 'need HTTP_AUTH';
    $message   or die 'need message';

    my $parsed = Email::MIME->new($message);
    my $activesync_vcalendar_data;
    for my $part ( $parsed->parts ) {
        my %headers = $part->header_str_pairs;
        if ( $headers{'Content-Type'} =~ m<text/calendar> ) {
            $activesync_vcalendar_data = $part->body;
        }
    }
    if ( !$activesync_vcalendar_data ) {
        logmsg 'Did not find any VCALENDAR data in the message';
        return 0;
    }

    _munge_vcalendar( \$activesync_vcalendar_data );

    my ( $range_begin, $range_end ) = _get_search_time_range($activesync_vcalendar_data);
    my $summary = _get_field( $activesync_vcalendar_data, 'SUMMARY' );

    my ( $ccs_event_uid, $ccs_event_organizer_line, $ccs_event_href ) = _get_ccs_event_info( $range_begin, $range_end, $summary );
    if ( !$ccs_event_uid ) {
        logmsg 'Did not find the correct UID for the event in CCS';
        return 0;
    }

    $activesync_vcalendar_data =~ s/^UID:.*$/UID:$ccs_event_uid/m;
    $activesync_vcalendar_data =~ s/^ORGANIZER.*$/$ccs_event_organizer_line/m;    # Android simplifies the ORGANIZER field in a way that's incompatible with CCS, so disregard the Android-provided value

    return _reply_over_caldav( $ccs_event_href, $activesync_vcalendar_data );
}

################################################################

# Given a piece of VCALENDAR data, determine a suitable time range for searching for that event
sub _get_search_time_range {
    my ($activesync_vcalendar_data) = @_;

    my ( $dtstart_tzref, $dtstart_year, $dtstart_month, $dtstart_day, $dtstart_hour, $dtstart_minute, $dtstart_second ) = $activesync_vcalendar_data =~ m<
        ^DTSTART                                        # field name
        (?:;TZID=([^:]+))?                              # optional time zone specification prefix
        :                                               # separator
        ([0-9]{4}) ([0-9]{2}) ([0-9]{2}) T ([0-9]{2}) ([0-9]{2}) ([0-9]{2}) # ISO-8601 format date/time
        (?:Z)?                                          # Z if UTC
    >mx;

    if ( !$dtstart_year ) {
        die "Failed to parse DTSTART timestamp from $activesync_vcalendar_data";
    }

    my $dtstart_obj = DateTime->new(
        year       => $dtstart_year,
        month      => $dtstart_month,
        day        => $dtstart_day,
        hour       => $dtstart_hour,
        minute     => $dtstart_minute,
        second     => $dtstart_second,
        nanosecond => 0,
        time_zone  => $dtstart_tzref || 'UTC',
    );

    $dtstart_obj->set_time_zone('UTC');

    $dtstart_obj->subtract( minutes => 5 );
    my $range_begin = sprintf( '%sT%sZ', $dtstart_obj->ymd(''), $dtstart_obj->hms('') );
    $dtstart_obj->add( minutes => 10 );
    my $range_end = sprintf( '%sT%sZ', $dtstart_obj->ymd(''), $dtstart_obj->hms('') );

    return ( $range_begin, $range_end );
}

# Look up a property's value from VCALENDAR data (is not aware of property parameters)
sub _get_field {
    my ( $vcalendar, $field ) = @_;
    my ($value) = $vcalendar =~ /^\Q$field\E:([\S ]+)/m;
    if ( !defined($value) ) {
        die "Failed to extract $field field from $vcalendar";
    }
    return $value;
}

# Given a search time range and an event summary (name), attempt to find the unique id and ics path of the event in CCS
sub _get_ccs_event_info {
    my ( $range_begin, $range_end, $summary ) = @_;

    # Gmail app SUMMARY format:         Event update: Event name
    # Samsung Mail app SUMMARY format:  Accepted: Event update: Event name
    # Desired format:                   Event name
    $summary =~ s/^[^:]+: //;                          # This may be in any language
    $summary =~ s/^Event (?:invitation|update): //;    # Samsung

    logmsg sprintf( 'Searching for event from “%s” to “%s” with summary ”%s”', $range_begin, $range_end, $summary );

    my $lookup_body_format = <<'EOF';
<?xml version="1.0" encoding="utf-8" ?>
   <C:calendar-query xmlns:D="DAV:"
         xmlns:C="urn:ietf:params:xml:ns:caldav">
     <D:prop>
       <D:getetag/>
       <C:calendar-data>
     <C:comp name="VCALENDAR">
       <C:prop name="VERSION"/>
       <C:comp name="VEVENT">
         <C:prop name="SUMMARY"/>
         <C:prop name="UID"/>
         <C:prop name="DTSTART"/>
         <C:prop name="DTEND"/>
         <C:prop name="ORGANIZER"/>
       </C:comp>
       <C:comp name="VTIMEZONE"/>
     </C:comp>
       </C:calendar-data>
     </D:prop>
     <C:filter>
       <C:comp-filter name="VCALENDAR">
     <C:comp-filter name="VEVENT">
       <C:time-range start="%s"
             end="%s"/>
     </C:comp-filter>
       </C:comp-filter>
     </C:filter>
   </C:calendar-query>
EOF

    my $lookup_body = sprintf( $lookup_body_format, $range_begin, $range_end );

    my $response = HTTP::Tiny->new->request(
        'REPORT',
        "https://127.0.0.1:2080/calendars/users/$USER/",
        {
            headers => {
                'Authorization'  => $HTTP_AUTH,
                'User-Agent'     => 'invite-reply',
                'Accept'         => '*/*',
                'Content-Type'   => 'application/xml; charset="utf-8"',
                'Depth'          => '1',
                'Content-Length' => length($lookup_body),
            },
            content => $lookup_body,
        },
    );

    my $matches = _parse_multistatus_xml( $response->{content} );
    logmsg sprintf( 'Found %d match(es) (want 1) for the time range', scalar(@$matches) );

    my ( $ccs_event_uid, $ccs_event_organizer_line, $ccs_event_href );
    for my $match (@$matches) {
        my ( $calendar_data, $href, $status ) = @$match{ 'multistatus:response:propstat:prop:calendar-data', 'multistatus:response:href', 'multistatus:response:propstat:status' };
        if ( $status ne 'HTTP/1.1 200 OK' ) {
            logmsg sprintf( 'Unexpected multistatus response status: %s', $status );
            next;
        }

        my $match_summary = _get_field( $calendar_data, 'SUMMARY' );
        if ( $match_summary && $match_summary eq $summary ) {
            logmsg 'Found an event in CCS matching the date and summary of the expected one';
            _munge_vcalendar( \$calendar_data );
            $ccs_event_uid = _get_field( $calendar_data, 'UID' );
            ($ccs_event_organizer_line) = $calendar_data =~ /^(ORGANIZER[:;][\S ]+(?:\015?\012[ \011][\S ]+)?)/m;
            if ( !$ccs_event_organizer_line ) {
                logmsg 'Did not find CCS organizer';
                die;
            }
            $ccs_event_href = $href;
            last;
        }
        else {
            logmsg "CCS event summary “$match_summary” is not the expected summary “$summary”";
        }
    }

    return ( $ccs_event_uid, $ccs_event_organizer_line, $ccs_event_href );
}

sub _parse_multistatus_xml {
    my ($xml) = @_;

    my @parsed;
    my $inText = undef;

    # For each multistatus response, populate a hash ref with attributes named
    # multistatus:response:something:something containing any text values underneath
    # that response.
    my $parser = XML::Parser->new(
        Handlers => {
            Start => sub {
                my ( $xml_parser_expat, $name ) = @_;
                my $context = join( ':', $xml_parser_expat->context );
                if ( $context eq 'multistatus' && $name eq 'response' ) {
                    push @parsed, {};
                }
                $inText = $context . ':' . $name;
            },
            End => sub {
                my ( $xml_parser_expat, $name ) = @_;
                my $context = join( ':', $xml_parser_expat->context );
                $inText = $context;
            },
            Char => sub {
                my ( $xml_parser_expat, $text ) = @_;
                my @context = $xml_parser_expat->context;
                if ( $inText && @context >= 2 && 'multistatus:response' eq join( ':', @context[ 0, 1 ] ) ) {
                    $parsed[-1]{$inText} .= $text;
                }
            },
        },
    );

    $parser->parse($xml);

    return \@parsed;
}

# Update the event in CCS with the attendee's response
sub _reply_over_caldav {
    my ( $ccs_event_href, $activesync_vcalendar_data ) = @_;

    my $put_response = HTTP::Tiny->new->put(
        'https://127.0.0.1:2080' . $ccs_event_href,
        {
            headers => {
                'Authorization'  => $HTTP_AUTH,
                'User-Agent'     => 'invite-reply',
                'Accept'         => '*/*',
                'Content-Type'   => 'text/calendar',
                'Content-Length' => length($activesync_vcalendar_data),
            },
            content => $activesync_vcalendar_data,
        },
    );
    if ( $put_response->{status} == 204 ) {
        logmsg 'Updated event in CCS';
        return 1;
    }

    logmsg "Got unexpected status $put_response->{status} while trying to update event";
    return 0;
}

sub _munge_vcalendar {
    my ($vcalendar_sr) = @_;

    $$vcalendar_sr =~ s/\015?\012[ \011]//g;    # un-wrap long lines
    $$vcalendar_sr =~ s/^METHOD.*\n//m;         # method isn't allowed by CCS

    return;
}

sub logmsg {
    my ($msg) = @_;
    print STDERR "[$0] $msg\n";
    return;
}

1;
