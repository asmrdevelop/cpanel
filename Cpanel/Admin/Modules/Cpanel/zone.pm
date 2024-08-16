package Cpanel::Admin::Modules::Cpanel::zone;

# cpanel - Cpanel/Admin/Modules/Cpanel/zone.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=cut

use cPstrict;

#----------------------------------------------------------------------

use parent qw( Cpanel::Admin::Base );

use Cpanel::Imports;

use Cpanel            ();
use Cpanel::Exception ();

sub _actions {
    return (
        'ASK_LOCAL',
        'RAWFETCH',
        'SWAP_IP_IN_ZONES',
        'MASS_EDIT',
        _actions__pass_exception(),
    );
}

sub _demo_actions {
    return qw(
      FETCH
      RAWFETCHALL
    );
}

#----------------------------------------------------------------------

sub _init {
    my $self = shift;

    Cpanel::initcp( $self->get_caller_username() );

    # REMOTE_USER needs to be set to the reseller for DNS cluster configuration
    $ENV{REMOTE_USER} = $Cpanel::CPDATA{OWNER} || 'root';

    return $self;
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @rrsets = ASK_LOCAL( @QUERIES )

A wrapper around L<Cpanel::DnsUtils::LocalQuery>’s C<ask_batch_sync()>
method.

Instead of returning a list of objects, this returns a list of array
references of array references. The top-level array reference corresponds
to the same-ordered @QUERIES member. Each inner array is: ( $TYPE, $RDATA ).

For example, if you do:

    ASK_LOCAL( [ 'example.com', 'A', 'AAAA' ], [ 'foo.example.com', 'NS' ] )

… the resulting list might be:

    [
        [ 'A', "\x7f\0\0\1" ],
        [ 'A', "\x7f\0\0\2" ],
        [ 'AAAA', $however_ipv6_addresses_are_stored_as_rdata ],
    ],
    [
        [ 'NS', "\7example\3com\0" ],
    ],

See L<Cpanel::DNS::Rdata> for logic to parse $RDATA values.

=cut

sub ASK_LOCAL ( $self, @queries ) {
    require Cpanel::DnsUtils::LocalQuery;
    my $asker = Cpanel::DnsUtils::LocalQuery->new(
        username => $self->get_caller_username(),
    );

    my @rrsets = $asker->ask_batch_sync(@queries);

    for (@rrsets) {
        $_ = [ map { [ $_->type(), $_->rdata() ] } @$_ ];
    }

    return @rrsets;
}

sub RESET {
    my ( $self, $domain, $record_data ) = @_;

    $self->_throw_no_domain_access_if_user_mismatch($domain);
    $self->cpuser_has_feature_or_die('zoneedit');

    require Whostmgr::DNS::Rebuild;
    my %result;
    @result{qw(status statusmsg checkmx)} = (
        Whostmgr::DNS::Rebuild::restore_dns_zone_to_defaults(
            user   => $self->get_caller_username(),
            domain => $domain,
        )
    )[ 0, 1, 3 ];
    return \%result;
}

sub RAWFETCHALL {
    my $self = shift;

    require Cpanel::UserZones;
    Cpanel::initcp( $self->get_caller_username() );
    my $zone_ref = Cpanel::UserZones::get_all_user_zones( $Cpanel::CPDATA{DNS}, @Cpanel::DOMAINS )
      or die Cpanel::Exception->create('Failed to fetch zones.');

    return { status => 1, statusmsg => 'Zones fetched', zones => $zone_ref };
}

=head2 RAWFETCH( $ZONE_NAME )

Returns the text of a user’s zone, in master-file format (cf. RFC 1035).

=cut

sub RAWFETCH ( $self, $domain ) {
    $self->_throw_no_zone_access_if_user_mismatch($domain);

    require Cpanel::DnsUtils::AskDnsAdmin;

    my $text = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "GETZONE", 0, $domain );

    return $text;
}

