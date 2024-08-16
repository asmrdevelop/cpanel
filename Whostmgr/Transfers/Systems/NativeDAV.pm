package Whostmgr::Transfers::Systems::NativeDAV;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.
#
use cPstrict;

use Cpanel::DAV::Defaults ();
use Cpanel::DBI::SQLite   ();
use Cpanel::Exception     ();
use Cpanel::Slurper       ();

use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_prereq { return ['FileProtect']; }

sub get_phase { return 100; }

sub get_summary ($self) {
    return [ $self->_locale()->maketext("This takes the Calendar and Contacts data from CCS or Horde based installs and converts the data for use in cpdavd’s native mode.") ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore ($self) {
    my $extractdir  = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    my $ccsdir_path = "$extractdir/calendar_and_contacts";

    # Everything can (and probably should) be only readable/writable by the system user account
    require Cpanel::Umask;
    my $umask = Cpanel::Umask->new(0077);

    # See if CCS dump data exists in the archive, if so, attempt restore.
    if ( -d $ccsdir_path ) {
        print "Converting data from Apple Calendar and Contacts Server (CCS) to Native CPDAVD format...\n";
        return 0 unless $self->_restore_from_ccs( $extractdir, $ccsdir_path );
    }

    # If no CCS data, check for Horde data and attempt restore.
    if ( -f $self->homedir() . '/.cphorde/horde.sqlite' ) {
        print "Converting data from Horde to Native CPDAVD format...\n";
        return 0 unless $self->_restore_from_horde( $extractdir, $self->homedir() . '/.cphorde/horde.sqlite' );
    }

    # Probably not needed, but going to preserve script assumptions here.
    undef $umask;

    # This is a script, so return the opposite truthyness of it's unixy return.
    print "Updating free/busy data...\n";
    require 'scripts/update_freebusy_data';    ## no critic qw(Modules::RequireBarewordIncludes)
    return !scripts::update_freebusy_data->new( '--user', $self->newuser )->run();
}

sub _restore_from_ccs ( $self, $extractdir, $ccsdir_path ) {
    my $user_homedir = $self->homedir();
    my $user         = $self->newuser();

    my $err;
    try {
        local $SIG{'__WARN__'} = sub {
            $self->warn(@_);
        };

        # Load persistence.json
        require Cpanel::JSON;

        my $persist_hr;
        if ( -f $ccsdir_path . '/persistence.json' ) {
            $persist_hr = Cpanel::JSON::SafeLoadFile( $ccsdir_path . '/persistence.json' );
        }
        else {
            return 0;
        }

        if ( -f $ccsdir_path . '/delegates.json' ) {
            my $delegates_ar = Cpanel::JSON::SafeLoadFile( $ccsdir_path . '/delegates.json' );
            if ( @{$delegates_ar} ) {

                require Cpanel::DAV::Metadata;
                my %proxycfg;
                foreach my $delegate_setting ( @{$delegates_ar} ) {
                    my $delegator = $delegate_setting->{'delegator'};
                    my $delegatee = $delegate_setting->{'delegatee'};

                    print "Restoring delegate relation: Delegator '$delegator' -> '$delegatee'\n";
                    $proxycfg{$delegator}{$delegatee} = $delegate_setting->{'readonly'} == 1 ? 'calendar-proxy-read' : 'calendar-proxy-write';
                }
                my $md_obj              = Cpanel::DAV::Metadata->new( 'homedir' => $user_homedir, 'user' => $user );
                my $reduced_privs_guard = _drop_privs_if_needed($user);
                my $px_file             = $user_homedir . '/.caldav/.proxy_config';
                $md_obj->save( \%proxycfg, $px_file );
            }
        }

        # for each user, make sure they have the default calendar and addressbook via Cpanel::DAV::Defaults
        foreach my $persist_user ( keys %{ $persist_hr->{'users'} } ) {

            # open calendar_and_contacts/calendar/$user_uuid.ics
            my $backup_ccs_dir = $extractdir . '/calendar_and_contacts';

            foreach my $dav_thing (qw{calendars contacts}) {
                opendir( my $ccs_bu_dh, "${backup_ccs_dir}/${dav_thing}" ) or next;
                foreach my $file ( readdir($ccs_bu_dh) ) {
                    next if grep { $_ eq $file } qw{. ..};
                    my ($uuid) = $file =~ m/^([0-9a-zA-Z-]+)_/;
                    next if !$uuid || $persist_hr->{'users'}{$persist_user} ne $uuid;
                    $self->_do_restorepkg_dump_from_css_file(
                        $persist_user,
                        "$user_homedir/.caldav/$persist_user",
                        "${backup_ccs_dir}/${dav_thing}/$file"
                    );
                }
                closedir($ccs_bu_dh);
            }
        }
    }
    catch {
        $err = $_;
    };

    if ($err) {

        # Oddly, returning 0 doesn't result in error print!
        print STDERR Cpanel::Exception::get_string($err) . "\n";
        return ( 0, Cpanel::Exception::get_string($err) );
    }
    return 1;

}

# Adapted from Cpanel::CCS::DBUtils::do_restorepkg_inserts_for_type,
# as that already contained 99% of the logic needed here.
# Just write to file instead of running a PG query for every event.
sub _do_restorepkg_dump_from_css_file ( $self, $persist_user, $dump_dir, $file ) {    ## no critic qw(ManyArgs)

    # Thankfully no nesting exists
    my $inside_event;
    my $evt_uuid = "";
    my %type_map = (
        'ics'   => 'VCALENDAR',
        'vcard' => 'VCARD',
    );
    my %new_ext_map = (
        'ics'   => 'ics',
        'vcard' => 'vcf',
    );
    my %new_dir_map = (
        'ics'   => 'calendar',
        'vcard' => 'addressbook',
    );

    my $full_text = '';
    my $inserts   = 0;
    my $type      = substr( $file, rindex( $file, '.' ) + 1 );

    open( my $fh, "<", $file ) or die "Can't open $file: $!";
    my $guard = _drop_privs_if_needed( $self->newuser() );
    while (<$fh>) {

        # Check if we're starting an event. If not, ignore the line.
        if ( !$inside_event ) {
            $inside_event = ( index( $_, "BEGIN:$type_map{$type}" ) == 0 );
        }
        next if !$inside_event;

        # Append the line to th text blob we're building to insert.
        # Also check if we're actually at the end of this item.
        $full_text .= $_;
        ($evt_uuid) = $_ =~ m/^UID:(.*)\r/ if index( $_, "UID:" ) == 0;
        if ($inside_event) {
            $inside_event = 0 if index( $_, "END:$type_map{$type}" ) == 0;

            # if so, run the insert.
            if ( !$inside_event ) {

                # Dir should already exist due to defaults creation call
                if ( !-d "${dump_dir}/$new_dir_map{$type}" ) {
                    Cpanel::DAV::Defaults::create_calendar($persist_user)    if $type eq 'ics';
                    Cpanel::DAV::Defaults::create_addressbook($persist_user) if $type eq 'vcard';
                }
                my $file2write = "${dump_dir}/$new_dir_map{$type}/${evt_uuid}.$new_ext_map{$type}";
                Cpanel::Slurper::write( $file2write => $full_text );

                $inserts++;

                # Reset $full_text so that we can process the next entry
                $full_text = '';
            }
        }
    }
    undef $guard;
    close $fh;

    print "Added $inserts record(s) to $new_dir_map{$type} for $persist_user\n";
    return;
}

sub _restore_from_horde ( $self, $extractdir, $hordedb_path ) {
    my $user_homedir = $self->homedir();
    my $newuser      = $self->newuser();
    my $colldir      = "$user_homedir/.caldav";

    require Clone;
    require Cpanel::StringFunc::Trim;
    require DateTime;
    require MIME::Base64;
    require PHP::Serialization;
    require Text::VCardFast;

    # Manually take events/contacts from horde db and dump each one into a
    # .ics/.vcf file in relevant dir
    my $dbh = Cpanel::DBI::SQLite->connect(
        {
            'database' => $hordedb_path,
        }
    );
    my $guard        = _drop_privs_if_needed($newuser);
    my %coll_to_user = map { $_->{'share_name'} => $_->{'share_owner'} } (
        @{ $dbh->selectall_arrayref( 'SELECT * from turba_shares',     { 'Slice' => {} } ) },
        @{ $dbh->selectall_arrayref( 'SELECT * from kronolith_shares', { 'Slice' => {} } ) }
    );
    foreach my $type (qw{addressbook calendar}) {
        if ( $type eq 'addressbook' ) {
            my $query    = 'SELECT * FROM turba_objects';
            my $contacts = $dbh->selectall_arrayref( $query, { 'Slice' => {} } );
            foreach my $contact (@$contacts) {
                my $coll_user = $coll_to_user{ $contact->{'owner_id'} } || $newuser;
                my $dumpdir   = "$colldir/$coll_user/addressbook";
                $self->_do_dump_for_horde_contact( $coll_user, $dumpdir, $contact );
            }
        }
        else {
            my $query  = 'SELECT * FROM kronolith_events';
            my $events = $dbh->selectall_arrayref( $query, { 'Slice' => {} } );
            foreach my $event (@$events) {
                my $coll_user = $coll_to_user{ $event->{'calendar_id'} } || $newuser;
                my $dumpdir   = "$colldir/$coll_user/calendar";
                $self->_do_dump_for_horde_event( $coll_user, $dumpdir, $event );
            }
        }
    }

    return 1;
}

sub recur_days_calc ($hordedays) {
    my @icaldays;
    do {
        if ( $hordedays - 64 >= 0 ) { unshift @icaldays, ('SA'); $hordedays -= 64 }
        if ( $hordedays - 32 >= 0 ) { unshift @icaldays, ('FR'); $hordedays -= 32 }
        if ( $hordedays - 16 >= 0 ) { unshift @icaldays, ('TH'); $hordedays -= 16 }
        if ( $hordedays - 8 >= 0 )  { unshift @icaldays, ('WE'); $hordedays -= 8 }
        if ( $hordedays - 4 >= 0 )  { unshift @icaldays, ('TU'); $hordedays -= 4 }
        if ( $hordedays - 2 >= 0 )  { unshift @icaldays, ('MO'); $hordedays -= 2 }
        if ( $hordedays - 1 >= 0 )  { unshift @icaldays, ('SU'); $hordedays -= 1 }
    } while $hordedays > 0;
    return join ',', @icaldays;
}

sub _trim ($text) {
    return "" if !defined $text;
    $text =~ s/\s{2,}//mg;
    return $text;
}

sub _do_dump_for_horde_event ( $self, $principal, $dumpdir, $event ) {
    my %skipped = map { $_ => 1 } qw{
      alarm alarm_methods allday ar_id id start end baseid timezone
      recurcount recurdays recurenddate recurinterval recurtype resources
      exceptions
    };

    # kronolith/lib/Kronolith.php has the constants that this map duplicates in
    # order to know what DB value corresponds to what status for certain fields.
    my %event_status_map = (
        0 => 'NEEDS-ACTION',
        1 => 'TENTATIVE',
        2 => 'CONFIRMED',
        3 => 'CANCELLED',
        4 => 'FREE',
    );
    my %response_status_map = (
        1 => 'NEEDS-ACTION',
        2 => 'ACCEPTED',
        3 => 'DECLINED',
        4 => 'TENTATIVE',
    );

    # Horde/Date/Recurrence.php contains the related constants here.
    my %recur_type_map = (
        0 => 'NONE',
        1 => 'DAILY',
        2 => 'WEEKLY',
        3 => 'MONTHLY',    # _DATE
        4 => 'MONTHLY',    # _WEEKDAY
        5 => 'YEARLY',     # _DATE
        6 => 'YEARLY',     # _DAY
        7 => 'YEARLY',     # _WEEKDAY
        8 => 'MONTHLY',    # _LAST_WEEKDAY
    );

    my %remapped = (
        'status'   => sub { return [ { 'name' => 'status',  'value' => $event_status_map{ $_[0] } } ] },
        'title'    => sub { return [ { 'name' => 'summary', 'value' => $_[0] } ] },
        'private'  => sub { return [ { 'name' => 'class',   'value' => ( $_[0] ? 'private' : 'public' ) } ] },
        'modified' => sub {
            my $d      = DateTime->from_epoch( 'epoch' => $_[0] );
            my $format = "yyyymmdd'T'hhmmss'Z'";
            return [ { 'name' => 'last-modified', 'value' => $d->format_cldr($format) } ];
        },
        'attendees' => sub {
            return if !$_[0];
            my $breakfast = PHP::Serialization::unserialize( $_[0] );
            my $cnt       = 0;
            if ( ref($breakfast) eq 'ARRAY' ) {
                $cnt = @{$breakfast};
            }
            else {
                $cnt = scalar keys %{$breakfast};
            }
            if ( $cnt < 1 ) {
                return [ { 'name' => 'attendee', 'value' => 'none', 'params' => { 'role' => ['REQ-PARTICIPANT'], 'partstat' => [''], 'rsvp' => [''] } } ];
            }
            return [
                map {
                    my $key = $_;
                    {
                        'name'   => 'attendee',
                        'value'  => "mailto:$key",
                        'params' => {
                            'role'     => ['REQ-PARTICIPANT'],                                          # Horde has no conception of non-participants
                            'partstat' => [ $response_status_map{ $breakfast->{$key}{'response'} } ],
                            'rsvp'     => [ $breakfast->{$key}{'attendance'} ? 'true' : 'false' ],
                        },
                    }
                } keys(%$breakfast)
            ];
        },
        'creator_id' => sub {
            return [ { 'name' => 'organizer', 'value' => "mailto:$_[0]", 'params' => { 'cn' => $_[0] } } ];
        },
    );

    # I'm only doing package level scoping here for ease of testing.
    our %extra_items = (
        'transp'  => sub { return [ { 'name' => 'transp', 'value' => 'OPAQUE' } ] },
        'created' => sub {
            my $uid  = $_[0]->{'event_uid'};
            my $date = substr( $uid, 0, 14 );

            # Reject invalid dates... Only horde's events have this reliably set.
            # We can do a "naive" numeric check here because it isnt' decimal math.
            if ( length $date < 8 || $date !~ m/^\d+$/ ) {
                $date = '00000000T000000Z';
            }
            else {
                $date = substr( $date, 0, 8 ) . 'T' . substr( $date, 8 ) . 'Z';
            }
            return [ { 'name' => 'created', 'value' => $date } ];
        },    # Creation date is first part of event UID
        'dtstart' => sub {
            my ($data) = @_;
            my $val = $data->{'event_start'};
            $val =~ s/[-:]*//g;
            my $params = {};
            if ( $data->{'event_allday'} ) {
                $params->{'value'} = 'DATE';
                $val = substr( $val, 0, index( $val, " " ) );
            }
            else {
                $val =~ tr/ /T/;
            }
            return [ { 'name' => 'dtstart', 'value' => $val, 'params' => $params } ];
        },
        'dtend' => sub {
            my ($data) = @_;
            my $val = $data->{'event_end'};
            $val =~ s/[-:]*//g;
            my $params = {};
            if ( $data->{'event_allday'} ) {
                $params->{'value'} = 'DATE';
                $val = substr( $val, 0, index( $val, " " ) );
            }
            else {
                $val =~ tr/ /T/;
            }
            return [ { 'name' => 'dtend', 'value' => $val, 'params' => $params } ];
        },

        # No idea where it is getting dtstamp
        #'dtstamp' => sub { return [{ 'name' => 'dtstamp', 'value' => '' }] },
        'rrule' => sub {    # https://datatracker.ietf.org/doc/html/rfc2445#section-4.3.10
            my ($evt) = @_;
            return [] if !$evt->{'event_recurtype'};
            $evt->{'event_recurinterval'} //= 0;
            $evt->{'event_recurdays'}     //= 0;
            $evt->{'event_recurcount'}    //= 0;
            $evt->{'event_recurenddate'}  //= '99991231';
            my $rrval = 'freq=' . $recur_type_map{ $evt->{'event_recurtype'} } . ";";                                                                                    # FREQ is required
            $rrval .= 'interval=' . $evt->{'event_recurinterval'} . ";"             if $evt->{'event_recurinterval'} != 0;                                               # INTERVAL is optional
            $rrval .= 'byday=' . recur_days_calc( $evt->{'event_recurdays'} ) . ";" if $evt->{'event_recurdays'} != 0;                                                   # BYxxx rules are optional
            $rrval .= 'count=' . $evt->{'event_recurcount'} . ";"                   if $evt->{'event_recurcount'} != 0;                                                  # COUNT is optional
            $rrval .= 'until=' . $evt->{'event_recurenddate'} . ";"                 if $evt->{'event_recurcount'} == 0 && $evt->{'event_recurenddate'} ne '99991231';    # UNTIL is mutually exclusive with COUNT
            return [ { 'name' => 'rrule', 'value' => uc($rrval) } ];
        },

        # The two below have to be part of their own vcard. Datastructure
        # looks a bit strange as such ;_;
        #'valarm'  => sub { return [{ 'name' => 'valarm', 'value' => '' }] },
        #'vtimezone' => sub { return [{ 'name' => 'vtimezone', 'value' => '' }] },
    );
    my $evt_hr = {
        'objects' => [
            {
                'type'       => 'vevent',
                'properties' => {},
            }
        ],
    };
    foreach my $prop ( keys(%$event) ) {
        my $prop_short = substr( $prop, 6 );    # event_
        next if !defined $event->{$prop} || $skipped{$prop_short};
        if ( $remapped{$prop_short} ) {
            $evt_hr->{'objects'}[0]{'properties'}{$prop_short} = $remapped{$prop_short}->( $event->{$prop} );
        }
        else {
            # CPANEL-42420: It is HIGHly likely that the
            # description field has newlines/blank lines.
            # These unfortunately do not pass any known
            # parser's evaluation based on the spec, so
            # trim it.
            $evt_hr->{'objects'}[0]{'properties'}{$prop_short} = [
                {
                    'name'  => $prop_short,
                    'value' => _trim( $event->{$prop} ),
                },
            ];
        }
    }
    foreach my $item ( keys(%extra_items) ) {
        $evt_hr->{'objects'}[0]{'properties'}{$item} = $extra_items{$item}->($event);
    }

    # Reject events with nonsense values for DTSTART/DTEND (CPANEL-42509)
    next if grep { $evt_hr->{'objects'}[0]{'properties'}{$_} eq '00000000T000000' } qw{dtstart dtend};

    my $vevent = Text::VCardFast::hash2vcard($evt_hr);
    if ( $event->{'event_alarm'} ) {
        my $valarm = "BEGIN:VALARM\nACTION:DISPLAY\nDESCRIPTION:$event->{'event_title'}\nTRIGGER;VALUE=DURATION:-PT$event->{'event_alarm'}M\nEND:VALARM\n";
        $vevent =~ s/END:VEVENT/${valarm}END:VEVENT/;
    }

    my $ics_blob = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//cPanel Horde Calendar Exporter//export_horde_calendars_to_ics//EN\nX-WR-CALNAME:calendar\n${vevent}END:VCALENDAR\n";

    if ( !-d $dumpdir ) {
        Cpanel::DAV::Defaults::create_calendar($principal);
    }

    my $outfile = "${dumpdir}/$event->{'event_id'}.ics";

    Cpanel::Slurper::write( $outfile => $ics_blob );

    return;
}

sub _do_dump_for_horde_contact ( $self, $principal, $dumpdir, $contact ) {
    my %db2vcf_map = (
        'imaddress'   => { key    => 'x-wv-id' },
        'spouse'      => { key    => 'x-spouse' },
        'alias'       => { key    => 'nickname' },
        'anniversary' => { key    => 'x-anniversary' },
        'tz'          => { params => { 'value' => ['text'] } },
        'cellphone'   => { key    => 'tel', params => { type => [qw{CELL VOICE}] } },
        'homephone'   => { key    => 'tel', params => { type => [qw{HOME VOICE}] } },
        'workphone'   => { key    => 'tel', params => { type => [qw{WORK VOICE}] } },
        'fax'         => { key    => 'tel', params => { type => ['FAX'] } },
        'homefax'     => { key    => 'tel', params => { type => [qw{HOME FAX}] } },
        'pager'       => { key    => 'tel', params => { type => ['PAGER'] } },
        'notes'       => { key    => 'note' },
        'email'       => { params => { type => ['INTERNET'] } },
    );

    my @ignore_fields =
      qw{photo phototype logo logotype company department homestreet workstreet otherstreet homecity workcity othercity homeprovince workprovince otherprovince homepostalcode workpostalcode otherpostalcode homecountry workcountry othercountry radiophone smimepublickey workpob homepob otherpob yomifirstname yomilastname pgppublickey workphone2 firstname middlenames lastname nameprefix namesuffix manager imaddress2 imaddress3 homephone2 freebusyurl companyphone carphone assistant assistantphone id type};

    # Some fields in vcf are synthesized from many DB fields.
    my %extra_items = (
        'n'     => [ { 'name' => 'n',     'value' => [qw{lastname firstname middlenames nameprefix namesuffix}], 'format' => '?;?;?;?;?' } ],
        'fn'    => [ { 'name' => 'fn',    'value' => [qw{nameprefix firstname middlenames lastname namesuffix}], 'format' => '? ? ? ? ?' } ],
        'org'   => [ { 'name' => 'org',   'value' => [qw{company department}],                                   'format' => '?;?' } ],
        'photo' => [ { 'name' => 'photo', 'value' => 'photo',                                                    'params' => { 'encoding' => ['b'], 'type' => 'phototype' } } ],
        'logo'  => [ { 'name' => 'logo',  'value' => 'logo',                                                     'params' => { 'encoding' => ['b'], 'type' => 'logotype' } } ],
        'label' => [
            {
                'name'   => 'label',
                'value'  => [qw{homestreet homecity homeprovince homepostalcode}],
                'format' => '?=0A?, ? ?',                                            # Let's hope this works in other locales, haha
                'params' => {
                    'type'     => ['HOME'],
                    'encoding' => ['QUOTED-PRINTABLE'],
                    'charset'  => ['UTF-8'],
                },
            },
            {
                'name'   => 'label',
                'value'  => [qw{workstreet workcity workprovince workpostalcode}],
                'format' => '?=0A?, ? ?',
                'params' => {
                    'type'     => ['WORK'],
                    'encoding' => ['QUOTED-PRINTABLE'],
                    'charset'  => ['UTF-8'],
                },
            },
            {
                'name'   => 'label',
                'value'  => [qw{otherstreet othercity otherprovince otherpostalcode}],
                'format' => '?=0A?, ? ?',
                'params' => {
                    'encoding' => ['QUOTED-PRINTABLE'],
                    'charset'  => ['UTF-8'],
                },
            },
        ],
        'adr' => [
            {
                'name'   => 'adr',
                'value'  => [qw{homepob homestreet homecity homeprovince homepostalcode homecountry}],
                'format' => '?;;?;?;?;?;?',
                'params' => {
                    'type' => ['HOME'],
                },
            },
            {
                'name'   => 'adr',
                'value'  => [qw{workpob workstreet workcity workprovince workpostalcode workcountry}],
                'format' => '?;;?;?;?;?;?',
                'params' => {
                    'type' => ['WORK'],
                },
            },

        ],
    );
    my $obj_hr = {
        'type'       => 'vcard',
        'properties' => {
            'version' => [ { 'name' => 'version', 'value' => '2.1' } ],
        }
    };

    # I would have used map here, but the values for the keys
    # are all ARRAY, so you can push multiple onto the stack
    # of values for any given key. Thus key => value overwrites.
    my @params_filtered = grep {
        my $param       = $_;
        my $param_short = substr( $param, 7 );
        $contact->{$param} && index( $param, 'owner_' ) != 0 && !grep { $_ eq $param_short } @ignore_fields
    } sort keys( %{$contact} );
    foreach my $param (@params_filtered) {

        # object_ length = 7
        my $param_truncated = substr( $param, 7 );
        my $name            = $param_truncated;
        if ( ref $db2vcf_map{$param_truncated} eq 'HASH' && $db2vcf_map{$param_truncated}->{key} ) {
            $name = $db2vcf_map{$param_truncated}->{key};
        }
        my $struct = {
            value => $contact->{$param},
            name  => $name,
        };
        $struct->{'params'} = $db2vcf_map{$param_truncated}->{'params'} if $db2vcf_map{$param_truncated}->{'params'};
        if ( $obj_hr->{'properties'}{$name} ) {
            push @{ $obj_hr->{'properties'}{$name} }, $struct;
        }
        else {
            $obj_hr->{'properties'}{$name} = [$struct];
        }
    }

    foreach my $item ( keys(%extra_items) ) {
        my $arr = Clone::clone( $extra_items{$item} );
        for ( my $i = 0; $i <= scalar(@$arr) - 1; $i++ ) {

            if ( ref $arr->[$i]{'value'} eq 'ARRAY' ) {
                my $format = delete $arr->[$i]{'format'};
                foreach my $value ( @{ $arr->[$i]{'value'} } ) {
                    my $actual = $contact->{ 'object_' . $value } || '';
                    my $sep    = $actual ? '' : ';?';
                    $format =~ s/\?$sep/$actual/;
                }

                if ( $format && !grep { Cpanel::StringFunc::Trim::ws_trim($format) eq $_ } ( ';', '=0A,' ) ) {
                    $arr->[$i]{'value'} = $format;
                }
                else {
                    delete $arr->[$i]{'value'};
                }
            }
            else {
                if ( $contact->{ 'object_' . $arr->[$i]{'value'} } ) {
                    $arr->[$i]{'value'} = $contact->{ 'object_' . $arr->[$i]{'value'} };
                }
                else {
                    delete $arr->[$i]{'value'};
                }
            }
            if ( ref $arr->[$i]{'params'} eq 'HASH' && $arr->[$i]{'params'}{'type'} && !ref $arr->[$i]{'params'}{'type'} ) {
                my $type       = delete $arr->[$i]{'params'}{'type'};
                my $actualtype = $contact->{"object_$type"};
                $arr->[$i]{'params'}{'type'} = [$actualtype] if $actualtype;
                if ( $actualtype && $actualtype =~ m/^image/ ) {
                    $arr->[$i]{'value'} = MIME::Base64::encode_base64( $arr->[$i]{'value'}, '' );
                }
            }
        }

        # Yea yea, I'm double looping. That said, running splice
        # on the array you iterate through above to get rid of
        # elements which ultimately don't have any value to
        # ain't the best idea either, so I ain't got any good
        # ideas to avoid this.
        @$arr = grep { $_->{'value'} } @$arr;
        $obj_hr->{'properties'}{$item} = $arr if scalar @$arr;
    }

    if ( !-d $dumpdir ) {
        Cpanel::DAV::Defaults::create_addressbook($principal);
    }

    my $vcf_blob = Text::VCardFast::hash2vcard( { 'objects' => [$obj_hr] } );
    my $outfile  = "${dumpdir}/$contact->{'object_id'}.vcf";

    Cpanel::Slurper::write( $outfile => $vcf_blob );

    return;
}

sub _drop_privs_if_needed ($user) {
    if ( $> == 0 && $user ne 'root' ) {
        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new($user);
    }
    return;
}

# Avoid "no warnings qw{once};" being needed here by *not aliasing*
sub restricted_restore {
    return unrestricted_restore(@_);
}

1;
