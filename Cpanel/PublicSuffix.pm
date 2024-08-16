package Cpanel::PublicSuffix;

# cpanel - Cpanel/PublicSuffix.pm                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Make this lazy-load because we’ll load it dynamically below.
use parent -norequire, 'IO::Socket::SSL::PublicSuffix';

use Cpanel::AdminBin::Serializer         ();
use Cpanel::AdminBin::Serializer::FailOK ();
our $VERSION = '1.2';    # must not end in zero for compat

our $public_suffix_db;

BEGIN {
    if ( !$INC{'Mozilla/PublicSuffix.pm'} ) {
        $INC{'Mozilla/PublicSuffix.pm'}       = __FILE__;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
                                                             # This is for HTTP::CookieJar so we do not load two publicsuffix modules
        *Mozilla::PublicSuffix::public_suffix = sub {
            __PACKAGE__->get_io_socket_ssl_publicsuffix_handle()->public_suffix(@_);
        };
    }
}

my %IS_SIMPLE_TLD = (
    com            => 1,
    net            => 1,
    org            => 1,
    info           => 1,
    cloud          => 1,
    arpa           => 1,
    'in-addr.arpa' => 1,
    'ip6.arpa'     => 1,
);

sub domain_isa_tld {
    my ($domain) = @_;

    return 1 if ( $domain =~ tr/.// ) == 0;

    return 1 if $IS_SIMPLE_TLD{$domain};

    return 1 if get_io_socket_ssl_publicsuffix_handle()->public_suffix($domain) eq $domain;

    return 0;
}

sub get_io_socket_ssl_publicsuffix_handle {
    return ( $public_suffix_db ||= bless {}, __PACKAGE__ );
}

sub public_suffix {
    $_[0]->_ensure_loaded();
    return $_[0]->SUPER::public_suffix( @_[ 1 .. $#_ ] );
}

sub _ensure_loaded {
    if ( !scalar keys %{ $_[0] } ) {

        # Dyanamic loading for perlcc
        require IO::Socket::SSL::PublicSuffix;

        # If the cache is missing or cannot be loaded _load_cached_publicsuffix_db
        # will fail.  Since this is a cache we will just proceed on.
        local $@;
        warn if !eval {    # Try::Tiny will clobber $_[0]
            my $db = _load_cached_publicsuffix_db();
            @{ $_[0] }{ keys %$db } = values %$db;
            1;
        };

        if ( scalar keys %{ $_[0] } ) {
            return;
        }

        my $db = IO::Socket::SSL::PublicSuffix->default();

        die "Cold not load IO::Socket::SSL::PublicSuffix default database" if !$db;

        warn if !eval { _write_cached_publicsuffix_db($db); 1 };

        @{ $_[0] }{ keys %$db } = values %$db;
    }
    return;

}

sub _DATASTORE_FILE {
    require Cpanel::CachedCommand::Utils;
    return Cpanel::CachedCommand::Utils::get_datastore_filename( __PACKAGE__, 'default' );
}

sub _get_publicsuffix_size_mtime {
    if ( $INC{'IO/Socket/SSL/PublicSuffix.pm'} ) {
        return ( stat( $INC{'IO/Socket/SSL/PublicSuffix.pm'} ) )[ 7, 9 ];
    }
    foreach my $path (@INC) {
        my ( $size, $mtime ) = ( stat("$path/IO/Socket/SSL/PublicSuffix.pm") )[ 7, 9 ];
        return ( $size, $mtime ) if $size;
    }
    die "Cannot locate: IO/Socket/SSL/PublicSuffix.pm";
}

sub _load_cached_publicsuffix_db {
    my $datastore_file = _DATASTORE_FILE();
    if ( -e $datastore_file ) {
        my $datastore_mtime = ( stat(_) )[9];
        my ( $public_suffix_size, $public_suffix_mtime ) = _get_publicsuffix_size_mtime();
        return undef if !$public_suffix_size || !$public_suffix_mtime || $public_suffix_mtime > $datastore_mtime;
        my $cache = Cpanel::AdminBin::Serializer::FailOK::LoadFile($datastore_file);
        if ( ref $cache eq 'HASH' && $cache->{'VERSION'} && $cache->{'size'} && $cache->{'VERSION'} == $VERSION && $cache->{'size'} == $public_suffix_size ) {
            return $cache->{'data'};
        }
    }
    return undef;
}

# Note: _write_cached_address_lookup is mocked in testing
# if you change this here, you must change it in the test.
sub _write_cached_publicsuffix_db {
    my ($db) = @_;

    my $datastore_file = _DATASTORE_FILE();

    my ( $public_suffix_size, $public_suffix_mtime ) = _get_publicsuffix_size_mtime();
    my $unblessed = { %{$db} };

    # Its possible that there are two or more processes doing whois
    # looks on the same ip. We always want to keep the newest one
    # so we overwrite below.
    require Cpanel::FileUtils::Write;
    Cpanel::FileUtils::Write::overwrite( $datastore_file, Cpanel::AdminBin::Serializer::Dump( { 'VERSION' => $VERSION, 'size' => $public_suffix_size, 'data' => $unblessed } ), 0640 );

    return 1;
}

sub clear_cache {
    my $datastore_file = _DATASTORE_FILE();
    unlink $datastore_file;
    return;
}

1;