=head2 $new_serial = MASS_EDIT( %OPTS )

Updates and/or adds multiple records at once.

%OPTS are:

=over

=item * C<zone> - The name of the zone to edit.

=item * C<serial> - The zone’s SOA record’s serial number. Must match the
existing zone, or this operation fails.

=item * C<additions> - Arrayref of arrayrefs: [ dname, ttl, type, @data ]
(The order corresponds to the order of zone files.)

=item * C<edits> - Arrayref of arrayrefs: [ line_index, dname, ttl, type, @data ]
Again, the order corresponds to zone files, with the line index first,
as you may see in a text editor.

=item * C<removals> - Arrayref of line indices (unsigned ints).

=back

This returns the zone’s SOA record’s new serial number.
See L<Cpanel::ZoneFile::LineEdit> for a discussion of why that’s useful.

=cut

sub MASS_EDIT ( $self, %opts ) {
    my @accepted_rr_types = $self->_get_accepted_rr_types_or_die();

    my $zonename = $opts{'zone'} or die Cpanel::Exception::create(
        'AdminError',
        [ message => 'need “zone”' ],
    );

    my $serial = $opts{'serial'} // die Cpanel::Exception::create(
        'AdminError',
        [ message => 'need “serial”' ],
    );

    $self->_throw_no_zone_access_if_user_mismatch($zonename);

    my $adds_ar     = $opts{'additions'} // [];
    my $edits_ar    = $opts{'edits'}     // [];
    my $removals_ar = $opts{'removals'}  // [];

    if ( !@$adds_ar && !@$edits_ar && !@$removals_ar ) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                message => locale()->maketext('You must provide at least one change to the [asis,DNS] zone.'),
            ],
        );
    }

    require Cpanel::ZoneFile::LineEdit;
    my $editor;

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            $editor = Cpanel::ZoneFile::LineEdit->new(
                zone   => $zonename,
                serial => $opts{'serial'},
            );
        },
    );

    for my $addition_ar (@$adds_ar) {
        my $new_type = $addition_ar->[2];

        _authorize_record_type( $new_type, @accepted_rr_types );
    }

    for my $edit_ar (@$edits_ar) {
        my $new_type = $edit_ar->[3];

        _authorize_record_type( $new_type, @accepted_rr_types );
    }

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            $editor->add(@$_) for @$adds_ar;
        },
    );

    $self->_verify_access_to_records_by_line_index(
        $editor,
        \@accepted_rr_types,
        [
            @$removals_ar,
            ( map { $_->[0] } @$edits_ar ),
        ],
    );

    my $ret;

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            $editor->edit(@$_)  for @$edits_ar;
            $editor->remove($_) for @$removals_ar;
            $ret = $editor->save();
        },
    );

    return $ret;
}

sub _authorize_record_type ( $type, @allowed ) {
    if ( !grep { $_ eq $type } @allowed ) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                message => locale()->maketext( 'You cannot create “[_1]” records. You can only create [list_and,_2] records.', $type, \@allowed ),
            ],
        );
    }

    return;
}

sub _verify_access_to_records_by_line_index ( $self, $editor, $accepted_rr_types_ar, $line_idxs_ar ) {    ## no critic qw(ManyArgs) - mis-parse
    for my $lineidx (@$line_idxs_ar) {
        my $old_hr = $editor->get_item_by_line($lineidx);

        # $editor will catch invalid line indexes and
        # line indexes that refer to non-records. We only need
        # to limit record updates to record types that cPanel
        # users can create.
        next if !$old_hr;
        next if $old_hr->{'type'} ne 'record';

        if ( !grep { $_ eq $old_hr->{'record_type'} } @$accepted_rr_types_ar ) {
            die Cpanel::Exception::create(
                'AdminError',
                [
                    message => locale()->maketext( 'Line [numf,_1] contains a record of type “[_2]”. You cannot edit or remove “[_2]” records. You can only edit or remove [list_and,_3] records.', $lineidx, $old_hr->{'record_type'}, $accepted_rr_types_ar ),
                ],
            );
        }
    }

    return;
}

