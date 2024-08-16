package Cpanel::ZoneEdit;

# cpanel - Cpanel/ZoneEdit.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;
use Cpanel::DnsUtils::UsercPanel    ();
use Cpanel::Encoder::URI            ();
use Cpanel::AdminBin::Call          ();
use Cpanel::JSON                    ();
use Cpanel::Locale                  ();
use Cpanel::Server::Type::Role::DNS ();

my $locale;
my %KEYMAP = ( 'line' => 'Line', 'ttl' => 'ttl', 'name' => 'name', 'class' => 'class', 'address' => 'address', 'type' => 'type', 'txtdata' => 'txtdata', 'preference' => 'preference', 'exchange' => 'exchange' );

sub ZoneEdit_init { }

sub ZoneEdit_printzone ($domain) {

    if ( Cpanel::Server::Type::Role::DNS->is_enabled() ) {
        my $results = _fetchzone( 'domain' => $domain );

        print Cpanel::JSON::Dump($results);
    }

    return;
}

# Can only be called with json or xml api because it uses
# a non-standard return
sub api2_fetchzone (%opts) {
    my $results = _fetchzone(%opts);
    return [$results];
}

# Can only be called with json or xml api because it uses
# a non-standard return
sub api2_fetchzones {
    my $results = _adminbin_call( 'Cpanel', 'zone', 'RAWFETCHALL' );
    return [$results];
}

sub _fetchzone (%OPTS) {

    my $domain  = $OPTS{'domain'};
    my $results = _adminbin_call( 'Cpanel', 'zone', 'FETCH', $domain, $OPTS{customonly} ? 1 : 0 );

    if ( ref $results->{'record'} eq 'ARRAY' ) {
        for ( 0 .. $#{ $results->{'record'} } ) {
            $results->{record}[$_]{record} =
              ( $results->{record}[$_]{address} || $results->{record}[$_]{cname} || $results->{record}[$_]{txtdata} );
            $results->{record}[$_]{line} = ( $results->{record}[$_]{Line} );
        }
        foreach my $key ( keys %KEYMAP ) {
            if ( exists $OPTS{$key} && defined $OPTS{$key} ) {
                my %MULTITYPES = map { $_ => undef } split( /[\|\,]/, $OPTS{$key} );
                my $mapped     = $KEYMAP{$key};
                @{ $results->{'record'} } = grep { defined $_->{$mapped} && exists $MULTITYPES{ $_->{$mapped} } } @{ $results->{'record'} };
            }
        }
    }

    return $results;
}

sub fetchzone_raw ($zonename) {
    return Cpanel::AdminBin::Call::call( 'Cpanel', 'zone', 'RAWFETCH', $zonename );
}

# <?cp tag compat

sub api2_fetch_cpanel_generated_domains {
    my %OPTS = @_;
    my @RET;
    my $domain                       = $OPTS{'domain'};
    my $cpanel_generated_domains_ref = Cpanel::DnsUtils::UsercPanel::get_cpanel_generated_dns_names($domain);
    foreach my $domain ( keys %{$cpanel_generated_domains_ref} ) {
        next unless length $domain;
        push @RET, { 'domain' => $domain };
    }
    return \@RET;
}

# <?cp ZoneEdit::fetchzone_records ?> Compatiable
#
sub api2_fetchzone_records {
    my $results = _fetchzone(@_);
    return $results->{record} || [];
}

sub _serialize_request ($opt_ref) {
    my @KEYLIST;
    foreach my $opt ( keys %$opt_ref ) {
        push @KEYLIST, Cpanel::Encoder::URI::uri_encode_str($opt) . '=' . Cpanel::Encoder::URI::uri_encode_str( $opt_ref->{$opt} );
    }
    return join( '&', @KEYLIST );
}

my $zoneedit_simplezoneedit = { needs_feature => { match => 'any', features => [qw(zoneedit simplezoneedit)] } };

my $allow_demo = { allow_demo => 1 };

our %API = (
    remove_zone_record => $zoneedit_simplezoneedit,
    edit_zone_record   => {
        needs_feature => { match => 'any', features => [qw(zoneedit simplezoneedit changemx)] },
    },
    add_zone_record   => $zoneedit_simplezoneedit,
    fetchzone         => $allow_demo,
    fetchzones        => $allow_demo,
    fetchzone_records => $allow_demo,
    get_zone_record   => {
        func       => 'api2_fetchzone_records',
        allow_demo => 1,
    },
    resetzone                      => { needs_feature => 'zoneedit' },
    fetch_cpanel_generated_domains => $allow_demo,
);

$_->{'needs_role'} = 'DNS' for values %API;

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

## no critic (Subroutines::RequireArgUnpacking)

sub api2_resetzone {

    my %OPTS = @_;

    my $domain = $OPTS{'domain'};

    my $results = _adminbin_call( 'Cpanel', 'zone', 'RESET', $domain );

    return [ { result => $results } ];
}

sub api2_add_zone_record {
    my %OPTS = ( @_, unencoded => 1 );
    if ( not $OPTS{'name'} ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{'zoneedit'} = $locale->maketext(
            'Invalid [asis,DNS] record: No name provided.',
        );
        return;
    }

    my $domain = $OPTS{'domain'};

    my $res = _adminbin_call( 'Cpanel', 'zone', 'ADD', $domain, _serialize_request( \%OPTS ) );
    return [ { result => $res } ];
}

sub api2_edit_zone_record {

    my %OPTS = ( @_, unencoded => 1 );

    my $domain = $OPTS{'domain'};
    my $res    = _adminbin_call( 'Cpanel', 'zone', 'EDIT', $domain, _serialize_request( \%OPTS ) );
    return [ { result => $res } ];
}

sub api2_remove_zone_record (%OPTS) {

    my $domain = $OPTS{'domain'};

    # avoid warnings
    my $line;
    if ( exists $OPTS{line} and abs int $OPTS{line} ) {
        $line = abs int $OPTS{line};
    }
    elsif ( exists $OPTS{Line} and abs int $OPTS{Line} ) {
        $line = abs int $OPTS{Line};
    }

    my $res = _adminbin_call( 'Cpanel', 'zone', 'DELETE', $domain, $line );
    return [ { result => $res } ];
}

sub _adminbin_call (@args) {

    return try { Cpanel::AdminBin::Call::call(@args) }
    catch {
        {
            status    => 0,
            statusmsg => $_->get_string_no_id(),
        };
    };
}

1;
