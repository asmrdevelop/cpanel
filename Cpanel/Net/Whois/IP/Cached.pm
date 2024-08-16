package Cpanel::Net::Whois::IP::Cached;

# cpanel - Cpanel/Net/Whois/IP/Cached.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class should encapsulate all interaction with WHOIS servers.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Debug                ();
use Cpanel::JSON                 ();
use Cpanel::CachedCommand::Utils ();
use Cpanel::LoadFile             ();
use Cpanel::IP::Expand           ();
use Cpanel::Exception            ();
use Cpanel::Encoder::Cleaner     ();
use Try::Tiny;

my $EXPIRE_TIME = ( 86400 * 7 );    # 7 days

our $WHOIS_TIMEOUT = 30;            # seconds

#NOTE: This module currently doesn't need to use an object; however,
#it's being left this way in the interest of potential future expansion.
sub new {
    my ($class) = @_;

    return bless {}, $class;
}

###########################################################################
#
# Method:
#    lookup_address
#
# Description:
#    Lookup an IPv4 or IPv6 address in the whois IP database.
#
# Arguments:
#   $address - An IPv4 or IPv6 address
#
# Returns:
#   Cpanel::Net::Whois::IP::Cached::Response object -
#     If the lookup was successful and a valid
#     response was received from the IP server.
#   undef -
#     Returned when any failure is encountered.
#
sub lookup_address {
    my ( $self, $unexpanded_address ) = @_;

    my $address = Cpanel::IP::Expand::expand_ip($unexpanded_address);

    my $cached_contents;

    if ( !length $address ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide an [asis,IP] Address.' );
    }

    # If the cache is missing or cannot be loaded _load_cached_address_lookup
    # will fail.  Since this is a cache we will just proceed on.
    try {
        $cached_contents = $self->_load_cached_address_lookup($address);
    };

    if ($cached_contents) {
        return $self->_parse_whois_response($cached_contents);
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Alarm');
    Cpanel::LoadModule::load_perl_module('Net::Whois::IANA');
    my $response;
    {
        # IO::Socket::INET has a timeout parameter, but it only applies to connect(). So, use alarm instead.
        my $alarm = Cpanel::Alarm->new(
            $WHOIS_TIMEOUT,
            sub {
                die Cpanel::Exception::create_raw( 'Timeout', "The whois query for the address '$address' took longer than $WHOIS_TIMEOUT seconds." );
            }
        );

        # Warnings need to be suppressed as whois servers
        # can be offline or blocking due to query maximums.
        local $SIG{__WARN__} = sub { };
        try {
            $response = Net::Whois::IANA->new()->whois_query( -ip => $address );
        }
        catch {
            local $@ = $_;
            my $err = $_;
            Cpanel::Debug::log_warn( Cpanel::Exception::get_string($err) );
        };
    }

    return if !$response;

    Cpanel::LoadModule::load_perl_module('Net::CIDR');

    # validate and clean up CIDRs
    for ( @{ $response->{cidr} } ) { $_ = Net::CIDR::cidrvalidate( $_ // '' ) or return }

    $self->_write_cached_address_lookup( $address, $response );

    return $self->_parse_whois_response($response);
}

# Note: _write_cached_address_lookup is mocked in testing
# if you change this here, you must change it in the test.
sub _write_cached_address_lookup {
    my ( $self, $address, $response ) = @_;

    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename( __PACKAGE__, $address );

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');

    # Its possible that there are two or more processes doing whois
    # looks on the same ip. We always want to keep the newest one
    # so we overwrite below.
    Cpanel::FileUtils::Write::overwrite( $datastore_file, Cpanel::JSON::Dump($response), 0640 );

    return 1;
}

# Note: _load_cached_address_lookup is mocked in testing
# if you change this here, you must change it in the test.
sub _load_cached_address_lookup {
    my ( $self, $address ) = @_;

    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename( __PACKAGE__, $address );
    if ( -e $datastore_file && ( stat(_) )[9] > ( time() - $EXPIRE_TIME ) ) {

        # Cpanel::JSON::LoadFile was not used here
        # because we want to generate an exception
        # in the event the file cannot be loaded.
        #
        # LoadFile only warns which needs to be suppressed
        # since loading the cache is not fatal.
        #
        my $contents = Cpanel::LoadFile::load($datastore_file);

        return Cpanel::JSON::Load($contents);
    }
    return;
}

sub _parse_whois_response {
    my ( $self, $response ) = @_;

    my $class = ref($self) . '::Response';

    return $class->new(%$response);
}

package Cpanel::Net::Whois::IP::Cached::Response;

use strict;

use Cpanel::LoadModule ();

sub new {
    my ( $class, %params ) = @_;

    return bless { _params => \%params }, $class;
}

# Parameters to this method match the return of the whois_query() method of Net::Whois::IANA.
sub get {
    my ( $self, $attr ) = @_;

    my $raw_value = $self->{'_params'}{$attr};

    #Occasionally “cidr” comes back from IANA as “low - high”
    #rather than “low/mask”. Ensure that the caller always does indeed
    #receive back CIDR notation.

    if ( $attr eq 'descr' ) {
        return Cpanel::Encoder::Cleaner::get_clean_utf_string($raw_value);
    }
    if ( $attr eq 'cidr' && 'ARRAY' eq ref $raw_value ) {
        my @vals = @$raw_value;

        for my $v (@vals) {
            next if $v !~ m<\A (\S+) \s* - \s* (\S+) \z>x;

            Cpanel::LoadModule::load_perl_module('Cpanel::IP::Convert');

            $v = Cpanel::IP::Convert::start_end_address_to_cidr( $1, $2 );
        }

        return \@vals;
    }

    return $raw_value;
}

1;