sub _get_accepted_rr_types_or_die ($self) {
    require Cpanel::ZoneEdit::User;
    my @accepted_rr_types = Cpanel::ZoneEdit::User::get_allowed_record_types(
        sub ($feature) { return $self->cpuser_has_feature($feature) },
    );

    if ( !@accepted_rr_types ) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                message => locale()->maketext('You cannot edit [asis,DNS] zones.'),
            ],
        );
    }

    return @accepted_rr_types;
}

sub FETCH {
    my ( $self, $domain, $custom_only ) = @_;

    $self->_throw_no_domain_access_if_user_mismatch($domain);

    require Cpanel::QuickZoneFetch;
    my $zone_fetch_ref = Cpanel::QuickZoneFetch::fetch($domain);

    die Cpanel::Exception->create( 'Failed to fetch zone file for “[_1]”.', [$domain] )
      if exists $zone_fetch_ref->{dnszone}
      and ref $zone_fetch_ref->{dnszone}
      and scalar @{ $zone_fetch_ref->{dnszone} } == 0;

    die Cpanel::Exception->create( 'Failed to serialize zone file. Error was “[_1]”.', [ $zone_fetch_ref->{error} ] )
      if not exists $zone_fetch_ref->{dnszone}
      or not ref $zone_fetch_ref->{dnszone};

    if ($custom_only) {
        _remove_cpanel_generated_records( $domain, $zone_fetch_ref->{dnszone} );
    }
    for ( grep { $_->{type} eq 'TYPE257' } @{ $zone_fetch_ref->{dnszone} } ) {
        $_->{type} = 'CAA';
    }
    return {
        status    => 1,
        statusmsg => 'Zone Serialized',
        serialnum => $zone_fetch_ref->get_serial_number(),
        record    => $zone_fetch_ref->{dnszone},
    };
}

sub SET_UP_FOR_DNS_DCV {
    my ( $self, $zones_ar ) = @_;

    require Cpanel::Context;
    Cpanel::Context::must_be_list();

    $self->_throw_no_domain_access_if_user_mismatch($_) for @$zones_ar;

    #This functionality is limited in scope enough that a user that can’t
    #normally alter a zone file should still be able to call this function.
    $self->cpuser_has_at_least_one_of_features_or_die(qw(sslinstall));

    require Cpanel::SSL::DCV::DNS::Setup;

    return Cpanel::SSL::DCV::DNS::Setup::set_up_for_zones($zones_ar);
}

sub ADD {
    my ( $self, $domain, $record_data ) = @_;

    $self->_throw_no_domain_access_if_user_mismatch($domain);
    $self->cpuser_has_at_least_one_of_features_or_die(qw(zoneedit simplezoneedit));

    my ( $success, $record ) = $self->parse_record( $record_data, $domain );
    die Cpanel::Exception->create('You may only add [asis,A], [asis,AAAA], [asis,CAA], [asis,CNAME], [asis,NS], [asis,SRV] or [asis,TXT] records.')
      if $record->{type} !~ /\A(?:A|AAAA|CAA|CNAME|NS|SRV|TXT)\z/;

    if ( not $success ) {
        $self->_throw_no_simple_zone_admin_access( $domain, $record );
    }

    if (    not $self->cpuser_has_feature('zoneedit')
        and not _record_can_be_accessed_with_simple_editor( $domain, $record ) ) {
        $self->_throw_no_simple_zone_admin_access( $domain, $record );
    }

    require Whostmgr::DNS;
    my %result;
    @result{qw(status statusmsg newserial)} =
      ( Whostmgr::DNS::add_zone_record( $record, $domain ) )[ 0, 1, 2 ];
    return \%result;
}

