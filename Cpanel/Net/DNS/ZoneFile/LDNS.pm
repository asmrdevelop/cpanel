package Cpanel::Net::DNS::ZoneFile::LDNS;

# cpanel - Cpanel/Net/DNS/ZoneFile/LDNS.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Carp                                 ();
use Ref::Util                            ();
use Cpanel::AccessIds::LoadFile          ();
use Cpanel::AcctUtils::DomainOwner::BAMP ();
use Cpanel::LoadFile                     ();
use Cpanel::ZoneFile::Parse              ();
use Cpanel::DnsUtils::CAA                ();
use Cpanel::DnsUtils::GenericRdata       ();

use constant {
    'KEYS_TO_CASE' => qw<
      name cname dname exchange mname rname
      nsdname ptrdname target mbox txtdname
    >,

    # Parsing stolen from Net::DNS::RR::LOC
    'LOC_RE' => qr!
        ^
        (\d+) \s+           # deg lat
        ((\d+) \s+)?        # min lat
        (([\d.]+) \s+)?      # sec lat
        ([NS]) \s+           # hem lat
        (\d+) \s+            # deg lon
        ((\d+) \s+)?        # min lon
        (([\d.]+) \s+)?      # sec lon
        ([EW]) \s+           # hem lon
        (-?[\d.]+) m?        # altitude
        (\s+ ([\d.]+) m?)?   # size
        (\s+ ([\d.]+) m?)?   # horiz precision
        (\s+ ([\d.]+) m?)?   # vert precision
        $
    !xmas,
};

################################################
# lifted from Cpanel::CPAN::Net::DNS::ZoneFile #
################################################
# Reference lat/lon (see RFC 1876).
use constant {
    'REFERENCE_LATLON' => 2**31,

    # Conversions to/from thousandths of a degree.
    'CONV_SEC' => 1000,
};

# Conversions to/from thousandths of a degree.
use constant 'CONV_MIN' => 60 * CONV_SEC();
use constant 'CONV_DEG' => 60 * CONV_MIN();

my %DIRECT_CONVERT = (
    'A' => ['address'],

    # Not supported
    #'A6' => [qw< prefix address refer >],

    'AAAA' => ['address'],

    # Not supported
    #'ALIAS' => ['alias'],

    'DHCID' => ['digest'],

    'DLV' => [
        qw<
          name DLV keytag algorithm digtype digest
        >
    ],

    'DNSKEY' => [
        qw<
          flags protocol algorithm publickey
        >
    ],

    'DS'         => [qw< keytag algorithm digtype digest >],
    'EUI48'      => ['address'],
    'EUI64'      => ['address'],
    'HINFO'      => [qw< cpu os >],
    'MB'         => ['madname'],
    'MG'         => ['mgmname'],
    'MINFO'      => [qw< rmailbx emailbx >],
    'MR'         => ['newname'],
    'OPENPGPKEY' => ['key'],
    'RKEY'       => [qw< flags protocol algorithm key >],

    'RRSIG' => [
        qw<
          typecovered algorithm labels
          orgttl sigexpiration siginception
          keytag signame signature
        >
    ],

    'SMIMEA' => [qw< usage selector matchingtype cert >],
    'TLSA'   => [qw< usage selector matchingtype cert >],
    'URI'    => [qw< priority weight target >],
    'WKS'    => [qw< address protocol bitmap >],
);