sub DELETE {
    my ( $self, $domain, $line_number ) = @_;

    $self->_throw_no_domain_access_if_user_mismatch($domain);
    $self->cpuser_has_at_least_one_of_features_or_die(qw(zoneedit simplezoneedit));

    die Cpanel::Exception->create( 'You must specify a valid line when you call [asis,DELETE]: [_1]', [$line_number] )
      if !defined $line_number || $line_number =~ tr{0-9-}{}c;
    my $line = $line_number && abs int $line_number;
    die Cpanel::Exception->create( 'You must specify a valid line when you call [asis,DELETE]: [_1]', [$line] )
      if $line <= 0;

    require Cpanel::QuickZoneFetch;
    my $zone_fetch_ref = Cpanel::QuickZoneFetch::fetch($domain);
    die Cpanel::Exception->create('Could not load the [asis,DNS] zone.')
      if not ref $zone_fetch_ref->{dnszone};

    my $record = $zone_fetch_ref->get_record($line);
    die Cpanel::Exception->create('You may only delete [asis,A], [asis,AAAA], [asis,CAA], [asis,CNAME], [asis,NS], [asis,SRV] or [asis,TXT] records.')
      if $record->{type} !~ /\A(?:A|AAAA|CAA|CNAME|NS|SRV|TYPE257|TXT)\z/;

    if (    not $self->cpuser_has_feature('zoneedit')
        and not _record_can_be_accessed_with_simple_editor( $domain, $record ) ) {
        $self->_throw_no_simple_zone_admin_access( $domain, $record );
    }

    require Whostmgr::DNS;
    my %result;
    @result{qw(status statusmsg newserial)} = (
        Whostmgr::DNS::remove_zone_record(
            {
                domain => $domain,
                Line   => $line,
            },
            $zone_fetch_ref,
        ),
    )[ 0, 1, 2 ];
    return \%result;
}

sub EDIT {
    my ( $self, $domain, $record_data ) = @_;

    $self->_throw_no_domain_access_if_user_mismatch($domain);

    # We are retrofitting this code to allow changes to the MX records
    # so that the 'unified' zone editor can easily accomplish the task
    # of updating records where the 'type' changes.
    $self->cpuser_has_at_least_one_of_features_or_die(
        qw(
          zoneedit
          simplezoneedit
          changemx
        ),
    );

    my ( $success, $new_record ) = $self->parse_record( $record_data, $domain );
    if ( not $success ) {
        $self->_throw_no_simple_zone_admin_access( $domain, $new_record );
    }

    my $line = $new_record->{Line} && abs int $new_record->{Line};
    $line //= $new_record->{line} && abs int $new_record->{line};

    @{$new_record}{qw(Line domain)} = ( $line, $domain );
    require Cpanel::QuickZoneFetch;
    my $zone_fetch_ref = Cpanel::QuickZoneFetch::fetch($domain);

    die Cpanel::Exception->create('You must specify a valid line when you call [asis,EDIT].')
      if $line <= 0;
    die Cpanel::Exception->create('Could not load the [asis,DNS] zone.')
      if not ref $zone_fetch_ref->{dnszone};

    my $old_record = $zone_fetch_ref->get_record($line);
    die Cpanel::Exception->create( 'Failed to fetch record on line: [_1]', [ int $line ] )
      if not $old_record
      or not $old_record->{type};

    $new_record->{type} //= $old_record->{type};

    foreach my $record ( $old_record, $new_record ) {

        # Validate authz for this RR type
        next if $self->_allowed_record_edit( $domain, $record );
        if ( $self->cpuser_has_feature('zoneedit') ) {
            die Cpanel::Exception->create('You may only edit [asis,A], [asis,AAAA], [asis,CAA], [asis,CNAME], [asis,SRV] or [asis,TXT] records.');
        }
        else {
            $self->_throw_no_simple_zone_admin_access( $domain, $record );
        }
    }

    require Whostmgr::DNS;
    my %result;
    @result{qw(status statusmsg newserial)} =
      ( Whostmgr::DNS::edit_zone_record( $new_record, $domain, $zone_fetch_ref ) )[ 0, 1, 2 ];
    return \%result;
}

=head2 $domain_authority_hr = HAS_LOCAL_AUTHORITY( \@DOMAINS )

Determines whether or not local changes to the DNS zones will be authoritative.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

The domains to check.

=back

=item Output

=over 3

=item C<HASHREF>

Same return as C<Cpanel::DnsUtils::Authority::has_local_authority>.

=back

=back

=cut

sub HAS_LOCAL_AUTHORITY {
    my ( $self, $domains ) = @_;
    $self->_throw_no_domain_access_if_user_mismatch($_) for @$domains;
    require Cpanel::DnsUtils::Authority;
    return Cpanel::DnsUtils::Authority::has_local_authority($domains);
}

=head2 $soa_zone_domain_ar = GET_SOA_AND_ZONES_FOR_DOMAINS( \@DOMAINS )

Determines whether or not local changes to the DNS zones will be authoritative.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

The domains to check.

=back

=item Output

=over 3

=item C<ARRAYREF>

Same return as C<Cpanel::DnsUtils::Authority::get_soa_and_zones_for_domains>.

=back

=back

=cut

sub GET_SOA_AND_ZONES_FOR_DOMAINS {
    my ( $self, $domains ) = @_;
    $self->_throw_no_domain_access_if_user_mismatch($_) for @$domains;
    require Cpanel::DnsUtils::Authority;
    return Cpanel::DnsUtils::Authority::get_soa_and_zones_for_domains($domains);
}

sub SWAP_IP_IN_ZONES {
    my ( $self, $source_ip, $dest_ip, $shared_ip, $domains_ar ) = @_;

    _validate_ip($source_ip) if ( $source_ip ne '-1' );    # The API accepts -1 for the source IP
    _validate_ip($dest_ip);
    _validate_ip($shared_ip);

    $self->_throw_no_domain_access_if_user_mismatch($_) for @$domains_ar;

    require Whostmgr::DNS::SwapIP;
    return Whostmgr::DNS::SwapIP::swap_ip_in_zones(
        domainref => $domains_ar,
        sourceip  => $source_ip,
        destip    => $dest_ip,
        ftpip     => $shared_ip,
        zoneref   => {},
    );
}

sub _allowed_record_edit {
    my ( $self, $domain, $record ) = @_;

    return 1 if ( $self->cpuser_has_feature('changemx') and $record->{type} eq 'MX' );

    return 1 if ( $self->cpuser_has_feature('zoneedit') and $record->{type} =~ /\A(?:A|AAAA|CAA|CNAME|SOA|SRV|TYPE257|TXT)\z/ );

    return 1 if ( $self->cpuser_has_feature('simplezoneedit') and _record_can_be_accessed_with_simple_editor( $domain, $record ) );

    return 0;
}

sub _cpanel_generated_domains_ref {
    require Cpanel::DnsUtils::cPanel;
    return Cpanel::DnsUtils::cPanel::get_cpanel_generated_dns_names(shift);
}

sub _validate_ip ($ip) {
    require Cpanel::Validate::IP::v4;
    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,IPv4] address.', [$ip] );
    }
}

sub _throw_no_domain_access_if_user_mismatch {
    my ( $self, $domain ) = @_;

    require Cpanel::AcctUtils::DomainOwner::Tiny;
    if ( $self->get_caller_username() ne Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ) {
        die Cpanel::Exception::create( 'AdminError', [ message => locale()->maketext( 'You do not possess permission to read the zone for “[_1]”.', $domain ) ] );
    }

    return;
}

sub _throw_no_zone_access_if_user_mismatch ( $self, $name ) {

    # This module’s documentation says that it doesn’t necessarily
    # give all of the user’s zones, but it appears to give the same
    # results that Cpanel::DomainLookup gives, which means there’s
    # no reason for a user to get here unless the domain they give
    # is also one that this module knows about.
    require Cpanel::UserZones::User;

    my @zone_names = Cpanel::UserZones::User::list_user_dns_zone_names( $self->get_caller_username() );

    if ( !grep { $_ eq $name } @zone_names ) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                message => locale()->maketext( 'You do not control a [asis,DNS] zone named “[_1]”.', $name ),
            ],
        );
    }

    return;
}