my %CALLBACK_CONVERT = (
    'AFSDB' => sub ( $ref, $subtype, $hostname ) {
        $ref->{'subtype'}  = $subtype;
        $ref->{'hostname'} = $hostname =~ s/\.$//xmsr;
    },

    'APL' => sub ( $ref, $init_item, @more_items ) {
        $ref->{'apitems'} = [ map { s/\s+$//xmsr } $init_item, @more_items ];
    },

    'CAA' => sub ( $ref, $flag, $tag, $value ) {
        $ref->@{qw< flag tag value >} = ( $flag, $tag, $value );
        my $rdata  = Cpanel::DnsUtils::CAA::encode_rdata( $flag, $tag, $value );
        my $legacy = Cpanel::DnsUtils::GenericRdata::encode($rdata);
        $ref->{'value_legacy'} = $legacy;
    },

    'CDS' => sub ( $ref, $flags, $proto, $algo, $key ) {
        $ref->@{
            qw<
              flags protocol algorithm key
            >
        } = map { int } $flags, $proto, $algo, $key;
    },

    'CDNSKEY' => sub ( $ref, $flags, $proto, $algo, $key ) {
        $ref->@{
            qw<
              flags protocol algorithm key
            >
        } = map { int } $flags, $proto, $algo, $key;
    },

    'CNAME' => sub ( $ref, $cname ) {
        $ref->{'cname'} = $cname =~ s/\.$//xmsr;
    },

    'CSYNC' => sub ( $ref, $serial, $flags, $typelist ) {
        $ref->@{qw< serial flags typelist >} = ( $serial, $flags, $typelist );
        $ref->{'typelist'} =~ s/\s+$//xms;
    },

    'DNAME' => sub ( $ref, $dname ) {
        $ref->{'dname'} = $dname =~ s/\.$//xmsr;
    },

    'IPSECKEY' => sub ( $ref, $ipsecstr ) {
        $ref->@{
            qw<
              precedence gatetype algorithm gateway key
            >
        } = split /\s+/xms, $ipsecstr;
    },

    'KX' => sub ( $ref, $pref, $exchange ) {
        $ref->{'preference'} = $pref;
        $ref->{'exchange'}   = $exchange =~ s{\.$}{}xmsr;
    },

    'LOC' => sub ( $ref, $loc_str ) {
        _parse_loc( $loc_str, $ref );
    },

    'MX' => sub ( $ref, $pref, $exchange ) {
        $ref->{'preference'} = $pref;
        $ref->{'exchange'}   = $exchange =~ s/\.$//xmsr;
    },

    'NAPTR' => sub ( $ref, $order, $pref, $flags, $svc, $regexp, $replace ) {
        $ref->@{
            qw<
              order preference flags service regexp replacement
            >
        } = ( $order, $pref, $flags, $svc, $regexp, $replace );

        $ref->{'replacement'} =~ s/\.$//xms;
    },

    'NS' => sub ( $ref, $nsdname ) {
        $ref->{'nsdname'} = $nsdname =~ s/\.$//xmsr;
    },

    'NSEC' => sub ( $ref, $nxtdname, $typelist ) {
        $ref->@{qw< nxtdname typelist >} = map { s/\s+$//xmsr } $nxtdname, $typelist;
    },

    'NSEC3' => sub ( $ref, $algo, $flags, $iter, $salt, $hnxtname, $rrset = '' ) {

        # $rrset is optional, we don't provide it anyway
        $ref->@{
            qw<
              algorithm flags iterations salt hnxtname
            >
        } = map { s/\s+$//xmsr } $algo, $flags, $iter, $salt, $hnxtname;
    },

    'NSEC3PARAM' => sub ( $ref, $algo, $flags, $iter, $salt ) {
        $ref->@{
            qw<
              algorithm flags iterations salt
            >
        } = map { s/\s+$//xmsr } $algo, $flags, $iter, $salt;
    },

    'PTR' => sub ( $ref, $ptrdname ) {
        $ref->{'ptrdname'} = $ptrdname =~ s/\.$//xmsr;
    },

    'RP' => sub ( $ref, $mbox, $txtdname ) {
        $ref->@{qw< mbox txtdname >} = map { s/\.$//xmsr } $mbox, $txtdname;
    },

    'SOA' => sub ( $ref, $mname, $rname, $serial, $refresh, $retry, $expire, $minimum ) {
        $ref->@{qw< mname rname serial refresh retry expire minimum >} = ( $mname, $rname, $serial, $refresh, $retry, $expire, $minimum );

        $ref->{$_} =~ s/\.$//xms for qw< mname rname >;
    },

    'SPF' => sub ( $ref, $txtdname ) {
        $ref->{'txtdata'} = $txtdname =~ s/\.$//xmsr;
    },

    'SRV' => sub ( $ref, $prio, $weight, $port, $target ) {
        $ref->@{qw< priority weight port target >} = ( $prio, $weight, $port, $target );
        $ref->{'target'} =~ s/\.$//xms;
    },

    'SSHFP' => sub ( $ref, $algo, $fptype, $fp ) {
        $ref->@{qw< algorithm fptype fingerprint >} = ( $algo, $fptype, $fp );
        $ref->{'fingerprint'} = uc $ref->{'fingerprint'};
    },

    'TXT' => sub ( $ref, $init_str, @more_strs ) {
        $ref->{'txtdata'}       = join '', $init_str, @more_strs;
        $ref->{'type'}          = 'TXT';
        $ref->{'char_str_list'} = [ $init_str, @more_strs ];
    },
);

sub _dms2latlon ( $deg, $min, $sec, $hem ) {
    my ($retval);

    $retval = ( $deg * CONV_DEG() ) + ( $min * CONV_MIN() ) + ( $sec * CONV_SEC() );
    $retval = -$retval if ( $hem eq "S" ) || ( $hem eq "W" );
    $retval += REFERENCE_LATLON();
    return $retval;
}

sub _replace_include_recursively ( $stringref, $domain_owner ) {
    foreach my $line ( split /\n/xms, $stringref->$* ) {
        if ( $line =~ /^ \$INCLUDE \s+ (.+) $/xmsi ) {
            my $filename = $1;

            # the filename might be quoted
            # and might end with semicolon
            $filename =~ s{^['"]}{}xmsg;
            $filename =~ s{['"];?}{}xmsg;

            # If this is invoked inside of an AdminBin call
            # we will need to drop privileges to avoid arbitrary file
            # reads by a non-root user.
            my $content;
            if ($domain_owner) {
                $content = Cpanel::AccessIds::LoadFile::loadfile_as_user( $domain_owner, $filename );
            }
            elsif ( exists $ENV{'USER'} && $ENV{'USER'} ne 'root' ) {
                $content = Cpanel::AccessIds::LoadFile::loadfile_as_user( $ENV{'USER'}, $filename );
            }
            else {
                $content = Cpanel::LoadFile::loadfile($filename);
            }
            _replace_include_recursively( \$content, $domain_owner );
            $stringref->$* =~ s{^\Q$line\E$}{$content}xms;
        }
        elsif ( $line =~ /^ \$GENERATE \s+ ([0-9])\-([0-9]) \s+ (.+) $/xmsi ) {
            my $from     = $1;
            my $until    = $2;
            my $template = $3;
            my @generated;

            for my $num ( $from .. $until ) {
                my $str = $template =~ s{\$}{$num}xmsgr;
                push @generated, $str;
            }

            my $generated = join "\n", @generated;
            $stringref->$* =~ s{^\Q$line\E$}{$generated}xms;
        }
    }

    # not used
    return;
}

sub _fix_lowercase_directives ($stringref) {
    $stringref->$* =~ s{^\$ORIGIN}{\$ORIGIN}xmsgi;
    $stringref->$* =~ s{^\$TTL}{\$TTL}xmsgi;

    # not used
    return;
}

sub _parse_loc ( $rdata_txt, $rr_hashref ) {

    # Stolen from Cpanel::CPAN::Cpanel::Net::DNS::ZoneFile::Fast
    $rdata_txt =~ LOC_RE();

    my ( $latdeg, $latmin, $latsec,    $lathem )   = ( $1,  $3,  $5,  $6 );
    my ( $londeg, $lonmin, $lonsec,    $lonhem )   = ( $7,  $9,  $11, $12 );
    my ( $alt,    $size,   $horiz_pre, $vert_pre ) = ( $13, $15, $17, $19 );

    # Defaults from RFC 1876
    my $default_min       = 0;
    my $default_sec       = 0;
    my $default_size      = 1;
    my $default_horiz_pre = 10_000;
    my $default_vert_pre  = 10;

    # Reference altitude in centimeters (see RFC 1876).
    my $reference_alt = 100_000 * 100;

    my $version = 0;

    $latmin ||= $default_min;
    $latsec ||= $default_sec;
    $lathem = uc($lathem);

    $lonmin ||= $default_min;
    $lonsec ||= $default_sec;
    $lonhem = uc($lonhem);

    $size      ||= $default_size;
    $horiz_pre ||= $default_horiz_pre;
    $vert_pre  ||= $default_vert_pre;

    $rr_hashref->@{
        qw<
          version size horiz_pre vert_pre
          size_mts horiz_pre_mts vert_pre_mts
          latitude longitude
          latitude_dms longitude_dms
          altitude altitude_mts
        >
      }
      = (
        $version, $size * 100, $horiz_pre * 100, $vert_pre * 100,
        $size,    $horiz_pre,  $vert_pre,
        _dms2latlon( $latdeg, $latmin, $latsec, $lathem ),
        _dms2latlon( $londeg, $lonmin, $lonsec, $lonhem ),
        "$latdeg $latmin $latsec $lathem",
        "$londeg $lonmin $lonsec $lonhem",
        $alt * 100 + $reference_alt, $alt,
      );

    # return value ignored
    return;
}

sub parse {
    my @def_args = @_;

    # Handle the way Cpanel::Net::DNS::ZoneFile::Fast is called
    @def_args or Carp::croak('Cpanel::Net::DNS::ZoneFile::LDNS::parse() required parameters');

    my %args =
      @def_args == 1
      ? ( 'text' => $def_args[0] )
      : @def_args;

    if ( $args{'soft_errors'} ) {
        Carp::croak("'soft_errors' is not supported");
    }

    if ( defined $args{'file'} ) {
        return parse_file( $args{'file'}, \%args );
    }

    if ( defined $args{'fh'} ) {
        return parse_fh( $args{'fh'}, \%args );
    }

    if ( defined $args{'text'} ) {
        return parse_string( $args{'text'}, \%args );
    }

    Carp::croak('Cpanel::Net::DNS::ZoneFile::LDNS::parse() must have "text" or "file"');
}

# Cpanel/ZoneFile/Parse.pm only does strings, not files
# So we read the file
sub parse_file ( $filename, $args ) {
    my $zone_string = Cpanel::LoadFile::loadfile($filename);
    return parse_string( $zone_string, $args );
}

sub parse_fh ( $fh, $args ) {
    my $zone_string = '';
    { local $/; $zone_string = <$fh>; }
    return parse_string( $zone_string, $args );
}

sub parse_string ( $zone_string, $args ) {
    if ( $args->{'to_lower'} && $args->{'to_upper'} ) {
        Carp::croak('You cannot send both "to_lower" and "to_upper"');
    }

    if ( Ref::Util::is_arrayref($zone_string) ) {
        $zone_string = join "\n", $zone_string->@*;
    }

    if ( Ref::Util::is_scalarref($zone_string) ) {
        $zone_string = $zone_string->$*;
    }

    $zone_string =~ /\n$/
      or $zone_string .= "\n";

    my $domain_owner = '';
    if ( exists $args->{'origin'} ) {
        my $domain = $args->{'origin'} // '';
        $domain =~ s/\.$//;
        $domain_owner = Cpanel::AcctUtils::DomainOwner::BAMP::getdomainownerBAMP( $domain, { 'default' => '' } );
    }

    # https://github.com/NLnetLabs/ldns/issues/67
    # $INCLUDE is not supported
    _replace_include_recursively( \$zone_string, $domain_owner );

    # This fixes $ORiGiN and $ttl
    _fix_lowercase_directives( \$zone_string );

    my $origin_name = $args->{'origin'} // '.';
    my $rrs;
    eval {
        $rrs = [ Cpanel::ZoneFile::Parse::parse_string( $zone_string, $origin_name )->@* ];
        1;
    } or do {
        my $error = $@;

        # rethrow normally
        $args->{'quiet'}
          or die $error;

        return [];
    };

    # Count the total number of records:
    # "record"  - record content
    # "control" - $TTL is apparently also included
    my $lines_no = grep $_->{'type'} ne 'comment', $rrs->@*;

    my @zone_string_lines = split /\n/xms, $zone_string;

    my $line = 0;
    my @output_rrs;
    foreach my $rr_idx ( 0 .. $rrs->$#* ) {
        my $rr_hashref = $rrs->[$rr_idx];
        my $line_idx   = delete $rr_hashref->{'line_index'};
        my $elem_type  = delete $rr_hashref->{'type'};

        $rr_hashref->{'Line'} = $line_idx + 1;

        # We do nothing with comments but set the type
        if ( $elem_type eq 'comment' ) {
            $rr_hashref->{'type'} = ':RAW';

            my $text = delete $rr_hashref->{'text'} // '';
            $rr_hashref->{'raw'} = $text;

            push @output_rrs, $rr_hashref;
            next;
        }

        my $line_diff = 1;                       # default
        my $next_rr   = $rrs->[ $rr_idx + 1 ];

        # Line calculation is funky...
        # * If there's a record ahead of us, great, we can use it
        #   BUT, since Cpanel::ZoneFile::Parse eliminates empty RAW records,
        #   we don't actually know if the next record is in the next line,
        #   or maybe after a few empty lines
        #   EXCEPT, we need to count on multilines having empty lines that canot
        #           be ignored
        #   SO, we take the next record and count up until we hit a non-empty line
        # * If there's no record ahead of us, we're the last record
        #   which would mean we can count the number of lines and decrease our
        #   current line count
        #   BUT, we need to ignore empty lines that come after us, because they should
        #        not be counted

        if ($next_rr) {

            # This is a bit complicated because a record could be multiline
            # *and* include empty lines
            # This could probably be written more succinctly (and with better
            # performance), but this should be fairly readable
            my $empty_line_count = 0;
            my $next_line_index  = $next_rr->{'line_index'};

            # Starting from the previous line, count empty lines
            while ( !length $zone_string_lines[ --$next_line_index ] ) {
                $empty_line_count++;
            }

            # Remove empty lines that appear between the next record and us
            $line_diff = $next_rr->{'line_index'} - $empty_line_count - $line_idx;
        }
        else {
            # No additional records
            # So take last line, removing all empty lines until this record
            # and decrease it from our index
            my $empty_line_count = 0;
            my $next_line_index  = @zone_string_lines;

            # Starting from the last line, count empty lines
            while ( !length $zone_string_lines[ $next_line_index-- ] ) {
                $empty_line_count++;
            }

            $line_diff = ( @zone_string_lines + 1 ) - $line_idx - $empty_line_count;
        }

        if ( $elem_type eq 'control' ) {
            my $text = delete $rr_hashref->{'text'};

            if ( $text =~ /^\$ORIGIN/xmsi ) {
                $line++;
                next;
            }

            if ( $text =~ /^\$ttl\s+(\S+)$/xmsi ) {
                $rr_hashref->{'type'} = '$TTL';
                $rr_hashref->{'ttl'}  = $1;
            }

            push @output_rrs, $rr_hashref;
            next;
        }

        # We expect at this point to have 'control' or 'record'
        if ( $elem_type ne 'record' ) {
            Carp::croak("Unknown element type: '$elem_type'");
        }

        my $rr_type = delete $rr_hashref->{'record_type'} // '';

        if ( $rr_type eq 'SOA' ) {
            $rr_hashref->{'Lines'} = $line_diff;
        }

        $rr_hashref->{'class'} = 'IN';
        $rr_hashref->{'type'}  = $rr_type;

        my $dname = delete $rr_hashref->{'dname'};
        $rr_hashref->{'name'} = $dname;

        $dname =~ /\.$/xms
          or $rr_hashref->{'name'} = "$dname.$origin_name";

        my @rdata_txt = ( delete $rr_hashref->{'data'} )->@*;

        # add fields callers expect for RRs
        if ( my $keys = $DIRECT_CONVERT{$rr_type} ) {
            $keys->@* == @rdata_txt
              or Carp::croak(
                sprintf "Incorrect '$rr_type' values (%d) vs. record keys (%d)",
                scalar $keys->@*,
                scalar @rdata_txt,
              );

            $rr_hashref->@{ $keys->@* } = @rdata_txt;
        }
        elsif ( my $cb = $CALLBACK_CONVERT{$rr_type} ) {
            eval {
                $cb->( $rr_hashref, @rdata_txt );
                1;
            } or do {
                my $error = $@;
                Carp::croak("Cannot convert with callback for type '$rr_type': $@");
            };
        }
        else {
            Carp::croak("Unknown record: '$rr_type'");
        }

        if ( $args->{'tolower'} ) {
            $rr_hashref->{$_} = lc $rr_hashref->{$_} for grep defined $rr_hashref->{$_}, KEYS_TO_CASE();
        }
        elsif ( $args->{'toupper'} ) {
            $rr_hashref->{$_} = uc $rr_hashref->{$_} for grep defined $rr_hashref->{$_}, KEYS_TO_CASE();
        }

        push @output_rrs, $rr_hashref;
    }

    return \@output_rrs;
}

1;

__END__

=pod

=head1 SYNOPSIS

    use Cpanel::Net::DNS::ZoneFile::LDNS;
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'text' => $text );

    # same thing:
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse();

=head1 DESCRIPTION

This module replaces the now-removed
C<Cpanel::CPAN::Cpanel::Net::DNS::ZoneFile::Fast> in
parsing a DNS zone file. It uses
L<C<libldns>|https://www.nlnetlabs.nl/projects/ldns/about/>.

This module works as a drop-in replacement (almost entirely one-to-one feature
and bug compatibility). If you don't like its interface or output, well... me
neither.

=head1 FUNCTIONS

=head2 parse

Primary function to parse strings, files, and file handles.

    # Parse a string
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse($text);
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(\$text);

    # Parse an arrayref of strings
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(\@text);

    # All the above, but explicit
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'text' => $text );

    # Parse a file
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'file' => $filename );

    # Parse a file handle
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'fh' => $filehandle );

You can also provide the origin:

    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(
        'text'   => $text,
        'origin' => 'example.com',
    );

You can prevent exceptions by adding the C<quiet> argument:

    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(
        'text'  => $text,
        'quiet' => 1,
    );

Two options are availale for "normalizing" the output names, compatible
with L<Net::DNS::ZoneFile::Fast>:

    # lowercase all names
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(
        'text'     => $text,
        'to_lower' => 1,
    );

    # uppercase all names
    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse(
        'text'     => $text,
        'to_upper' => 1,
    );

The arguments C<to_lower> and C<to_upper> will take affect on the
following record items:

=over 4

=item * C<name>

=item * C<cname>

=item * C<dname>

=item * C<mname>

=item * C<rname>

=item * C<nsdname>

=item * C<ptrdname>

=item * C<txtdname>

=item * C<exchange>

=item * C<target>

=item * C<mbox>

=back

DNS zone files must end in a newline. If your input (whether file, file
handle, or string) does not end in a newline, one will be added.

Specifically, C<soft_errors> are B<NOT> supported. If you try to use
them, it will crash and burn and be loud about it.

=head2 parse_file

    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse_file(
        $filename,
        { 'origin' => $origin, ... },
    );

All of the arguments defined in the overarching C<parse> function above
can be provided to this function in a hashref as a second argument.

This is the implementation that C<parse> uses.

=head2 parse_fh

    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse_fh(
        $fh,
        { 'origin' => $origin, ... },
    );

All of the arguments defined in the overarching C<parse> function above
can be provided to this function in a hashref as a second argument.

This is the implementation that C<parse> uses.

=head2 parse_string

    my $rrset = Cpanel::Net::DNS::ZoneFile::LDNS::parse_string(
        $text,
        { 'origin' => $origin, ... },
    );

All of the arguments defined in the overarching C<parse> function above
can be provided to this function in a hashref as a second argument.

This is the implementation that C<parse> uses.

=head1 SEE ALSO

=over 4

=item * L<cPstrict>

=item * L<Carp> (C<croak>)

=item * L<Path::Tiny>

=item * L<Cpanel::LoadFile>

=item * L<Cpanel::ZoneFile::Parse>

=item * L<Cpanel::DnsUtils::CAA>

=item * L<Cpanel::DnsUtils::GenericRdata>

The two above modules are used for creating the legacy value of a CAA
record that is listed as TYPE257. libldns parses it as CAA with the
new value, but not the legacy value.

=back