sub _throw_no_simple_zone_admin_access {
    my ( $self, $domain, $record ) = @_;
    require Cpanel::DnsUtils::cPanel;
    die Cpanel::Exception->create('Your hosting provider must enable either the “[asis,Zone Editor (A~, CNAME)]” or “[asis,Zone Editor (AAAA~, CAA~, SRV~, TXT)]” features to perform this action.') if not( $self->cpuser_has_feature('zoneedit') or $self->cpuser_has_feature('simplezoneedit') );
    die Cpanel::Exception->create('Your hosting provider must enable the “[asis,Zone Editor (AAAA~, CAA~, SRV~, TXT)]” feature to add or modify cPanel-generated records. Currently, only the “[asis,Zone Editor (A~, CNAME)]” feature is enabled for your account.')
      if exists Cpanel::DnsUtils::cPanel::get_cpanel_generated_dns_names($domain)->{ $record->{name} };
    die Cpanel::Exception->create('Your hosting provider must enable the “[asis,Zone Editor (AAAA~, CAA~, SRV~, TXT)]” feature to perform this action. Currently, only the “[asis,Zone Editor (A~, CNAME)]” feature is enabled for your account.');
}

sub _remove_cpanel_generated_records {
    my ( $domain, $dnszone_ref ) = @_;
    my $cpanel_generated_domains_ref = _cpanel_generated_domains_ref($domain);
    @{$dnszone_ref} = grep { defined $_->{'name'} and not exists $cpanel_generated_domains_ref->{ $_->{'name'} } } @{$dnszone_ref};

    return;
}

sub _record_can_be_accessed_with_simple_editor {
    my ( $domain, $record ) = @_;

    # Leaving the TXT record in here since it was put in initially years ago
    # when this was zoneadmin.pl.
    return 0 if $record->{type} !~ /\A(?:A|CNAME|TXT)\z/;
    return 0
      if exists _cpanel_generated_domains_ref($domain)->{ $record->{name} };
    return 1;
}

sub parse_record {
    my ( $self, $data, $domain ) = @_;
    my ( $name, $value );
    my %RECORD;
    my $success = 1;
    require Cpanel::Encoder::URI;
    require Cpanel::StringFunc::Trim;
    foreach my $key ( split( /&/, $data ) ) {
        ( $name, $value ) = split( /=/, $key );
        $RECORD{ Cpanel::Encoder::URI::uri_decode_str($name) } = Cpanel::StringFunc::Trim::ws_trim( Cpanel::Encoder::URI::uri_decode_str($value) );
    }

    if ( exists $RECORD{'name'} && $RECORD{'name'} !~ /\./ && $domain ) {
        $RECORD{'name'} .= '.' . $domain . '.';
    }

    if ( not $self->cpuser_has_feature('zoneedit') ) {
        require Cpanel::NameserverCfg;
        my ( $ttl, $nsttl ) = Cpanel::NameserverCfg::fetch_ttl_conf();
        $RECORD{'ttl'}   //= $ttl;
        $RECORD{'class'} //= 'IN';
        $success = 0 if $RECORD{'ttl'} ne $ttl || $RECORD{'class'} ne 'IN';
    }
    return ( $success, \%RECORD );
}

#----------------------------------------------------------------------

# XXX Please don’t add to this list.
sub _actions__pass_exception {
    return qw(
      RAWFETCHALL
      FETCH
      ADD
      SET_UP_FOR_DNS_DCV
      RESET
      DELETE
      EDIT
      HAS_LOCAL_AUTHORITY
      GET_SOA_AND_ZONES_FOR_DOMAINS
    );
}

1;
